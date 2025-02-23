{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    aicommit = {
      url = "github:nguyenvanduocit/ai-commit";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, aicommit, treefmt-nix }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      aicommitPkgs = pkgs.buildGoModule {
        name = "ai-commit";
        src = aicommit;
        vendorHash = "sha256-BPxPonschTe8sWc5pATAJuxpn7dgRBeVZQMHUJKpmTk=";
      };

      nix-checkpoint = pkgs.writeShellApplication {
        name = "nix-checkpoint";
        runtimeInputs = [
          aicommitPkgs
          pkgs.findutils
          pkgs.jq
          pkgs.nix-fast-build
        ];
        text = builtins.readFile ./nix-checkpoint.sh;
      };


      packages = {
        default = nix-checkpoint;
        nix-checkpoint = nix-checkpoint;
        formatting = treefmtEval.config.build.check self;
        snapshot-test = pkgs.runCommandNoCCLocal "snapshot-test" { } ''
          mkdir -p "$out/snapshot/nested"
          echo "bar" > "$out/snapshot/nested/file.txt"
        '';
      };

      gcroot = packages // {
        gcroot-all = pkgs.linkFarm "gcroot-all" packages;
      };

      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixpkgs-fmt.enable = true;
        programs.prettier.enable = true;
        programs.shfmt.enable = true;
        programs.shellcheck.enable = true;
        settings.formatter.shellcheck.options = [ "-s" "sh" ];
        settings.global.excludes = [ "LICENSE" ];
      };

    in

    {

      devShells.x86_64-linux.default = pkgs.mkShellNoCC {
        buildInputs = [
          nix-checkpoint
        ];
      };

      packages.x86_64-linux = gcroot;

      checks.x86_64-linux = gcroot;

      formatter.x86_64-linux = treefmtEval.config.build.wrapper;

      apps.x86_64-linux = {
        fix = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "fix" ''
              echo "running fix"
              sleep 1
              echo "done fix"
            ''
          );
        };
      };

    };
}
