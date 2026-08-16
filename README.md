# nix-get-overlayed-packages

A flake that helps compose packages entirely out of a directory of Nixpkgs overlays, instead of listing them one by one in `outputs`.

## Usage

A typical flake keeps its overlays as separate files under a directory (here, `./overlays`), reads them into a list once, and reuses that same list both for `nixosConfigurations` (via `nixpkgs.overlays`) and for the `packages` output.
This makes a package an overlay adds/overrides automatically buildable with `nix build .#that-package`, with nothing to keep in sync by hand.

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.nix-get-overlayed-packages.url = "github:doronbehar/nix-get-overlayed-packages";

  outputs = { self, nixpkgs, nix-get-overlayed-packages, ... }@inputs:
    let
      system = "x86_64-linux";
      overlays = nix-get-overlayed-packages.lib.readOverlayDir {
        dir = ./overlays;
        inherit inputs;
      };
      pkgs = import nixpkgs { inherit system overlays; };
    in
    {
      packages.${system} = nix-get-overlayed-packages.lib.getOverlayedPackages {
        inherit nixpkgs system overlays;
      };

      nixosConfigurations.myMachine = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          { nixpkgs.overlays = overlays; }
          ./configuration.nix
        ];
      };
    };
}
```

### `readOverlayDir`

Reads every `.nix` file directly under `dir` and imports it, returning a list of overlay (`final: prev: {...}`) functions in the order `builtins.readDir` lists them.

The `inputs` argument is your own flake's `inputs` attrset -- the one captured by `@inputs` in:

```nix
  outputs = {
    self,
    nixpkgs,
    ...
  }@inputs:
  {
    # ...
  }
```

This makes it possible to run e.g:

```
env NIX_PATH=nixpkgs-overlays=./overlays:nixpkgs=$HOME/repos/nixpkgs nix build --impure my-overlayed-dependent-package 
```

While `my-overlayed-dependent-package` is not available in the flake's `packages` output.

Usually you'd want to put this overlay in a dedicated overlay Nix file like `./overlays/from-flake-inputs.nix`:

```nix
final: prev:
let
  inputs = (builtins.getFlake (toString ../.)).inputs;
in
{
  my-tool = inputs.my-tool-flake.packages.x86_64-linux.default;
}
```

### `getOverlayedPackages`

Applies `overlays` on top of `nixpkgs`, then returns an attribute set of these packages.

`overlays` and `nixpkgs` are the only arguments this function looks at itself -- everything else (`system`, `config`, `crossSystem`, ...) is passed straight through to `import nixpkgs`, so it works unmodified for cross-compiled package sets too:

```nix
nix-get-overlayed-packages.lib.getOverlayedPackages {
  inherit nixpkgs overlays;
  system = "x86_64-linux";
  crossSystem = "armv7l-linux";
}
```

returns armv7l-linux derivations, buildable from an x86_64-linux machine, same as `import nixpkgs { system = "x86_64-linux"; crossSystem = "armv7l-linux"; overlays = [...]; }` would. 
