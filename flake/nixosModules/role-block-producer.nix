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
    inherit (groupCfg) groupName groupOutPath;
    inherit (groupCfg.meta) environmentName;
    inherit (perNodeCfg.lib) cardanoLib;

    groupCfg = config.cardano-parts.cluster.group;
    perNodeCfg = config.cardano-parts.perNode;
    protocol = cardanoLib.environments.${environmentName}.nodeConfig.Protocol;
    owner = "cardano-node";
    group = "cardano-node";

    # Byron era secrets path definitions
    signingKey = "${groupOutPath}/secrets/${groupName}/${name}-byron-delegate.key";
    delegationCertificate = "${groupOutPath}/secrets/${groupName}/${name}-byron-delegation-cert.json";
    byronKeysExist = builtins.pathExists signingKey && builtins.pathExists delegationCertificate;

    # Shelly+ era secrets path definitions
    vrfKey = "${groupOutPath}/secrets/${groupName}/${name}-node-vrf.skey";
    kesKey = "${groupOutPath}/secrets/${groupName}/${name}-node-kes.skey";
    operationalCertificate = "${groupOutPath}/secrets/${groupName}/${name}-node.opcert";
    bulkCredentials = "${groupOutPath}/secrets/${groupName}/${name}-bulk.creds";

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
        then (mkSopsSecret "cardano-node-bulk-credentials" bulkCredentials)
        else
          (mkSopsSecret "cardano-node-vrf-signing" vrfKey)
          // (mkSopsSecret "cardano-node-kes-signing" kesKey)
          // (mkSopsSecret "cardano-node-operational-cert" operationalCertificate);

      Cardano = TPraos // optionalAttrs byronKeysExist RealPBFT;
    };
  in {
    systemd.services.cardano-node = {
      after = ["sops-secrets.service"];
      wants = ["sops-secrets.service"];
    };

    services.cardano-node =
      serviceCfg.${protocol}
      // {
        publicProducers = mkForce [];
        usePeersFromLedgerAfterSlot = -1;
      };

    sops.secrets = keysCfg.${protocol};
    users.users.cardano-node.extraGroups = ["keys"];
  };
}
