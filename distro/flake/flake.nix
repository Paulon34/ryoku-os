{
  description = "Ryoku Debian — standalone Home Manager + Niri + DMS (no NixOS/osConfig)";

  # Pins are commit SHAs / tags so guests can `nix flake lock` reproducibly.
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

    # DankMaterialShell 1.5.3 — matches Ryoku visual patch pin.
    dankMaterialShell = {
      url = "github:AvengeMedia/DankMaterialShell/v1.5.3";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, home-manager, nixGL, dankMaterialShell, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      mkHome =
        { username, homeDirectory }:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = {
            inherit nixGL dankMaterialShell;
            ryokuUser = {
              inherit username homeDirectory;
            };
          };
          modules = [
            ./home/home.nix
            {
              home.username = username;
              home.homeDirectory = homeDirectory;
            }
          ];
        };
    in
    {
      homeConfigurations.ryoku = mkHome {
        username = "ryoku";
        homeDirectory = "/home/ryoku";
      };

      homeConfigurations.default = self.homeConfigurations.ryoku;

      packages.${system} = {
        niri = pkgs.niri;
        nixGLIntel = nixGL.packages.${system}.nixGLIntel;
        nixGLDefault = nixGL.packages.${system}.nixGLDefault;
        dms-shell = dankMaterialShell.packages.${system}.dms-shell;
      };

      checks.${system}.paths = pkgs.runCommand "ryoku-debian-flake-paths" { } ''
        test -f ${./home/home.nix}
        test -f ${./home/niri.nix}
        test -f ${./home/dms.nix}
        test -f ${./patches/dms/1.5.3/ryoku-quattro-foundation.patch}
        mkdir -p $out
        echo ok > $out/result
      '';

      formatter.${system} = pkgs.nixfmt-rfc-style;
    };
}
