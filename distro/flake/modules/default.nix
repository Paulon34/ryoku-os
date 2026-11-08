{ ... }:

{
  imports = [
    ./profiles.nix
    ./features/minimal.nix
    ./features/full.nix
    ./features/visual.nix
  ];
}
