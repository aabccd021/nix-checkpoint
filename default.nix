{ pkgs }:

{

  nix-checkpoint = pkgs.writeShellApplication {
    name = "nix-checkpoint";
    runtimeInputs = [
      pkgs.opencommit
      pkgs.findutils
      pkgs.jq
      pkgs.all-follow
    ];
    text = builtins.readFile ./nix-checkpoint.sh;
  };
}
