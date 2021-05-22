{
  description = "A matrix bot... or not?";

  outputs = { self, nixpkgs }:
  let
    systems = [ "x86_64-linux" "i686-linux" "x86_64-darwin" "aarch64-linux" ];

    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

    # Memoize nixpkgs for different platforms for efficiency.
    nixpkgsFor = forAllSystems (system:
    import nixpkgs {
      inherit system;
      overlays = [ self.overlay ];
    });

  in {
    overlay = final: prev: {
      not-bot = final.beamPackages.mixRelease {
        pname = "foo";
        version = "1.0.0";
        src = nixpkgs.lib.cleanSource ./.;
        mixNixDeps = final.callPackage ./deps.nix {};
        buildInputs = [];
      };
    };

    packages = forAllSystems (system: { inherit (nixpkgsFor.${system}) not-bot; });

    defaultPackage = forAllSystems (system: self.packages.${system}.not-bot);
  };
}
