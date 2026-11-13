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
      lib = nixpkgs.lib;
      # Read the GUI's live (Git-tracked) root settings.json. The distro/ryoku
      # copy is only a bootstrap seed; it must not mask saved shell style.
      ryokuLib = import ../ryoku/lib.nix { inherit lib; };

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
          settingsApply ? { },
        }:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = {
            inherit nixGL dankMaterialShell home-manager;
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
                # Appearance -> Quattro/Islands in Ryoku Settings takes
                # precedence when explicitly saved. Null keeps bootstrap's
                # host profile (Minimal defaults to Islands).
                shellStyle =
                  let saved = ryokuLib.appearance.shellStyle or null;
                  in if saved == null then (profile.shellStyle or "islands") else saved;
                jarvis = profile.jarvis or false;
                compositor = profile.compositor or "hyprland";
              };
              # Absolute checkout path only — never invent ~/ryoku-os.
              ryoku.settingsApply.repoPath = settingsApply.repoPath or "";
              ryoku.settingsApply.flakeHost = settingsApply.flakeHost or username;
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
          settingsApply = host.settingsApply or { };
        in
        mkHome {
          inherit username homeDirectory profile settingsApply;
        };
    in
    {
      # One attr per hosts/<name> — bootstrap targets .#<user>, never a fixed wrong HOME.
      homeConfigurations = lib.genAttrs hostNames homeFromHost;

      packages.${system} = {
        niri = pkgs.niri;
        nixGLIntel = nixGL.packages.${system}.nixGLIntel;
        # Pure Mesa default: automatic NVIDIA detection requires impure currentTime.
        nixGLDefault = nixGL.packages.${system}.nixGLIntel;
        dms-shell = dankMaterialShell.packages.${system}.dms-shell;
        quickshell = pkgs.quickshell; # Expose qs for CI and runtime diagnosis.
        # Buildable reference variant to verify all Ryoku 1.5.3 patches in CI.
        dms-shell-ryoku = pkgs.callPackage ./pkgs/dms-shell-ryoku.nix {
          dms-shell = dankMaterialShell.packages.${system}.dms-shell;
          ryokuSettingsJson = "/home/ryoku/.config/ryoku/settings.json";
          ryokuShellStyle = "quattro";
        };
        ryoku-settings = pkgs.callPackage ./pkgs/ryoku-settings.nix {
          ryokuRepoPathDefault = "/home/ryoku/ryoku-os";
          ryokuFlakeHostDefault = "ryoku";
        };
        ryoku-settings-apply = pkgs.callPackage ./pkgs/ryoku-settings-apply.nix {
          repoPath = "/home/ryoku/ryoku-os";
          flakeHost = "ryoku";
          flakeDir = "/home/ryoku/ryoku-os/distro/flake";
          home-manager = home-manager.packages.${system}.default;
        };
      };

      # SHA-256 of the declarative apply subset (ryoku/settings.json via lib.nix).
      ryokuSettingsHash = ryokuLib.settingsHash;

      checks.${system}.paths = pkgs.runCommand "ryoku-debian-flake-paths" { } ''
        test -f ${./home/home.nix}
        test -f ${./home/niri.nix}
        test -f ${./home/hyprland.nix}
        test -f ${./home/session-helpers.nix}
        test -f ${./home/dms.nix}
        test -f ${./home/settings.nix}
        test -f ${./home/build-info.nix}
        test -f ${./pkgs/ryoku-settings.nix}
        test -f ${./pkgs/ryoku-settings-apply.nix}
        test -f ${./patches/dms/1.5.3/ryoku-quattro-foundation.patch}
        test -f ${./hosts/ryoku/default.nix}
        test -f ${./modules/profiles.nix}
        test -f ${../apps/ryoku-settings/CMakeLists.txt}
        test -f ${../ryoku/settings.json}
        test -f ${../polkit/org.ryoku.settings.apply.policy}
        test -x ${../scripts/ryoku-doctor}
        mkdir -p $out
        echo ok > $out/result
      '';

      lib.mkRyokuHome = mkHome;

      formatter.${system} = pkgs.nixfmt-rfc-style;
    };
}
