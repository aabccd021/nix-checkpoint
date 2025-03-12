{ pkgs, aicommit }:

let
  aicommitPkgs = pkgs.buildGoModule {
    name = "ai-commit";
    src = aicommit;
    vendorHash = "sha256-BPxPonschTe8sWc5pATAJuxpn7dgRBeVZQMHUJKpmTk=";
  };
in

{

  nix-checkpoint = pkgs.writeShellApplication {
    name = "nix-checkpoint";
    runtimeInputs = [
      aicommitPkgs
      pkgs.findutils
      pkgs.jq
      pkgs.all-follow
    ];
    text = builtins.readFile ./nix-checkpoint.sh;
  };
}
