set shell := ["nu", "-c"]
set positional-arguments

default:
  just --list

lint:
  deadnix -f
  statix check
