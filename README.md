<p align="center">
  <img width='150px' src="docs/theme/cardano-logo.png" alt='Cardano Logo' />
</p>

<p align="center">
  Welcome to the Cardano Parts Repository
  <br />
</p>

Cardano is a decentralized third-generation proof-of-stake blockchain platform
and home to the ada cryptocurrency. It is the first blockchain platform to
evolve out of a scientific philosophy and a research-first driven approach.

# Cardano Parts

The cardano-parts project serves as the common code repository for deploying
cardano networks. It utilizes [flake-parts](https://flake.parts/) and provides
nixosModules and flakeModules to downstream consumers, such as
[cardano-playground](https://github.com/input-output-hk/cardano-playground).

Multiple cardano networks can be defined and deployed from within a single
downstream repository.

Various nixos modules are provided which support cardano network deployments
including roles of:

    cardano-node
    cardano-db-sync
    cardano-smash
    cardano-faucet
    cardano-metadata


## Getting started

Create a new cardano-parts project with:

    nix flake new -t github:input-output-hk/cardano-parts <NEW_DIRECTORY>

Git add all new project files:

    cd <NEW_DIRECTORY> && git init && git add -Afv

Update the following files in the `<NEW_DIRECTORY>`:

    # Update with details of your new cluster
    flake/cluster.nix

    # Update with details of your new nodes
    flake/colmena.nix

    # Update to define SSH access via auth-keys-hub
    flake/nixosModules/common.nix

    # If needed: resource customization
    flake/cloudFormation/terraformState.nix
    flake/opentofu/cluster.nix

Continue following the [README](templates/cardano-parts-project/README.md)
found in your <NEW_DIRECTORY> and customize it as desired.
