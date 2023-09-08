lib: groupCfg:
# Argument `lib` is provided by the lib flakeModule topology option default:
#   flake.cardano-parts.lib.topology
#
# Argument groupCfg is provided by nixosModules whenever topology lib is required.
# GroupCfg is a mechanism to allow multiple cardano networks within a single repo.
with lib; rec {
  inherit (groupCfg.meta) domain;

  # Function composition
  compose = f: g: x: f (g x);

  # Compose list of function
  composeAll = builtins.foldl' compose id;
}
