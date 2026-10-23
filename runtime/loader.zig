// SPDX-License-Identifier: LGPL-3.0-or-later
//! Process-global dynamic loader for translated C APIs.
//! `load` publishes a complete table; failures close providers and allow retries.

const std = @import("std");
const builtin = @import("builtin");

/// An explicit absolute path or a platform-searched library name.
pub const LoadSource = union(enum) {
    /// Absolute path; relative paths are invalid.
    path: []const u8,
    /// Basename or SONAME; separators and NUL bytes are invalid.
    system: []const u8,
};

/// Errors returned when a provider cannot be loaded.
pub const LoadError = error{
    /// Empty path or library name.
    EmptySource,
    /// Request exceeds `max_source_len`; it is never truncated.
    SourceTooLong,
    /// Path is not absolute, or a system name contains a separator or NUL.
    InvalidSource,
    /// This target has no dynamic loader.
    UnsupportedTarget,
    /// Platform loader refused the request or its dependencies.
    OpenFailed,
    /// A required translated symbol is absent.
    MissingSymbol,
    /// Provider validation failed after symbol resolution.
    ValidationFailed,
    /// A different provider is already loaded or loading.
    ProviderMismatch,
    /// The attempt's owner thread called `load` recursively.
    ReentrantLoad,
};

/// Maximum source length, in bytes.
pub const max_source_len = 32768;

const SourceRecord = struct {
    tag: enum(u8) { none = 0, path, system } = .none,
    len: u32 = 0,
    bytes: [max_source_len]u8 = undefined,

    fn set(self: *SourceRecord, request: LoadSource) void {
        const text = switch (request) {
            .path => |p| p,
            .system => |s| s,
        };
        @memcpy(self.bytes[0..text.len], text);
        self.len = @intCast(text.len);
        self.tag = switch (request) {
            .path => .path,
            .system => .system,
        };
    }

    /// Returns the remembered request, if any.
    pub fn source(self: *const SourceRecord) ?LoadSource {
        const text = self.bytes[0..self.len];
        return switch (self.tag) {
            .none => null,
            .path => .{ .path = text },
            .system => .{ .system = text },
        };
    }
};

/// Compares request kinds and bytes without normalization.
pub fn eqlSource(a: LoadSource, b: LoadSource) bool {
    return switch (a) {
        .path => |pa| switch (b) {
            .path => |pb| std.mem.eql(u8, pa, pb),
            .system => false,
        },
        .system => |sa| switch (b) {
            .system => |sb| std.mem.eql(u8, sa, sb),
            .path => false,
        },
    };
}

fn validateSource(source: LoadSource) LoadError!void {
    const text = switch (source) {
        .path => |p| p,
        .system => |s| s,
    };
    if (text.len == 0) return error.EmptySource;
    if (text.len > max_source_len) return error.SourceTooLong;
    if (std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidSource;
    switch (source) {
        .path => {
            const absolute = if (builtin.os.tag == .windows)
                switch (std.fs.path.getWin32PathType(u8, text)) {
                    .drive_absolute, .unc_absolute, .local_device, .root_local_device => true,
                    .relative, .rooted, .drive_relative => false,
                }
            else
                std.fs.path.isAbsolutePosix(text);
            if (!absolute) return error.InvalidSource;
        },
        .system => {
            for (text) |byte| {
                if (std.fs.path.isSep(byte)) return error.InvalidSource;
                if (builtin.os.tag == .windows and byte == ':') return error.InvalidSource;
            }
        },
    }
}

/// States of the configured module's table.
pub const Phase = enum(u8) {
    /// No provider is loaded; failed attempts also return here.
    not_loaded = 0,
    /// A thread is filling the table.
    loading = 1,
    /// The table is published and ready.
    ready = 2,
};

/// Readiness flag published with release ordering and read with acquire ordering.
pub const Ready = struct {
    phase: std.atomic.Value(u8) = .init(@backingInt(Phase.not_loaded)),

    /// True after a successful load.
    pub fn isReady(self: *const Ready) bool {
        return self.phase.load(.acquire) == @backingInt(Phase.ready);
    }

    /// Current loader state.
    pub fn state(self: *const Ready) Phase {
        return @fromBackingInt(@intCast(self.phase.load(.acquire)));
    }

    /// Publishes or withdraws a table state.
    pub fn set(self: *Ready, value: Phase) void {
        self.phase.store(@backingInt(value), .release);
    }
};

/// Kind of provider export stored in a symbol table.
pub const SymbolKind = enum {
    /// Function pointer with the translated header's signature.
    function,
    /// Address of exported data, not a copy.
    data,
};

/// One required exported symbol and its kind.
pub const Symbol = struct {
    /// Exported name as declared by the C header.
    name: [:0]const u8,
    /// Function or data address.
    kind: SymbolKind,
};

/// Panics when a routed call precedes a successful load.
/// Names the library and symbol in every optimization mode.
pub fn panicNotReady(library: []const u8, comptime symbol: []const u8) noreturn {
    std.debug.panic(
        "{s}: {s} was called before this module was loaded; call " ++
            "load({{ .path = \"...\" }}) or load({{ .system = \"...\" }}) first",
        .{ library, symbol },
    );
}

/// Whether this target has a dynamic loader.
pub const supported_target: bool = switch (builtin.os.tag) {
    .wasi, .emscripten, .freestanding => false,
    else => true,
};

/// Loader for one configured module; concurrent requests share attempts.
/// Successful providers are retained; failed attempts can be retried.
pub fn Loader(comptime Config: type) type {
    return struct {
        const LoaderType = @This();

        /// Table type filled by this loader.
        pub const table_type = Config.table;

        /// Current or undrained load attempt.
        attempt: ?Attempt = null,

        /// Request copy, read under the lock until publication.
        request: SourceRecord = .{},

        /// Thread-safe provider load; identical concurrent requests share an attempt.
        /// Returns `LoadError`; failures close the candidate, while a different provider is rejected.
        pub fn load(self: *LoaderType, source: LoadSource) LoadError!void {
            try validateSource(source);
            // Fast path: ready loads need one acquire read and no lock.
            if (Config.ready().isReady()) return self.accept(source);

            Config.sync.lock();
            while (true) {
                switch (Config.ready().state()) {
                    .ready => {
                        Config.sync.unlock();
                        return self.accept(source);
                    },
                    .loading => {
                        const attempt = &self.attempt.?;
                        if (attempt.owner == Config.sync.threadSelf()) {
                            Config.sync.unlock();
                            return error.ReentrantLoad;
                        }
                        if (!eqlSource(self.request.source().?, source)) {
                            Config.sync.unlock();
                            return error.ProviderMismatch;
                        }
                        // Same-request callers join the in-flight attempt.
                        attempt.waiters += 1;
                        while (Config.ready().state() == .loading) Config.sync.wait();
                        const result = attempt.result;
                        attempt.waiters -= 1;
                        // Keep the result until every attached waiter reads it.
                        Config.sync.broadcast();
                        Config.sync.unlock();
                        return result;
                    },
                    .not_loaded => {
                        // Do not start a retry until the previous waiters drain.
                        if (self.attempt != null) {
                            Config.sync.wait();
                            continue;
                        }
                        break;
                    },
                }
            }

            self.request.set(source);
            self.attempt = .{ .owner = Config.sync.threadSelf() };
            Config.ready().set(.loading);
            Config.sync.unlock();

            // Provider constructors run outside the lock; waiters use the attempt.
            const outcome = runAttempt(self.request.source().?);
            const succeeded = if (outcome) |_| true else |_| false;

            Config.sync.lock();
            self.attempt.?.result = outcome;
            Config.ready().set(if (succeeded) .ready else .not_loaded);
            // Wake all waiters to read this attempt's result.
            Config.sync.broadcast();
            // Keep the attempt until every waiter has returned.
            while (self.attempt.?.waiters > 0) Config.sync.wait();
            self.attempt = null;
            // Anyone waiting to start a retry was waiting for exactly this.
            Config.sync.broadcast();
            Config.sync.unlock();

            return outcome;
        }

        /// Returns the successful request, retained for the process lifetime, or null.
        pub fn loadedSource(self: *const LoaderType) ?LoadSource {
            if (!Config.ready().isReady()) return null;
            return self.request.source();
        }

        /// Checks a new request against the selected provider.
        fn accept(self: *const LoaderType, source: LoadSource) LoadError!void {
            // `accept` follows an acquire read of readiness.
            const published = self.request.source() orelse unreachable;
            if (eqlSource(published, source)) return;
            return error.ProviderMismatch;
        }

        /// Opens, resolves, and validates a candidate without publishing it.
        /// Closes the candidate on every failure path.
        fn runAttempt(source: LoadSource) LoadError!void {
            const handle = platform.open(source) catch |err| return err;

            var retain = false;
            defer if (!retain) platform.close(handle);

            if (@hasDecl(Config, "optional_symbols")) {
                inline for (Config.optional_symbols, 0..) |_, index| {
                    Config.assignMissing(index, Config.tablePtr());
                }
            }

            inline for (Config.symbols, 0..) |symbol, index| {
                const address = platform.lookup(handle, symbol.name) orelse
                    return error.MissingSymbol;
                Config.assign(index, Config.tablePtr(), address);
            }

            if (@hasDecl(Config, "optional_symbols")) {
                inline for (Config.optional_symbols, 0..) |symbol, index| {
                    if (platform.lookup(handle, symbol.name)) |address| {
                        Config.assignOptional(index, Config.tablePtr(), address);
                    }
                }
            }

            if (@hasDecl(Config, "validate")) {
                if (Config.validate(Config.tablePtr())) |refusal| {
                    std.debug.print("{s}: refusing this provider: {s}\n", .{
                        Config.library_name,
                        refusal,
                    });
                    return error.ValidationFailed;
                }
            }

            // The table points into this handle for the process lifetime.
            retain = true;
        }
    };
}

/// One active or undrained load attempt.
const Attempt = struct {
    /// Thread running the attempt, for reentrancy checks.
    owner: u64,
    /// Result published before leaving the loading state.
    result: LoadError!void = error.OpenFailed,
    /// Attached callers that have not read the result.
    waiters: usize = 0,
};

/// Windows loader path-buffer capacity, in UTF-16 code units.
const windows_path_units = 32768;

const platform = if (builtin.os.tag == .windows)
    Windows
else if (supported_target)
    Unix
else
    NoLoader;

/// Dynamic loading is unavailable for this target.
const NoLoader = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget };

    fn open(source: LoadSource) OpenError!*anyopaque {
        _ = source;
        return error.UnsupportedTarget;
    }
    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        _ = handle;
        _ = name;
        return null;
    }
    fn close(handle: *anyopaque) void {
        _ = handle;
    }
};

/// Unix dynamic-loader bindings.
const Unix = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget };

    fn open(source: LoadSource) OpenError!*anyopaque {
        const text = switch (source) {
            .path => |p| p,
            .system => |s| s,
        };
        var buffer: [max_source_len + 1]u8 = undefined;
        @memcpy(buffer[0..text.len], text);
        buffer[text.len] = 0;
        // RTLD_NOW rejects missing dependencies during open.
        // RTLD_LOCAL keeps symbols out of other SDKs' global lookups.
        return std.c.dlopen(
            // `dlopen` requires a sentinel-terminated path.
            buffer[0..text.len :0].ptr,
            .{ .NOW = true, .GLOBAL = false },
        ) orelse error.OpenFailed;
    }

    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        return std.c.dlsym(handle, name.ptr);
    }

    fn close(handle: *anyopaque) void {
        _ = std.c.dlclose(handle);
    }
};

const kernel32 = struct {
    extern "kernel32" fn LoadLibraryExW(
        file_name: [*:0]const u16,
        file: ?*anyopaque,
        flags: u32,
    ) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn GetProcAddress(module: *anyopaque, name: [*:0]const u8) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn FreeLibrary(module: *anyopaque) callconv(.winapi) i32;
};

/// Windows dynamic-loader bindings.
const Windows = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget, SourceTooLong };

    /// Search standard directories for names; paths with separators are used as given.
    /// The search excludes the current directory.
    const load_library_search_default_dirs: u32 = 0x0000_1000;
    const load_library_search_dll_load_dir: u32 = 0x0000_0100;

    fn open(source: LoadSource) OpenError!*anyopaque {
        const text = switch (source) {
            .path => |p| p,
            .system => |s| s,
        };
        if (text.len > windows_path_units) return error.SourceTooLong;
        var buffer: [windows_path_units + 1]u16 = undefined;
        const units = std.unicode.utf8ToUtf16Le(buffer[0..text.len], text) catch
            return error.OpenFailed;
        buffer[units] = 0;
        return kernel32.LoadLibraryExW(
            buffer[0..units :0],
            null,
            load_library_search_default_dirs | switch (source) {
                .path => load_library_search_dll_load_dir,
                .system => @as(u32, 0),
            },
        ) orelse error.OpenFailed;
    }

    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        return kernel32.GetProcAddress(handle, name.ptr);
    }

    fn close(handle: *anyopaque) void {
        _ = kernel32.FreeLibrary(handle);
    }
};
