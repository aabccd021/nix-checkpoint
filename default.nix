{ pkgs, aicommit }:

let
  aicommitPkgs = pkgs.buildGoModule {
    name = "ai-commit";
    src = aicommit;
    vendorHash = "sha256-BPxPonschTe8sWc5pATAJuxpn7dgRBeVZQMHUJKpmTk=";
  };
in

{

  aicommit = aicommitPkgs;

  nix-checkpoint = pkgs.writeShellApplication {
    name = "nix-checkpoint";
    runtimeInputs = [
      aicommitPkgs
      pkgs.findutils
      pkgs.jq
    ];
    text = builtins.readFile ./nix-checkpoint.sh;
  };
}
