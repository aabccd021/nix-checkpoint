{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    nix-auto-follow.url = "github:fzakaria/nix-auto-follow";
  };

  outputs = { self, nixpkgs, treefmt-nix, nix-auto-follow }:
    let
      overlay = (final: prev:
        (nix-auto-follow.overlays.default final prev)
        // (import ./default.nix { pkgs = final; })
      );

      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [ overlay ];
      };

      packages = {
        default = pkgs.nix-checkpoint;
        nix-checkpoint = pkgs.nix-checkpoint;
        formatting = treefmtEval.config.build.check self;
        snapshot-test = pkgs.runCommandNoCCLocal "snapshot-test" { } ''
          mkdir -p "$out/snapshot/nested"
          echo "hello" > "$out/snapshot/nested/file.txt"
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
        buildInputs = [ pkgs.nix-checkpoint ];
      };

      overlays.default = overlay;

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
