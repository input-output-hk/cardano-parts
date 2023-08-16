flake: {
  perSystem = {
    inputs',
    pkgs,
    system,
    lib,
    ...
  }: {
    packages = {
      inherit
        (inputs'.cardano-db-sync.packages)
        cardano-db-sync
        cardano-db-tool
        ;

      # TODO:
      # inherit
      #   (inputs'.cardano-faucet.packages)
      #   cardano-faucet;

      inherit
        (inputs'.cardano-node-ng.packages)
        db-truncater
        ;

      inherit
        (inputs'.cardano-node.packages)
        bech32
        cardano-cli
        cardano-node
        cardano-submit-api
        cardano-tracer
        db-analyser
        db-synthesizer
        ;

      inherit
        (inputs'.cardano-wallet.packages)
        cardano-address
        cardano-wallet
        ;

      inherit
        (flake.inputs.offchain-metadata-tools.${system}.app.packages)
        metadata-server
        metadata-sync
        metadata-validator-github
        metadata-webhook
        token-metadata-creator
        ;

      # Cardano-cli to be split out from node starting in >= 8.2.x release
      cardano-cli-ng = pkgs.writeShellScriptBin "cardano-cli-ng" ''
        exec ${lib.getExe inputs'.cardano-cli-ng.packages."cardano-cli:exe:cardano-cli"} "$@"
      '';

      cardano-node-ng = pkgs.writeShellScriptBin "cardano-node-ng" ''
        exec ${lib.getExe inputs'.cardano-node-ng.packages.cardano-node} "$@"
      '';
    };
  };
}
