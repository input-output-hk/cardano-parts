{localFlake}: {flake-parts-lib, ...}: let
  inherit (flake-parts-lib) mkPerSystemOption;
in {
  options = {
    perSystem = mkPerSystemOption ({
      config,
      system,
      ...
    }: {
      config.packages = {
        inherit (localFlake.packages.${system}) demo;
      };
    });
  };
}
