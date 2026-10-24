# SPDX-License-Identifier: LGPL-3.0-or-later
#
# Both the flake and devenv use this source derivation.

{ lib
, stdenv
, zig
, fetchFromGitHub
, gmpSrc ? fetchFromGitHub {
    owner = "CoffeeImpliesCode";
    repo = "gmp";
    rev = "c124ccbaf2072c438a7e8def5addc628c65ab74e";
    hash = "sha256-XLUE9x9L3vT9ERvevND54ChAzuK7Ih0YrBN1sE5VZYw=";
  }
, linkage ? "static"
, optimize ? "ReleaseSafe"
}:

stdenv.mkDerivation {
  pname = "mpfr-zig";
  version = "4.2.2";

  src = lib.cleanSourceWith {
    src = ./.;
    # Exclude workspace locks and build outputs from derivation inputs.
    filter = path: _type:
      let base = baseNameOf (toString path); in
      !(lib.elem base [
        ".git"
        ".zig-cache"
        "zig-cache"
        "zig-out"
        "zig-pkg"
        ".devenv"
        ".devenv.flake.nix"
        ".direnv"
        "flake.lock"
        "devenv.lock"
        "result"
      ]) && !(lib.hasPrefix "result-" base);
  };

  strictDeps = true;
  nativeBuildInputs = [ zig ];

  # Do not set `dontInstall`; `installPhase` implements installation.
  dontConfigure = true;
  dontBuild = true;
  dontCheck = true;
  dontUseZigCheck = true;
  dontAddPrefix = true;
  dontSetZigDefaultFlags = true;

  # Keep Zig caches in `TMPDIR`, outside the unpacked source.
  installPhase = ''
    runHook preInstall

    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    mkdir -p "$ZIG_GLOBAL_CACHE_DIR/p"
    cp -r --no-preserve=mode ${gmpSrc} "$ZIG_GLOBAL_CACHE_DIR/p/gmp-6.3.0-FVVS2nj8CwF5oxyvYkR6LzJuPs5MgvaDC7zf-xWIJX--"

    zig build install \
      --prefix "$out" \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Doptimize=${optimize} \
      -Dcpu=baseline \
      -Dlinkage=${linkage}

    runHook postInstall
  '';

  meta = {
    description = "GNU MPFR 4.2.2, built from source as a Zig package, with the GMP package dependency";
    homepage = "https://www.mpfr.org/";
    longDescription = ''
      The complete libmpfr compiled from this repository by Zig 0.17.0, with the
      typed Zig facade, the translated public C API, pkg-config metadata and the
      GMP package dependency the library links. `linkage` selects a static archive
      or a shared library; both variants install the matching libgmp beside it,
      so the dynamic output is closed only together with its shared dependency.
    '';

    # Installed output is LGPL-3.0-or-later; see `NOTICE.md` for licence groups.
    license = lib.licenses.lgpl3Plus;
    licenseFile = "share/licenses/mpfr/COPYING.LESSER";
    licenseNote = ''
      The installed output is LGPL-3.0-or-later. The source tree is not a single
      licence: upstream also ships GPL-3-or-later tooling, GPL-2-or-later test
      data and an FDL-1.3-or-later manual, none of which is installed. The
      GMP dependency keeps GMP's own dual LGPL-3.0-or-later OR GPL-2.0-or-later
      offer and its four COPYING files, installed under share/licenses/gmp.
    '';
  };

  passthru = {
    inherit linkage;
    gmpSource = gmpSrc;
    gmpVersion = "6.3.0";
  };
}
