# nixosModule: role-block-producer
#
# TODO: Move this to a docs generator
#
# Attributes available on nixos module import:
#
# Tips:
#
{
  flake.nixosModules.role-block-producer = {
    config,
    name,
    lib,
    ...
  }:
    with builtins; let
      inherit (lib) last mkForce optionalAttrs;
      inherit (groupCfg) groupName groupFlake;
      inherit (groupCfg.meta) environmentName;
      inherit (perNodeCfg.lib) cardanoLib;
      inherit (cardanoLib.environments.${environmentName}.nodeConfig) Protocol ShelleyGenesisFile;

      groupCfg = config.cardano-parts.cluster.group;
      perNodeCfg = config.cardano-parts.perNode;
      groupOutPath = groupFlake.self.outPath;
      owner = "cardano-node";
      group = "cardano-node";
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

      trimStorePrefix = path: last (split "/nix/store/[^/]+/" path);
      verboseTrace = key: traceVerbose ("${name}: using " + (trimStorePrefix key));

      mkSopsSecret = secretName: key: {
        ${secretName} = verboseTrace (pathPrefix + key) {
          inherit owner group;
          sopsFile = pathPrefix + key;
        };
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
          (mkSopsSecret "cardano-node-signing" signingKey)
          // (mkSopsSecret "cardano-node-delegation-cert" delegationCertificate);

        TPraos =
          if perNodeCfg.roles.isCardanoDensePool
          then
            (mkSopsSecret "cardano-node-bulk-credentials" bulkCredentials)
            // (mkSopsSecret "cardano-node-cold-verification" coldVerification)
          else
            (mkSopsSecret "cardano-node-vrf-signing" vrfKey)
            // (mkSopsSecret "cardano-node-kes-signing" kesKey)
            // (mkSopsSecret "cardano-node-cold-verification" coldVerification)
            // (mkSopsSecret "cardano-node-operational-cert" operationalCertificate);

        Cardano = TPraos // optionalAttrs byronKeysExist RealPBFT;
      };
    in {
      systemd.services.cardano-node = {
        after = ["sops-secrets.service"];
        wants = ["sops-secrets.service"];
      };

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
            --stake-pool-id "$(show-pool-id)"
        '';
      };
    };
}
