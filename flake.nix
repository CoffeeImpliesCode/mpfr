# SPDX-License-Identifier: LGPL-3.0-or-later
#
# Flake entry point. It owns no build logic: both variants and the devenv
# outputs call `package.nix`.
#
# The nixpkgs input is a fixed revision. `flake.lock` is written by whoever owns
# locks in this workspace; no hash appears here because none has been observed.
#
# Canonical development is `devenv`, not this flake.

{
  description = "GNU MPFR 4.2.2 as a standalone Zig SDK";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f";

  outputs =
    { nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;

      # Systems whose package outputs this flake exposes. MPFR builds for more;
      # this is not a support claim.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
        "x86_64-windows"
      ];

      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # `zig = pkgs.zig_0_16` is named at both call sites on purpose:
      # callPackage fills an omitted argument from the package set, and
      # `pkgs.zig` is a moving alias, not the pinned compiler.
      packages = forAllSystems (pkgs: rec {
        static = pkgs.callPackage ./package.nix { zig = pkgs.zig_0_16; };
        shared = pkgs.callPackage ./package.nix {
          zig = pkgs.zig_0_16;
          linkage = "dynamic";
        };

        # The package's existing linkage policy is a static library.
        default = static;
      });

      # Tools only. Opening a development environment must not build the SDK.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.zig_0_16
            pkgs.pkg-config
            pkgs.gnumake
            pkgs.nix
          ];
        };
      });
    };
}
