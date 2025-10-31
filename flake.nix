{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
  inputs.aicommit.url = "github:nguyenvanduocit/ai-commit";
  inputs.aicommit.flake = false;

  outputs =
    { self, ... }@inputs:
    let
      lib = inputs.nixpkgs.lib;

      collectInputs =
        is:
        pkgs.linkFarm "inputs" (
          builtins.mapAttrs (
            name: i:
            pkgs.linkFarm name {
              self = i.outPath;
              deps = collectInputs (lib.attrByPath [ "inputs" ] { } i);
            }
          ) is
        );

      overlays.default = (
        final: prev:
        import ./default.nix {
          pkgs = final;
          aicommit = inputs.aicommit;
        }
      );

      pkgs = import inputs.nixpkgs {
        system = "x86_64-linux";
        overlays = [ overlays.default ];
      };

      treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
        programs.prettier.enable = true;
        programs.shfmt.enable = true;
        programs.shellcheck.enable = true;
        settings.formatter.shellcheck.options = [
          "-s"
          "sh"
        ];
        settings.global.excludes = [ "LICENSE" ];
      };

      formatter = treefmtEval.config.build.wrapper;

      devShells.default = pkgs.mkShellNoCC {
        buildInputs = [ pkgs.nixd ];
      };

      packages = devShells // {
        formatting = treefmtEval.config.build.check self;
        formatter = formatter;
        allInputs = collectInputs inputs;
        default = pkgs.nix-checkpoint;
        nix-checkpoint = pkgs.nix-checkpoint;
        snapshot-test = pkgs.runCommand "snapshot-test" { } ''
          mkdir -p "$out/snapshot/nested"
          echo "hello" > "$out/snapshot/nested/file.txt"
        '';
        prefmt = pkgs.writeShellScriptBin "prefmt" ''
          echo "running prefmt"
          sleep 1
          echo "done prefmt"
        '';
      };

    in

    {

      packages.x86_64-linux = packages // {
        gcroot = pkgs.linkFarm "gcroot" packages;
      };

      checks.x86_64-linux = packages;
      formatter.x86_64-linux = formatter;
      overlays = overlays;
      devShells.x86_64-linux = devShells;

    };
}
