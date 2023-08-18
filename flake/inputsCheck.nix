flake @ {lib, ...}: let
  p = v: lib.traceSeq v v;

  # Attrset defaults don't work from impure cli passing to functions
  parseArgs = args:
    p (lib.foldl' lib.recursiveUpdate {} [
      # Search defns
      (parseArg args "startPathStr" "inputs")
      (parseArg args "recursePathStr" "inputs")

      # To scan though all discovered inputs and search for closureSize
      (parseArg args "dumpAllPaths" true)

      # Blank if dumpAllPaths, otherwise, a regex match string
      (parseArg args "matchExtRegex" "")

      # Depth limiter
      (parseArg args "maxRecurseDepth" 6)

      # Redundant or infinite recursion exclusions here
      (parseArg args "denyList" ["self"])

      # Optionally show all fullPaths as they are recursed
      (parseArg args "pathTrace" false)
    ]);

  parseArg = args: name: default: {
    ${name} =
      if builtins.hasAttr name args
      then args.${name}
      else default;
  };

  optionalTrace = args: attrPath: eval:
    if args.pathTrace
    then builtins.trace attrPath eval
    else eval;

  filterAttrs = args: lib.filterAttrs (n: _: !(builtins.elem n args.denyList));
  filterList = args: builtins.filter (n: !(builtins.elem n args.denyList));

  found = pathAttr: [{FOUND = {inherit (pathAttr) attrPath out depth;};}];
  attrCheck = pathAttr: args: builtins.hasAttr args.recursePathStr pathAttr.attr && pathAttr.depth < args.maxRecurseDepth;

  genPathAttr = args:
    lib.mapAttrsToList (name: _: {
      inherit name;
      out = builtins.unsafeDiscardStringContext flake.${args.startPathStr}.${name}.outPath;
      attr = flake.${args.startPathStr}.${name};
      attrPath = "${args.startPathStr}.${name}";
      depth = 1;
    })
    (filterAttrs args flake.${args.startPathStr});

  recursePathSearch = pathAttr: args: let
    recurseInto = pathAttr:
      map (name:
        recursePathSearch {
          inherit name;
          out = builtins.unsafeDiscardStringContext pathAttr.attr.${args.recursePathStr}.${name}.outPath;
          attr = pathAttr.attr.${args.recursePathStr}.${name};
          attrPath = "${pathAttr.attrPath}.${args.recursePathStr}.${name}";
          depth = pathAttr.depth + 1;
        }
        args)
      (filterList args (builtins.attrNames pathAttr.attr.${args.recursePathStr}));
  in
    optionalTrace args pathAttr.attrPath (
      if args.dumpAllPaths
      then found pathAttr ++ lib.optionals (attrCheck pathAttr args) (recurseInto pathAttr)
      else if builtins.match args.matchExtRegex pathAttr.name != null
      then found pathAttr
      else if attrCheck pathAttr args
      then recurseInto pathAttr
      else "recurseEndpointReached"
    );

  searchAttrPath = args:
    builtins.concatLists (
      map builtins.attrValues (
        lib.filter (e: builtins.typeOf e == "set" && e ? FOUND) (
          lib.flatten (
            map (
              pathAttr:
                if args.dumpAllPaths
                then found pathAttr ++ lib.optionals (attrCheck pathAttr args) (recursePathSearch pathAttr args)
                else if builtins.match args.matchExtRegex pathAttr.name != null
                then found pathAttr
                else if attrCheck pathAttr args
                then recursePathSearch pathAttr args
                else null
            )
            (genPathAttr args)
          )
        )
      )
    );
in {
  flake.inputsCheck = args: builtins.toJSON (searchAttrPath (parseArgs args));

  perSystem = {pkgs, ...}: {
    packages.inputs-check = with pkgs;
      writeShellApplication {
        name = "inputs-check";
        runtimeInputs = [findutils jq nix];
        text = ''
          [ -n "''${1:-}" ] && ARGS="$1" || ARGS="{}"
          # shellcheck disable=SC2016
          nix eval \
            --raw \
            --impure \
            --expr "let f = builtins.getFlake (toString ./.); in f.inputsCheck $ARGS" \
            | jq -r '.[] | (.attrPath) + " " + (.depth | tostring) + " " + (.out)' \
            | xargs -I{} bash -c 'echo "{} $(nix path-info -S $(echo {} | awk "{print \$3}") | awk "{print \$2}")"' \
            | jq -R '[splits(" +")] | {attrPath: .[0], depth: (.[1] | tonumber), out: .[2], closureSize: (.[3] | tonumber)}' \
            | jq -s 'sort_by(.closureSize) | reverse'
        '';
      };
  };
}
