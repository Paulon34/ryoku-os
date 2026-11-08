{
  description = "Ryoku Debian — standalone Home Manager + Niri (no NixOS/osConfig)";

  # Pins are commit SHAs so guests can `nix flake lock` reproducibly.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/f9a75f41be3a74eab55d3a7679d34ad6cc0da977";

    home-manager = {
      url = "github:nix-community/home-manager/2c0c1f01521469cf0271180c453c79782d53c2f6";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixGL = {
      url = "github:nix-community/nixGL/4306ae1d15adf3d386f1462b330d4f2648404711";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, home-manager, nixGL, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;

      # Host files under ./hosts/<name>/default.nix (plain attrsets, not gitignored).
      hostNames = lib.optionals (builtins.pathExists ./hosts) (
        lib.attrNames (
          lib.filterAttrs (
            name: type:
            type == "directory" && builtins.pathExists (./hosts + "/${name}/default.nix")
          ) (builtins.readDir ./hosts)
        )
      );

      mkHome =
        {
          username,
          homeDirectory,
          profile ? { },
        }:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = {
            inherit nixGL;
            ryokuUser = {
              inherit username homeDirectory;
            };
          };
          modules = [
            ./modules
            ./home/home.nix
            {
              home.username = username;
              home.homeDirectory = homeDirectory;
              ryoku.profile = {
                edition = profile.edition or "minimal";
                visual = profile.visual or "balanced";
                shellStyle = profile.shellStyle or "quattro";
                jarvis = profile.jarvis or false;
              };
            }
          ];
        };

      homeFromHost =
        name:
        let
          host = import (./hosts + "/${name}");
          username = host.username or name;
          homeDirectory = host.homeDirectory or "/home/${name}";
          profile = host.profile or { };
        in
        mkHome {
          inherit username homeDirectory profile;
        };
    in
    {
      # One attr per hosts/<name> — bootstrap targets .#<user>, never a fixed wrong HOME.
      homeConfigurations = lib.genAttrs hostNames homeFromHost;

      packages.${system} = {
        niri = pkgs.niri;
        nixGLIntel = nixGL.packages.${system}.nixGLIntel;
        # Deterministic default for pure flakes; NVIDIA auto-detection is impure.
        nixGLDefault = nixGL.packages.${system}.nixGLIntel;
      };

      checks.${system}.paths = pkgs.runCommand "ryoku-debian-flake-paths" { } ''
        test -f ${./home/home.nix}
        test -f ${./home/niri.nix}
        test -f ${./hosts/ryoku/default.nix}
        test -f ${./modules/profiles.nix}
        mkdir -p $out
        echo ok > $out/result
      '';

      # Expose builder for docs/tests (not a homeConfiguration by itself).
      lib.mkRyokuHome = mkHome;

      formatter.${system} = pkgs.nixfmt-rfc-style;
    };
}
