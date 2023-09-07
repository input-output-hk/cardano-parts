set shell := ["nu", "-c"]
set positional-arguments
AWS_REGION := 'eu-central-1'

default:
  just --list

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
