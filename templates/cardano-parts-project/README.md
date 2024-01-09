<p align="center">
  <img width='150px' src="docs/theme/cardano-logo.png" alt='Cardano Logo' />
</p>

<p align="center">
  Welcome to the Cardano $REPO Repository
  <br />
</p>

Cardano is a decentralized third-generation proof-of-stake blockchain platform and home to the ada cryptocurrency.
It is the first blockchain platform to evolve out of a scientific philosophy and a research-first driven approach.

# Cardano $REPO

The $REPO project serves as ...

It utilizes [flake-parts](https://flake.parts/) and re-usable
nixosModules and flakeModules from [cardano-parts](https://github.com/input-output-hk/cardano-parts).

## Getting started

While working on the next step, you can already start the devshell using:

    nix develop

This will be done automatically if you are using [direnv](https://direnv.net/).

## AWS

Create an AWS user with your name and `AdministratorAccess` policy in the
$REPO organization, then store your access key in
`~/.aws/credentials` under the profile name `$REPO`:

    [$REPO]
    aws_access_key_id = XXXXXXXXXXXXXXXXXXXX
    aws_secret_access_key = XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

## AGE

While cluster secrets are handled using AWS KMS, per machine secrets are
handled using sops-nix age.  For sops-nix age secrets access, place the
SRE cluster secret in `~/.age/credentials`:

    # $REPO: sre
    AGE-SECRET-KEY-***********************************************************

## SSH

If your credentials are correct, you will be able to access SSH after creating
an `./.ssh_config` using:

    just save-ssh-config

With that you can then get started with:

    # Listing machines
    just list-machines

    # Ssh to machines
    just ssh $MACHINE

    # Finding other operations recipes to use
    just --list

## Cloudformation

We bootstrap our infrastructure using AWS Cloudformation, it creates resources
like S3 Buckets, a DNS Zone, KMS key, and OpenTofu state storage.

The distinction of what is managed by Cloudformation and OpenTofu is not very
strict, but generally anything that is not of the mentioned resource types will
go into OpenTofu since they are harder to configure and reuse otherwise.

All configuration is in `./flake/cloudFormation/terraformState.nix`

We use [Rain](https://github.com/aws-cloudformation/rain) to apply the
configuration. There is a wrapper that evaluates the config and deploys it:

    just cf terraformState

When arranging DNS zone delegation, the nameservers to delegate to are shown with:

    just show-nameservers

## OpenTofu

We use [OpenTofu](https://opentofu.org/) to create AWS instances, roles,
profiles, policies, Route53 records, EIPs, security groups, and similar.

All monitoring dashboards, alerts and recording rules are configured in `./flake/opentofu/grafana.nix`

All other cluster resource configuration is in `./flake/opentofu/cluster.nix`

The wrapper to setup the state, workspace, evaluate the config, and run `tofu`
for cluster resources is:

    just tofu [cluster] plan
    just tofu [cluster] apply

Similarly, for monitoring resources:

    just tofu grafana plan
    just tofu grafana apply

## Colmena

To deploy changes on an OS level, we use the excellent
[Colmena](https://github.com/zhaofengli/colmena).

All colmena configuration is in `./flake/colmena.nix`.

To deploy a machine:

    just apply $MACHINE

## Secrets

Secrets are encrypted using [SOPS](https://github.com/getsops/sops) and [KMS](https://aws.amazon.com/kms/).

All secrets live in `./secrets/`

You should be able to edit a KMS or sops age secret using:

    sops ./secrets/github-token.enc

Or simply decrypt a KMS or sops age secret with:

    sops -d ./secrets/github-token.enc

See also the `just sops-<encrypt|decrypt>-binary` recipes for encrypting or decrypting age binary blobs.
