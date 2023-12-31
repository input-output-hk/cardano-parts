# nixosModule: role-block-producer
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#
# Tips:
#
flake: {
  flake.nixosModules.role-block-producer = {
    config,
    lib,
    name,
    pkgs,
    ...
  }:
    with builtins; let
      inherit (lib) mkIf mkForce optionalAttrs;
      inherit (groupCfg) groupName groupFlake;
      inherit (groupCfg.meta) environmentName;
      inherit (perNodeCfg.lib) cardanoLib;
      inherit (cardanoLib.environments.${environmentName}.nodeConfig) Protocol ShelleyGenesisFile;
      inherit (opsLib) mkSopsSecret;

      groupCfg = config.cardano-parts.cluster.group;
      nodeCfg = config.services.cardano-node;
      perNodeCfg = config.cardano-parts.perNode;
      groupOutPath = groupFlake.self.outPath;
      opsLib = flake.config.flake.cardano-parts.lib.opsLib pkgs;

      pathPrefix = "${groupOutPath}/secrets/groups/${groupName}/deploy/";

      # Byron era secrets path definitions
      signingKey = "${name}-byron-delegate.key";
      delegationCertificate = "${name}-byron-delegation-cert.json";
      byronKeysExist = pathExists (pathPrefix + signingKey) && pathExists (pathPrefix + delegationCertificate);

      # Shelly+ era secrets path definitions
      vrfKey = "${name}-vrf.skey";
      kesKey = "${name}-kes.skey";
      coldVerification = "${name}-cold.vkey";
      operationalCertificate = "${name}.opcert";
      bulkCredentials = "${name}-bulk.creds";

      mkSopsSecretParams = secretName: keyName: {
        inherit groupOutPath groupName secretName keyName pathPrefix;
        fileOwner = "cardano-node";
        fileGroup = "cardano-node";
        reloadUnits = mkIf (nodeCfg.useSystemdReload && nodeCfg.useNewTopology) ["cardano-node.service"];
        restartUnits = mkIf (!nodeCfg.useSystemdReload || !nodeCfg.useNewTopology) ["cardano-node.service"];
      };

      serviceCfg = rec {
        RealPBFT = {
          signingKey = "/run/secrets/cardano-node-signing";
          delegationCertificate = "/run/secrets/cardano-node-delegation-cert";
        };

        TPraos =
          if perNodeCfg.roles.isCardanoDensePool
          then {
            extraArgs = ["--bulk-credentials-file" "/run/secrets/cardano-node-bulk-credentials"];
          }
          else {
            kesKey = "/run/secrets/cardano-node-kes-signing";
            vrfKey = "/run/secrets/cardano-node-vrf-signing";
            operationalCertificate = "/run/secrets/cardano-node-operational-cert";
          };

        Cardano = TPraos // optionalAttrs byronKeysExist RealPBFT;
      };

      keysCfg = rec {
        RealPBFT =
          (mkSopsSecret (mkSopsSecretParams "cardano-node-signing" signingKey))
          // (mkSopsSecret (mkSopsSecretParams "cardano-node-delegation-cert" delegationCertificate));

        TPraos =
          if perNodeCfg.roles.isCardanoDensePool
          then
            (mkSopsSecret (mkSopsSecretParams "cardano-node-bulk-credentials" bulkCredentials))
            // (mkSopsSecret (mkSopsSecretParams "cardano-node-cold-verification" coldVerification))
          else
            (mkSopsSecret (mkSopsSecretParams "cardano-node-vrf-signing" vrfKey))
            // (mkSopsSecret (mkSopsSecretParams "cardano-node-kes-signing" kesKey))
            // (mkSopsSecret (mkSopsSecretParams "cardano-node-cold-verification" coldVerification))
            // (mkSopsSecret (mkSopsSecretParams "cardano-node-operational-cert" operationalCertificate));

        Cardano = TPraos // optionalAttrs byronKeysExist RealPBFT;
      };
    in {
      services.cardano-node =
        serviceCfg.${Protocol}
        // {
          # These are also set from the profile-cardano-node-topology nixos module when role == "bp"
          publicProducers = mkForce [];
          usePeersFromLedgerAfterSlot = -1;
        };

      sops.secrets = keysCfg.${Protocol};
      users.users.cardano-node.extraGroups = ["keys"];

      environment.shellAliases = {
        cardano-show-kes-period-info = ''
          cardano-cli \
            query kes-period-info \
            --op-cert-file /run/secrets/cardano-node-operational-cert
        '';

        cardano-show-leadership-schedule = ''
          cardano-cli \
            query leadership-schedule \
            --genesis ${ShelleyGenesisFile} \
            --cold-verification-key-file /run/secrets/cardano-node-cold-verification \
            --vrf-signing-key-file /run/secrets/cardano-node-vrf-signing \
            --current
        '';

        cardano-show-pool-hash = ''
          cardano-cli \
            stake-pool id \
            --cold-verification-key-file /run/secrets/cardano-node-cold-verification \
            --output-format hex
        '';

        cardano-show-pool-id = ''
          cardano-cli \
            stake-pool id \
            --cold-verification-key-file /run/secrets/cardano-node-cold-verification \
            --output-format bech32
        '';

        cardano-show-pool-stake-snapshot = ''
          cardano-cli \
            query stake-snapshot \
            --stake-pool-id "$(cardano-show-pool-id)"
        '';
      };
    };
}
