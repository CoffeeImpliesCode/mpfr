# SPDX-License-Identifier: LGPL-3.0-or-later
#
# One source-only derivation. `flake.nix` and `devenv.nix` both call it, so the
# two entry points cannot describe different packages.
#
# The build graph owns C flags, source lists, header configuration and every
# installed artifact, header, licence file and `.pc`. Nothing here restates them.
# GMP comes from the in-tree `vendor/gmp` snapshot; there is no `../` import, no
# fetched source and no build-time download.

{ lib, stdenv, zig, linkage ? "static", optimize ? "ReleaseSafe" }:

stdenv.mkDerivation {
  pname = "mpfr-zig";
  version = "4.2.2";

  src = lib.cleanSourceWith {
    src = ./.;
    # Lock files are the workspace integration owner's, they are inputs to the
    # flake frontend rather than to this derivation, and nothing in
    # `installPhase` reads one. Keeping them out means a re-lock does not
    # invalidate an unchanged library build.
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

  # `installPhase` below is the only real phase. `dontInstall` stays unset:
  # setting it would disable that phase rather than run it.
  dontConfigure = true;
  dontBuild = true;
  dontCheck = true;
  dontUseZigCheck = true;
  dontAddPrefix = true;
  dontSetZigDefaultFlags = true;

  # Both caches live under the build's TMPDIR, outside the unpacked source, so
  # the sandbox never reaches $HOME and the local cache stays clean.
  installPhase = ''
    runHook preInstall

    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"

    zig build install \
      --prefix "$out" \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Doptimize=${optimize} \
      -Dcpu=baseline \
      -Dlinkage=${linkage}

    runHook postInstall
  '';

  meta = {
    description = "GNU MPFR 4.2.2, built from source as a Zig package, with its vendored GMP provider";
    homepage = "https://www.mpfr.org/";
    longDescription = ''
      The complete libmpfr compiled from this repository by Zig 0.16.0, with the
      typed Zig facade, the translated public C API, pkg-config metadata and the
      vendored GMP snapshot the library links. `linkage` selects a static archive
      or a shared library; both variants install the matching libgmp beside it,
      so the dynamic output is closed only together with its shared dependency.
    '';

    # The installed output is LGPL-3.0-or-later: libmpfr under MPFR's terms, and
    # the vendored GMP under the LGPLv3 side of GMP's dual offer, which is the
    # side this fork builds. The source tree is mixed; `NOTICE.md` is the
    # inventory and `FORK-LICENSE.md` covers this fork's own files.
    license = lib.licenses.lgpl3Plus;
    licenseFile = "share/licenses/mpfr/COPYING.LESSER";
    licenseNote = ''
      The installed output is LGPL-3.0-or-later. The source tree is not a single
      licence: upstream also ships GPL-3-or-later tooling, GPL-2-or-later test
      data and an FDL-1.3-or-later manual, none of which is installed. The
      vendored GMP keeps GMP's own dual LGPL-3.0-or-later OR GPL-2.0-or-later
      offer and its four COPYING files, installed under share/licenses/gmp.
    '';
  };

  passthru = {
    inherit linkage;
    gmpSource = "vendor/gmp";
    gmpVersion = "6.3.0";
  };
}
