# flakeModule: inputs.cardano-parts.flakeModules.lib
#
# TODO: Move this to a docs generator
#
# Attributes available on flakeModule import:
#   flake.cardano-parts.lib.topologyLib
#
# Tips:
#   * flake level attrs are accessed from flake level at [config.]flake.cardano-parts.lib.<...>
{
  config,
  lib,
  ...
}: let
  inherit (lib) mdDoc mkDefault mkOption types;
  inherit (types) attrsOf anything functionTo submodule;

  mainSubmodule = submodule {
    options = {
      lib = mkOption {
        type = libSubmodule;
        description = mdDoc "Cardano-parts lib options";
        default = {};
      };
    };
  };

  libSubmodule = submodule {
    options = {
      topologyLib = mkOption {
        type = functionTo (attrsOf anything);
        description = mdDoc ''
          The cardano-parts topology library.

          Consumers of the default definition of this library
          need to pass a valid cardano-parts.cluster.group.$GROUPNAME
          to initialize this library for use in a given customizable
          cardano environment.
        '';
        default = import ./lib/topology.nix lib;
      };
    };
  };
in {
  options = {
    # Top level option definition
    flake.cardano-parts = mkOption {
      type = mainSubmodule;
    };
  };

  config = {
    # Top level config definition
    flake.cardano-parts = mkDefault {};
  };
}
