flake @ {lib, ...}: let
  # Search defns
  startPathStr = "inputs";
  recursePathStr = "inputs";

  # To scan though all discovered inputs and search for closureSize
  dumpAllPaths = true;

  # Blank if dumpAllPaths, otherwise, a regex match string
  matchExtRegex = "";

  # Depth limiter
  maxRecurseDepth = 6;

  # Redundant or infinite recursion exclusions here
  denyList = ["self"];

  # Optionally show all fullPaths as they are recursed
  pathTrace = false;

  optionalTrace = arg1: arg2:
    if pathTrace
    then builtins.trace arg1 arg2
    else arg2;

  filterAttrs = lib.filterAttrs (n: _: !(builtins.elem n denyList));
  filterList = builtins.filter (n: !(builtins.elem n denyList));

  found = pathAttr: [{FOUND = {inherit (pathAttr) attrPath out depth;};}];
  attrCheck = pathAttr: builtins.hasAttr recursePathStr pathAttr.attr && pathAttr.depth < maxRecurseDepth;

  genPathAttr =
    lib.mapAttrsToList (name: _: {
      inherit name;
      out = builtins.unsafeDiscardStringContext flake.${startPathStr}.${name}.outPath;
      attr = flake.${startPathStr}.${name};
      attrPath = "${startPathStr}.${name}";
      depth = 1;
    })
    (filterAttrs flake.${startPathStr});

  recursePathSearch = pathAttr: let
    recurseInto = pathAttr:
      map (name:
        recursePathSearch {
          inherit name;
          out = builtins.unsafeDiscardStringContext pathAttr.attr.${recursePathStr}.${name}.outPath;
          attr = pathAttr.attr.${recursePathStr}.${name};
          attrPath = "${pathAttr.attrPath}.${recursePathStr}.${name}";
          depth = pathAttr.depth + 1;
        })
      (filterList (builtins.attrNames pathAttr.attr.${recursePathStr}));
  in
    optionalTrace pathAttr.attrPath (
      if dumpAllPaths
      then found pathAttr ++ lib.optionals (attrCheck pathAttr) (recurseInto pathAttr)
      else if builtins.match matchExtRegex pathAttr.name != null
      then found pathAttr
      else if builtins.hasAttr recursePathStr pathAttr.attr && pathAttr.depth < maxRecurseDepth
      then recurseInto pathAttr
      else "recurseEndpointReached"
    );

  searchAttrPath = builtins.concatLists (
    map builtins.attrValues (
      lib.filter (e: builtins.typeOf e == "set" && e ? FOUND) (
        lib.flatten (
          map (
            pathAttr:
              if dumpAllPaths
              then found pathAttr ++ lib.optionals (attrCheck pathAttr) (recursePathSearch pathAttr)
              else if builtins.match matchExtRegex pathAttr.name != null
              then found pathAttr
              else if builtins.hasAttr recursePathStr pathAttr.attr && pathAttr.depth < maxRecurseDepth
              then recursePathSearch pathAttr
              else null
          )
          genPathAttr
        )
      )
    )
  );
in {
  flake.inputsCheck = {
    result = builtins.toJSON searchAttrPath;
    attrPath = builtins.toJSON (map (result: result.attrPath) searchAttrPath);
    out = builtins.toJSON (map (result: result.out) searchAttrPath);
  };
}
# TODO: cleanup
#
# nix eval --raw .#inputsCheck.result \
#   | jq -r '.[] | (.attrPath) + " " + (.depth | tostring) + " " + (.out)' \
#   | xargs -I{} bash -c 'echo "{} $(nix path-info -S $(echo {} | awk "{print \$3}") | awk "{print \$2}")"' \
#   | jq -R '[splits(" +")] | {attrPath: .[0], depth: (.[1] | tonumber), out: .[2], closureSize: (.[3] | tonumber)}' \
#   > inputsCheck.json
#
# jq < inputsCheck.json | jq -s 'sort_by(.closureSize) | reverse' | less -R

