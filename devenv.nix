# SPDX-License-Identifier: LGPL-3.0-or-later
#
# Canonical development environment; package outputs use `package.nix`.
# Tasks enter the SDK root and place install prefixes under selected cache roots.
# The shell installs tools only.

{ pkgs, ... }:

let
  zig = pkgs.zig_0_16;

  # Shared Zig flags for package and consumer tasks.
  zigFlags = "-j8 --summary all";

  # Per-root cache flags for the SDK and consumer builds.
  flags = "${zigFlags} --cache-dir \"$mpfr_cache\"";

  consumerFlags = "${zigFlags} --cache-dir \"$consumer_cache\"";

  # Resolve and quote this repository root, not the caller's working directory.
  sdkRoot = pkgs.lib.escapeShellArg (builtins.toString ./.);

  # Enter this repository for each task; stop if the directory change fails.
  inSdk = ''cd ${sdkRoot} || exit 1'';

  # Use the caller's local cache, then XDG_CACHE_HOME, then TMPDIR; refuse an unset root.
  # Set the local cache for direct tasks; set the global cache when available.
  cacheDir = caller: ''
if [ -n "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
  mpfr_cache="$ZIG_LOCAL_CACHE_DIR"
elif [ -n "''${XDG_CACHE_HOME:-}" ]; then
  mpfr_cache="$XDG_CACHE_HOME/zig-local-cache"
elif [ -n "''${TMPDIR:-}" ]; then
  mpfr_cache="$TMPDIR/zig-local-cache"
else
  echo "${caller}: ZIG_LOCAL_CACHE_DIR, XDG_CACHE_HOME and TMPDIR are all unset, so" >&2
  echo "no location outside this checkout was named, and none was invented." >&2
  echo "Export one of the three at an approved mount." >&2
  exit 1
fi

if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
  ZIG_LOCAL_CACHE_DIR="$mpfr_cache"
  export ZIG_LOCAL_CACHE_DIR
fi
if [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
  if [ -n "''${XDG_CACHE_HOME:-}" ]; then
    ZIG_GLOBAL_CACHE_DIR="$XDG_CACHE_HOME/zig-global-cache"
    export ZIG_GLOBAL_CACHE_DIR
  elif [ -n "''${TMPDIR:-}" ]; then
    ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
    export ZIG_GLOBAL_CACHE_DIR
  fi
fi
mkdir -p "$mpfr_cache"
if [ -n "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
  mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
fi
'';

  # Install each linkage variant under its own cache-root prefix.
  installTo = task: variant: ''
${cacheDir task}
install_prefix="$mpfr_cache/mpfr-install/${variant}"
mkdir -p "$install_prefix"
echo "${task}: install prefix $install_prefix" >&2
'';
in
{
  packages = [
    zig
    pkgs.pkg-config
    pkgs.gnumake
    pkgs.nix
  ];

  assertions = [
    {
      assertion = zig.version == "0.16.0";
      message = "This SDK targets Zig 0.16.0; the environment resolved ${zig.version}.";
    }
  ];

  # Keep the default output lazy.
  outputs = rec {
    static = pkgs.callPackage ./package.nix { inherit zig; };
    shared = pkgs.callPackage ./package.nix {
      inherit zig;
      linkage = "dynamic";
    };
    default = static;
  };

  tasks = {
    "sdk:build" = {
      description = "Install the default (static) library outside the checkout";
      exec = ''
        ${inSdk}
        ${installTo "sdk:build" "static"}
        zig build --prefix "$install_prefix" ${flags}
      '';
    };
    "sdk:build:static" = {
      description = "Install the static library outside the checkout";
      exec = ''
        ${inSdk}
        ${installTo "sdk:build:static" "static"}
        zig build -Dlinkage=static --prefix "$install_prefix" ${flags}
      '';
    };
    "sdk:build:shared" = {
      description = "Install the shared library outside the checkout";
      exec = ''
        ${inSdk}
        ${installTo "sdk:build:shared" "dynamic"}
        zig build -Dlinkage=dynamic --prefix "$install_prefix" ${flags}
      '';
    };
    "sdk:test" = {
      description = "Run the behaviour suite";
      exec = ''
        ${inSdk}
        ${cacheDir "sdk:test"}
        zig build test ${flags}
      '';
    };
    "sdk:test:release-safe" = {
      description = "Run the behaviour suite in ReleaseSafe";
      exec = ''
        ${inSdk}
        ${cacheDir "sdk:test:release-safe"}
        zig build test -Doptimize=ReleaseSafe ${flags}
      '';
    };
    "sdk:smoke" = {
      description = "Run the deterministic example";
      exec = ''
        ${inSdk}
        ${cacheDir "sdk:smoke"}
        zig build smoke ${flags}
      '';
    };
    # Compile only; no target binary or emulator runs.
    "sdk:check" = {
      description = "Compile the facade, the suite and the example; run nothing";
      exec = ''
        ${inSdk}
        ${cacheDir "sdk:check"}
        zig build check ${flags}
      '';
    };
    "sdk:matrix" = {
      description = "Compile sdk:check for the six required targets; run nothing";
      exec = ''
        ${inSdk}
        ${cacheDir "sdk:matrix"}
        zig build matrix ${flags}
      '';
    };
    "sdk:consumer" = {
      description = "Run the dependent consumer package";
      # The consumer is a separate build root and needs its own cache.
      exec = ''
        ${inSdk}
        ${cacheDir "sdk:consumer"}
        consumer_cache="$mpfr_cache/mpfr-consumer"
        mkdir -p "$consumer_cache"
        cd consumer && zig build run ${consumerFlags}
      '';
    };
    "sdk:install" = {
      description = "Install the prefix an installed-C consumer expects";
      exec = ''
        ${inSdk}
        ${installTo "sdk:install" "static"}
        zig build install --prefix "$install_prefix" ${flags}
      '';
    };
  };

  enterShell = ''
    export PATH="${zig}/bin:$PATH"

    # Fill only missing Zig cache variables from XDG_CACHE_HOME or TMPDIR.
    # Caller paths win; defaults come from XDG_CACHE_HOME or TMPDIR.
    if [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ] || [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        mpfr_cache_root="$XDG_CACHE_HOME"
      elif [ -n "''${TMPDIR:-}" ]; then
        mpfr_cache_root="$TMPDIR"
      else
        mpfr_cache_root=
      fi

      if [ -n "$mpfr_cache_root" ]; then
        : "''${ZIG_GLOBAL_CACHE_DIR:=$mpfr_cache_root/zig-global-cache}"
        : "''${ZIG_LOCAL_CACHE_DIR:=$mpfr_cache_root/zig-local-cache}"
        export ZIG_GLOBAL_CACHE_DIR ZIG_LOCAL_CACHE_DIR
        mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR"
      elif [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ] || [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
        echo "mpfr devenv: XDG_CACHE_HOME and TMPDIR are both unset, so no Zig" >&2
        echo "cache location is chosen here. Export ZIG_GLOBAL_CACHE_DIR and" >&2
        echo "ZIG_LOCAL_CACHE_DIR at an approved mount; every task writes" >&2
        echo "outside the checkout and refuses without one." >&2
      fi
      unset mpfr_cache_root
    fi

    echo "MPFR Zig SDK - compiler $(zig version), GMP provider vendor/gmp 6.3.0"
    echo "  devenv task sdk:build | sdk:test | sdk:smoke | sdk:check | sdk:matrix"
    echo "  devenv task sdk:consumer"
    echo "  ./check-upstream-baseline.sh    every carried upstream byte, against the pin"
    echo "  devenv build outputs.static | devenv build outputs.shared"
    echo
    echo "Every task runs in this SDK's own directory, whichever directory you run"
    echo "it from, and every task names its cache and prefix under"
    echo "$ZIG_LOCAL_CACHE_DIR."
  '';
}
