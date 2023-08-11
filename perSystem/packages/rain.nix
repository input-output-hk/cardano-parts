{
  perSystem = {inputs', ...}: {
    packages = {
      inherit (inputs'.nixpkgs-unstable.legacyPackages) rain;
    };
  };
}
