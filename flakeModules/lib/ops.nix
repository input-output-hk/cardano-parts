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
}
