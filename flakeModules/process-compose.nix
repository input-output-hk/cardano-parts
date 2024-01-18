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
        inherit
          (localFlake.packages.${system})
          run-process-compose-dbsync-mainnet
          run-process-compose-dbsync-preprod
          run-process-compose-dbsync-preview
          run-process-compose-dbsync-private
          run-process-compose-dbsync-sanchonet
          run-process-compose-dbsync-shelley-qa
          run-process-compose-node-stack
          ;
      };
    });
  };
}
