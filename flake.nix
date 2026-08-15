{
  description = "Small helpers for building a flake `packages` output straight out of a directory of Nixpkgs overlays.";

  inputs.nixpkgs-lib.url = "github:nix-community/nixpkgs.lib";

  outputs =
    { self, nixpkgs-lib }:
    {
      lib = {
        # Reads a directory of overlay files (final: prev: {...}) into a
        # list, one entry per *.nix file, in the order builtins.readDir
        # returns them.
        #
        # Overlay files may call builtins.getFlake to reference their own
        # flake's own inputs -- every file gets it shadowed to just
        # return `inherit inputs;` (via scopedImport) rather than the
        # real, impure builtin, so a flake using this stays evaluable
        # without --impure even though one of its own overlay files
        # reaches back into its inputs. Pass the same `inputs` your
        # flake's own `outputs` function receives.
        readOverlayDir =
          { dir, inputs }:
          let
            importFromFlakeInputs =
              path:
              scopedImport {
                builtins = builtins // {
                  getFlake = _flakeRef: { inherit inputs; };
                };
              } path;
          in
          nixpkgs-lib.lib.pipe dir [
            builtins.readDir
            (nixpkgs-lib.lib.filterAttrs (name: type: type == "regular" && nixpkgs-lib.lib.hasSuffix ".nix" name))
            builtins.attrNames
            (map (name: importFromFlakeInputs (dir + "/${name}")))
          ];

        # Turns a list of overlays into an attrset of packages: every
        # top-level attribute any of the overlays add or override,
        # provided it's an actual derivation once the overlays are
        # applied (so e.g. a `foo = super.foo.override {...};` override
        # of an existing nixpkgs package shows up too, not just wholly
        # new packages). Suitable directly as (part of) a flake's
        # `packages.<system>` output.
        getOverlayedPackages =
          {
            nixpkgs,
            system,
            overlays,
            config ? { },
          }:
          let
            pkgs = import nixpkgs { inherit system overlays config; };
          in
          nixpkgs-lib.lib.pipe overlays [
            # Extract attribute names from each overlay. Calling each
            # overlay with two empty attrsets as final/prev works because
            # the *names* of the attributes an overlay defines don't
            # depend on evaluating final/prev -- only the *values* do,
            # and Nix's laziness means those are never forced here.
            (map (overlay: builtins.attrNames (overlay { } { })))
            # Flatten all attribute names into a single list
            builtins.concatLists
            # Remove duplicates
            nixpkgs-lib.lib.unique
            # Filter to only include actual derivations that exist in pkgs
            (builtins.filter (name: pkgs ? ${name} && nixpkgs-lib.lib.isDerivation pkgs.${name}))
            # Convert to attribute set of packages
            (map (name: {
              inherit name;
              value = pkgs.${name};
            }))
            builtins.listToAttrs
          ];
      };
    };
}
