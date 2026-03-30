{
  inputs,
  lib,
  ...
}: let
  inherit (lib) replaceStrings;
in {
  flake.lib =
    inputs.cardano-parts.lib
    // {
      strings = {
        dashToSnake = replaceStrings ["-"] ["_"];
        snakeToDash = replaceStrings ["_"] ["-"];
      };
    };
}
