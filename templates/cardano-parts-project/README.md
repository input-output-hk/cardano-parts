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

This will be done automatically if you are using [direnv](https://direnv.net/)
and issue `direnv allow`.

Note that the nix version must be at least `2.17` and `fetch-closure`,
`flakes` and `nix-command` must be included in your nix config for
`experimental-features`.

## AWS

From the parent AWS org, create an IAM identity center user with your name and
`AdministratorAccess` to the AWS account of the `$REPO` deployment, then store
the config in `~/.aws/config` under the profile name `$REPO`:

    [sso-session $PARENT_ORG_NAME]
    sso_start_url = https://$IAM_CENTER_URL_ID.awsapps.com/start
    sso_region = $REGION
    sso_registration_scopes = sso:account:access

    [profile $REPO]
    sso_session = $PARENT_ORG_NAME
    sso_account_id = $REPO_ARN_ORG_ID
    sso_role_name = AdministratorAccess
    region = $REGION

The `$PARENT_ORG_NAME` can be set to what you prefer, ex: `ioe`.  The
`$IAM_CENTER_URL_ID` and `$REGION` will be provided when creating your IAM
identity center user and the `$REPO_ARN_ORG_ID` will be obtained in AWS as
the `$REPO` org ARN account number.

If your AWS setup uses a flat or single org structure, then adjust IAM identity
center account access and the above config to reflect this.  The above config
can also be generated from the devshell using:

    aws configure sso

When adding additional profiles the `aws configure sso` command may create
duplicate sso-session blocks or cause other issues, so manually adding new
profiles is preferred.  Before accessing or using `$REPO` org resources, you
will need to start an sso session which can be done by:

    just aws-sso-login

While the identity center approach above gives session based access, it also
requires periodic manual session refreshes which are more difficult to
accomplish on a headless system or shared deployer.  For those use cases, IAM
of the `$REPO` organization can be used to create an AWS user with your name and
`AdministratorAccess` policy.  With this approach, create an access key set for
your IAM user and store them in `~/.aws/credentials` under the profile name
`$REPO`:

    [$REPO]
    aws_access_key_id = XXXXXXXXXXXXXXXXXXXX
    aws_secret_access_key = XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

No session initiation will be required and AWS resources in the org can be used
immediately.

In the case that a profile exists in both `~/.aws/config` and
`~/.aws/credentials`, the `~/.aws/config` sso definition will take precedence.

## AGE Admin

While cluster secrets shared by all machines are generally handled using AWS
KMS, per machine secrets are handled using sops-nix age.  However, an admin age
key is still typically desired so that all per machine secrets can be decrypted
by an admin or SRE.  A new age admin key can be generated with `age-keygen` and
this should be placed in `~/.age/credentials`:

    # $REPO: sre
    AGE-SECRET-KEY-***********************************************************

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

## SSH

If your credentials are correct, and the cluster is already provisioned with
openTofu infrastructure, you will be able to access SSH after creating an
`./.ssh_config` and nix ip module information using:

    just save-ssh-config
    just update-ips

With that you can then get started with:

    # List machines
    just list-machines

    # Ssh to a newly provisioned machine
    just ssh-bootstrap $MACHINE

    # Ssh to a machine already deployed
    just ssh $MACHINE

    # Find many other operations recipes to use
    just --list

Behind the scenes ssh is using AWS SSM and no open port 22 is required.  In
fact, the default template for a cardano-parts repo does not open port 22 for
ingress on security groups.

For special use cases which still utilize port 22 ingress for ssh, ipv4 or ipv6
ssh_config can be used by appending `.ipv4` or `.ipv6` to the target hostname.

## Colmena

To deploy changes on an OS level, we use the excellent
[Colmena](https://github.com/zhaofengli/colmena).

All colmena configuration is in `./flake/colmena.nix`.

To deploy a machine for the first time:

    just apply-bootstrap $MACHINE

To subsequently deploy a machine:

    just apply $MACHINE

## Secrets

Secrets are encrypted using [SOPS](https://github.com/getsops/sops) with
[KMS](https://aws.amazon.com/kms/) and
[AGE](https://github.com/FiloSottile/age).

All secrets live in `./secrets/`

KMS encryption is generally used for secrets intended to be consumed by all
machines as it has the benefit over age encryption of not needing re-encryption
every time a machine in the cluster changes. To sops encrypt a secret file
intended for all machines with KMS:

    sops --encrypt \
      --kms "$KMS" \
      --config /dev/null \
      --input-type binary \
      --output-type binary \
      $SECRET_FILE \
    > secrets/$SECRET_FILE.enc

    rm unencrypted-secret-file

For per-machine secrets, age encryption is preferred, where each secret is
typically encrypted only for the target machine and an admin such as an SRE.

Age public and private keys will be automatically derived for each deployed
machine from the machine's `/etc/ssh/ssh_host_ed25519_key` file.  Therefore, no
manual generation of private age keys for machines is required and the public
age key for each machine is printed during each `colmena` deployment, example:

    > just apply machine
    ...
    machine | sops-install-secrets: Imported /etc/ssh/ssh_host_ed25519_key as age key with fingerprint $AGE_PUBLIC_KEY
    ...

These machine public age keys become the basis for access assignment of
per-machine secrets declared in [.sops.yaml](.sops.yaml)

A machine's age public key can also be generated on demand:

    just ssh machine -- "'ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub'"

A KMS or age sops secret file can generally be edited using:

    sops ./secrets/github-token.enc

Or simply decrypt a KMS or age sops secret with:

    sops -d ./secrets/github-token.enc

In cases where the decrypted data is in json format, sops args of `--input-type
binary --output-type binary` may also be required to avoid decryption embedded
in json.

See also related sops encryption and decryption recipes:

    just sops-decrypt-binary "$FILE"                          # Decrypt a file to stdout using .sops.yaml rules
    just sops-decrypt-binary-in-place "$FILE"                 # Decrypt a file in place using .sops.yaml rules
    just sops-encrypt-binary "$FILE"                          # Encrypt a file in place using .sops.yaml rules
    just sops-rotate-binary "$FILE"                           # Rotate sops encryption using .sops.yaml rules
