set shell := ["nu", "-c"]
set positional-arguments

default:
  just --list

lint:
  deadnix -f
  statix check

show-flake:
  nix flake show --allow-import-from-derivation
