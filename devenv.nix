# SPDX-License-Identifier: LGPL-3.0-or-later
#
# Canonical development environment.
#
# `packages` holds tools only, so entering the shell never builds the SDK. The
# packaging route is `outputs`, which are lazy derivations from the same
# `package.nix` the flake calls:
#
#   devenv build outputs.static
#   devenv build outputs.shared
#
# `devenv.yaml` pins the nixpkgs input; `devenv.lock` is written by whoever owns
# locks in this workspace.
#
# Two rules every task body below follows, and why neither is optional:
#
#   * It runs in this SDK's own directory. `devenv tasks run` and
#     `devenv shell -- <script>` both execute in the working directory of
#     whoever ran them, and `$DEVENV_ROOT` names that same caller directory -
#     for a shell entered with `--from path:<sdk>`, a project directory with no
#     `build.zig`, no `consumer/` and no `UPSTREAM-BASELINE.sha256` in it.
#   * It writes nothing into the checkout. `zig build`'s own default install
#     prefix is `zig-out` inside the source tree and its own default local cache
#     is `.zig-cache` beside it; this checkout is on a network mount.

{ pkgs, ... }:

let
  zig = pkgs.zig_0_16;

  # The one flag list every canonical `zig build` in this file carries, so the
  # eight jobs and the summary are written once and nowhere else. Every command
  # also names its cache directory outright, because a `zig build` that is not
  # told one creates `.zig-cache` inside the checkout, and no command may
  # depend on a variable having been exported to avoid that.
  zigFlags = "-j8 --summary all";

  # This SDK's own graph, on the directory `cacheDir` resolved and created.
  flags = "${zigFlags} --cache-dir \"$mpfr_cache\"";

  # The consumer is a second build root, so it carries the same flags beside its
  # own directory: two build graphs must not share one manifest.
  consumerFlags = "${zigFlags} --cache-dir \"$consumer_cache\"";

  # This SDK's own directory, quoted for the shell.
  #
  # `./.` in an expression is relative to the file that writes it, so this is
  # `mpfr/` and not the directory a caller happens to be standing in.
  # `builtins.toString` renders the path the evaluation already holds;
  # `${./.}` would instead copy this whole SDK into the store - every vendored
  # GMP byte and all 2810 baseline records - on every evaluation, into a
  # read-only path where a task could write nothing beside what it built.
  # `pkgs.lib` is nixpkgs' own string helper, and this is the workspace's
  # quoting convention (`htscodecs/package.nix:84` uses the same function), so
  # quoting costs this file no module argument the caller has to supply.
  sdkRoot = pkgs.lib.escapeShellArg (builtins.toString ./.);

  # First line of every task body, without exception.
  # `|| exit 1`: a `cd` that failed would leave the task running in the very
  # caller directory this is here to escape from.
  inSdk = ''cd ${sdkRoot} || exit 1'';

  # Where build output and the Zig cache may go, as one rule the tasks apply at
  # run time. `$ZIG_LOCAL_CACHE_DIR` wins, because a caller that exported it
  # has already chosen an approved mount; `$XDG_CACHE_HOME` is next, because
  # that is where the Base Directory Specification puts a cache; `$TMPDIR` is
  # last, because that is the host's own scratch policy. A caller that named
  # none of the three is told which are missing and is given no location: this
  # file does not get to invent one, and `/tmp` is not one of the approved
  # mounts on this host. These three names in this order are also what
  # `enterShell` below fills in, and this block fills the same two Zig cache
  # names itself before any compiler runs, because `devenv tasks run` does not
  # run that hook: a task that reached `zig build` with them unset would put its
  # cache where the caller never chose.
  #
  # It sets `mpfr_cache`, fills and exports `ZIG_LOCAL_CACHE_DIR` and
  # `ZIG_GLOBAL_CACHE_DIR` only where the caller left them unset, creates the
  # directories it then hands to `zig build`, and stops the task if no
  # caller-named location exists. It never prints, so no task has to read a
  # command substitution whose failure would have to be checked twice. The body
  # is written flush left because this text is interpolated into a task body
  # verbatim, and its own indentation is the indentation the script carries.
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

  # The install prefix for one delivery variant: beneath the Zig local cache,
  # never inside the checkout. One directory per variant, so a static install
  # and a shared install cannot land on one another. `task` names the caller in
  # the message, because "which task wrote where" is the only question a log of
  # this can be asked afterwards.
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

  # `rec` keeps `default` lazy, so nothing here is realised on shell entry.
  # `zig` is named rather than left to callPackage, which would fill it from
  # `pkgs.zig` - a moving alias, not the pinned compiler.
  outputs = rec {
    static = pkgs.callPackage ./package.nix { inherit zig; };
    shared = pkgs.callPackage ./package.nix {
      inherit zig;
      linkage = "dynamic";
    };
    default = static;
  };

  # Real commands from this repository's build graph. Each is an entry point, not
  # a result; `README.md` section 3 keeps that distinction explicit.
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
    # Compiles only: no target binary runs and no emulator is assumed.
    # wasm32-wasi is expected to fail on the vendored GMP provider's signal
    # boundary; the other five targets are expected to compile.
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
      # Its own cache directory: two build graphs must not share one manifest.
      # The consumer is a second build root, so it takes its own directory
      # under the same cache root this shell exports, which is the separation
      # the CI job already makes by running from `consumer/` with
      # `--cache-dir` (`.github/workflows/verify.yml:255`).
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

    # Cache defaults, and only defaults: a value the caller exported always
    # wins and is never overwritten or unset here. These three names in this
    # order are the ones `cacheDir` above applies at task time, so a task
    # reached through `devenv tasks run` - which does not run this hook - lands
    # on the directory a shell would have chosen. Only the two directories
    # chosen here are created, so nothing is written into the checkout.
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
