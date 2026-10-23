# SPDX-License-Identifier: LGPL-3.0-or-later
#
# Package outputs use `package.nix`; devenv is the canonical development environment.

{
  description = "GNU MPFR 4.2.2 as a standalone Zig SDK";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/02c087f3fe673c9e317f206a627cb6b910336dbe";

  outputs =
    { nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;

      # Nix output platforms, not the full target support set.
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
      packages = forAllSystems (pkgs: rec {
        static = pkgs.callPackage ./package.nix { zig = pkgs.zig_0_17; };
        shared = pkgs.callPackage ./package.nix {
          zig = pkgs.zig_0_17;
          linkage = "dynamic";
        };

        default = static;
      });

      # Development tools only; opening the shell does not build the SDK.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.zig_0_17
            pkgs.pkg-config
            pkgs.gnumake
            pkgs.nix
          ];
        };
      });
    };
}
