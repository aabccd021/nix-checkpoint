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
      overlay = (final: prev: import ./default.nix { pkgs = final; aicommit = aicommit; });

      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [ overlay ];
      };

      scripts = {
        default = pkgs.nix-checkpoint;
        nix-checkpoint = pkgs.nix-checkpoint;
        formatting = treefmtEval.config.build.check self;
        snapshot-test = pkgs.runCommandNoCCLocal "snapshot-test" { } ''
          mkdir -p "$out/snapshot/nested"
          echo "hello" > "$out/snapshot/nested/file.txt"
        '';
        fix = pkgs.writeShellScript "fix" ''
          echo "running fix"
          sleep 1
          echo "done fix"
        '';

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

      packages = scripts // devShells // {
        formatting = treefmtEval.config.build.check self;
        formatter = formatter;
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
