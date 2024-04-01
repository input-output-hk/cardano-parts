set shell := ["nu", "-c"]
set positional-arguments
AWS_REGION := 'eu-central-1'

downstreamPath := env_var_or_default("DOWNSTREAM_PATH","no-path-given")
templatePath := 'templates/cardano-parts-project'

default:
  @just --list

# Diff compare a downstream file against a cardano-parts template file
downstream-diff FILE *ARGS:
  #!/usr/bin/env bash
  set -euo pipefail
  if ! [ -f "{{templatePath}}/{{FILE}}" ]; then
    FILE="<(echo '')"
  else
    FILE="{{templatePath}}/{{FILE}}"
  fi

  if [ "{{downstreamPath}}" = "no-path-given" ]; then
    echo "No downstream comparison path has been given.  Please set the DOWNSTREAM_PATH environment variable and try again."
    exit 1
  else
    DWN_FILE="{{downstreamPath}}/{{FILE}}"
    DWN_NAME="$DWN_FILE"
  fi

  eval "icdiff -L \"{{templatePath}}/{{FILE}}\" -L \"$DWN_NAME\" {{ARGS}} $FILE $DWN_FILE"

# Patch a downstream file into a cardano-parts template file
downstream-patch FILE:
  #!/usr/bin/env bash
  set -euo pipefail
  if git status --porcelain "{{templatePath}}/{{FILE}}" | grep -q "{{templatePath}}/{{FILE}}"; then
    echo "Git file {{templatePath}}/{{FILE}} is dirty.  Please revert or commit changes to clean state and try again."
    exit 1
  fi

  if [ "{{downstreamPath}}" = "no-path-given" ]; then
    echo "No downstream comparison path has been given.  Please set the DOWNSTREAM_PATH environment variable and try again."
    exit 1
  else
    DWN_FILE="{{downstreamPath}}/{{FILE}}"
  fi

  PATCH_FILE=$(eval "diff -Naru \"{{templatePath}}/{{FILE}}\" $DWN_FILE || true")
  patch "{{templatePath}}/{{FILE}}" < <(echo "$PATCH_FILE")
  git add -p "{{templatePath}}/{{FILE}}"

lint:
  deadnix -f
  statix check

show-flake *ARGS:
  nix flake show --allow-import-from-derivation {{ARGS}}

update-aws-ec2-spec AWS_PROFILE region=AWS_REGION:
  #!/usr/bin/env nu
  # To describe instance types, any valid aws profile can be provided
  # Default region for specs will be eu-central-1 which provides ~600 machine defns
  let spec = (
    do -c { aws ec2 --profile {{AWS_PROFILE}} --region {{region}} describe-instance-types }
    | from json
    | get InstanceTypes
    | select InstanceType MemoryInfo VCpuInfo
    | reject VCpuInfo.ValidCores? VCpuInfo.ValidThreadsPerCore?
    | sort-by InstanceType
  )
  mkdir flakeModules/aws/
  {InstanceTypes: $spec} | save --force flakeModules/aws/ec2-spec.json
