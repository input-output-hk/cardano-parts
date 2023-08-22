set shell := ["nu", "-c"]
set positional-arguments

default:
  just --list

lint:
  deadnix -f
  statix check

show-flake *ARGS:
  nix flake show --allow-import-from-derivation {{ARGS}}
