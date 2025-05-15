{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
  inputs.aicommit.url = "github:nguyenvanduocit/ai-commit";
  inputs.aicommit.flake = false;

  outputs = { self, nixpkgs, aicommit, treefmt-nix }:
    let
      overlay = (final: prev: import ./default.nix { pkgs = final; aicommit = aicommit; });

      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [ overlay ];
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

      formatter = treefmtEval.config.build.wrapper;

      devShells.default = pkgs.mkShellNoCC {
        buildInputs = [ pkgs.nixd ];
      };

      packages = devShells // {
        formatting = treefmtEval.config.build.check self;
        formatter = formatter;
        default = pkgs.nix-checkpoint;
        nix-checkpoint = pkgs.nix-checkpoint;
        snapshot-test = pkgs.runCommandNoCCLocal "snapshot-test" { } ''
          mkdir -p "$out/snapshot/nested"
          echo "hello" > "$out/snapshot/nested/file.txt"
        '';
        fix = pkgs.writeShellScriptBin "fix" ''
          set -x
          echo "running fix"
          sleep 1
          echo "done fix"
        '';
      };

    in

    {

      packages.x86_64-linux = packages // {
        gcroot = pkgs.linkFarm "gcroot" packages;
      };

      checks.x86_64-linux = packages;
      formatter.x86_64-linux = formatter;
      overlays.default = overlay;
      devShells.x86_64-linux = devShells;

    };
}
