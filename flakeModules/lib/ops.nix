pkgs:
# Argument `pkgs` is provided by the library consumer per the lib flakeModule ops option default:
#   flake.cardano-parts.lib.ops
with builtins;
with pkgs;
with lib; rec {
  # Use the iohk-nix mkConfigHtml attr and transform the output to what mdbook expects
  generateStaticHTMLConfigs = pkgs: cardanoLib: environments: let
    cardano-deployment = cardanoLib.mkConfigHtml environments;
  in
    pkgs.runCommand "cardano-html" {} ''
      mkdir "$out"
      cp "${cardano-deployment}/index.html" "$out/"
      cp "${cardano-deployment}/rest-config.json" "$out/"

      ENVS=(${escapeShellArgs (attrNames environments)})
      for ENV in "''${ENVS[@]}"; do
        # Migrate each env from a flat dir to an ENV subdir
        mkdir -p "$out/config/$ENV"
        for i in $(find ${cardano-deployment} -type f -name "$ENV-*" -printf "%f\n"); do
          cp -v "${cardano-deployment}/$i" "$out/config/$ENV/''${i#"$ENV-"}"
        done

        # Adjust genesis file and config refs
        sed -i "s|\"$ENV-|\"|g" "$out/config/$ENV/config.json"
        sed -i "s|\"$ENV-|\"|g" "$out/config/$ENV/db-sync-config.json"

        # Adjust index.html file refs
        sed -i "s|$ENV-|config/$ENV/|g" "$out/index.html"
      done
    '';

  mkCardanoLib = system: nixpkgs: flakeRef:
  # Remove the dead testnet environment until it is removed from iohk-nix
    removeByPath ["environments" "testnet"]
    (import nixpkgs {
      inherit system;
      overlays = map (
        overlay: flakeRef.overlays.${overlay}
      ) (builtins.attrNames flakeRef.overlays);
    })
    .cardanoLib;

  mkSopsSecret = {
    secretName,
    keyName,
    groupOutPath,
    groupName,
    fileOwner,
    fileGroup,
    pathPrefix ? "${groupOutPath}/secrets/groups/${groupName}/deploy/",
    restartUnits ? [],
    reloadUnits ? [],
    extraCfg ? {},
  }: let
    trimStorePrefix = path: last (split "/nix/store/[^/]+/" path);
    verboseTrace = keyName: traceVerbose ("${name}: using " + (trimStorePrefix keyName));
  in {
    ${secretName} = verboseTrace (pathPrefix + keyName) ({
        inherit restartUnits reloadUnits;
        owner = fileOwner;
        group = fileGroup;
        sopsFile = pathPrefix + keyName;
      }
      // extraCfg);
  };

  removeByPath = pathList:
    updateManyAttrsByPath [
      {
        path = init pathList;
        update = filterAttrs (n: _: n != (last pathList));
      }
    ];

  # A default list of IOG pools which will be used to verify IOG signature(s) on mithril snapshots
  # prior to mithril client use when config.mithril-client.verifySnapshotSignature is enabled.
  mithrilVerifyingPools = {
    mainnet = [
      "pool155efqn9xpcf73pphkk88cmlkdwx4ulkg606tne970qswczg3asc"
      "pool1gpzkwf3ntp7ky6yvyky8q6qu4dyup5y6v4pxzn56yut8sqp6k53"
      "pool1mxqjlrfskhd5kql9kak06fpdh8xjwc76gec76p3taqy2qmfzs5z"
      "pool1nee5kmpzv0qfz7lu258fe9ylgxh68lsqqdmjgw7jnheej3usn35"
    ];

    preprod = [
      "pool18svpptnxfctewpx7ntnmlazy4w9cr24f4rcq8smkvpggw600ql4"
      "pool1945cfqzmy2qe2z59mfdwm7jwqtucncfee5xkd8f4wu97zr8xuys"
      "pool1kxtrz8evgdrwwrdajhwweng6k8eysjvqgn59r8a5wkqw6rlnvv6"
    ];

    preview = [
      "pool12yrhvezsrqxlafahf02ka28a4a3qxgcgkylku4vqjg385jh60wa"
      "pool19ta77tu28f3y7m6yjgnqlcs98ak6a0vvtlcn7mc52azpwr4l2xt"
      "pool1u2pl6kx4yc77lnyapnveykkpnj07fmc7pd66fa40fvx3khw7cua"
    ];

    sanchonet = [
      "pool13lr6wv9m55el9ahscn8qmutc80gq9m5ajgawjstj3v5rqm7fpd9"
      "pool1h722gdd6kx782me0v9zresnds4ajugneq0vl9a0ju7mgvemezdf"
      "pool1m840r7thpj9mxhw33hud3g9jkvjvm00wkw89ul8t06nngjewl6m"
    ];
  };
}
