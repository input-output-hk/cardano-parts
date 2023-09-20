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
  }: let
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

    # Byron era secrets path definitions
    signingKey = "${groupOutPath}/secrets/groups/${groupName}/deploy/${name}-byron-delegate.key";
    delegationCertificate = "${groupOutPath}/secrets/groups/${groupName}/deploy/${name}-byron-delegation-cert.json";
    byronKeysExist = builtins.pathExists signingKey && builtins.pathExists delegationCertificate;

    # Shelly+ era secrets path definitions
    vrfKey = "${groupOutPath}/secrets/groups/${groupName}/deploy/${name}-vrf.skey";
    kesKey = "${groupOutPath}/secrets/groups/${groupName}/deploy/${name}-kes.skey";
    coldVerification = "${groupOutPath}/secrets/groups/${groupName}/deploy/${name}-cold.vkey";
    operationalCertificate = "${groupOutPath}/secrets/groups/${groupName}/deploy/${name}.opcert";
    bulkCredentials = "${groupOutPath}/secrets/groups/${groupName}/deploy/${name}-bulk.creds";

    trimStorePrefix = path: last (builtins.split "/nix/store/[^/]+/" path);
    verboseTrace = key: builtins.traceVerbose ("${name}: using " + (trimStorePrefix key));

    mkSopsSecret = secretName: key: {
      ${secretName} = verboseTrace key {
        inherit owner group;
        sopsFile = key;
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
        publicProducers = mkForce [];
        usePeersFromLedgerAfterSlot = -1;
      };

    sops.secrets = keysCfg.${Protocol};
    users.users.cardano-node.extraGroups = ["keys"];

    environment.shellAliases = {
      show-kes-period-info = ''
        cardano-cli \
          query kes-period-info \
          --op-cert-file /run/secrets/cardano-node-operational-cert
      '';

      show-leadership-schedule = ''
        cardano-cli \
          query leadership-schedule \
          --genesis ${ShelleyGenesisFile} \
          --cold-verification-key-file /run/secrets/cardano-node-cold-verification \
          --vrf-signing-key-file /run/secrets/cardano-node-vrf-signing \
          --current
      '';
    };
  };
}
