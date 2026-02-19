# flakeModule: inputs.cardano-parts.flakeModules.lib
#
# TODO: Move this to a docs generator
#
# Attributes available on flakeModule import:
#   flake.cardano-parts.lib.opsLib
#   flake.cardano-parts.lib.topologyLib
#
# Tips:
#   * flake level attrs are accessed from flake level at [config.]flake.cardano-parts.lib.<...>
{lib, ...}: let
  inherit (lib) mkDefault mkOption types;
  inherit (types) attrsOf anything functionTo submodule;

  mainSubmodule = submodule {
    options = {
      lib = mkOption {
        type = libSubmodule;
        description = "Cardano-parts lib options";
        default = {};
      };
    };
  };

  libSubmodule = submodule {
    options = {
      opsLib = mkOption {
        type = functionTo (attrsOf anything);
        description = ''
          The cardano-parts ops library.

          A miscellaneous library for shared code used in various places
          such as jobs, entrypoints and other ops related code.

          Consumers of the default definition of this library
          need to pass pkgs to initialize this library.
        '';
        default = import ./lib/ops.nix;
      };

      topologyLib = mkOption {
        type = functionTo (attrsOf anything);
        description = ''
          The cardano-parts topology library.

          Consumers of the default definition of this library
          need to pass a valid cardano-parts.cluster.groups.$GROUPNAME
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
