{
  description = "Ryoku Debian — standalone Home Manager + Niri (no NixOS/osConfig)";

  # Pins are commit SHAs so guests can `nix flake lock` reproducibly even when
  # flake.lock is regenerated. Prefer regenerating lock on the Debian guest.
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

      mkHome =
        { username, homeDirectory }:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = {
            inherit nixGL;
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
      # Default attribute used by bootstrap: .#ryoku
      homeConfigurations.ryoku = mkHome {
        username = "ryoku";
        homeDirectory = "/home/ryoku";
      };

      # Generic helper: bootstrap rewrites a thin host overlay when --user differs.
      homeConfigurations.default = self.homeConfigurations.ryoku;

      packages.${system} = {
        # Expose niri for smoke checks: nix build .#niri
        niri = pkgs.niri;
        nixGLIntel = nixGL.packages.${system}.nixGLIntel;
        nixGLDefault = nixGL.packages.${system}.nixGLDefault;
      };

      # Documentation / tooling markers for CI path checks.
      checks.${system}.paths = pkgs.runCommand "ryoku-debian-flake-paths" { } ''
        test -f ${./home/home.nix}
        test -f ${./home/niri.nix}
        mkdir -p $out
        echo ok > $out/result
      '';

      formatter.${system} = pkgs.nixfmt-rfc-style;
    };
}
