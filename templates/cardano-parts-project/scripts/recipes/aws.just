# AWS specific recipes related to non-Tofu infrastructure.
# Doing so will make diffing and patching the main repo Justfile easier.

# Describe an aws ec2 machine
aws-ec2-describe NAME REGION:
  #!/usr/bin/env bash
  set -e
  ID=$(just aws-ec2-id {{NAME}} {{REGION}})
  aws --region {{REGION}} ec2 describe-instances --instance-ids "$ID"

# Get an aws ec2 machine id
aws-ec2-id NAME REGION:
  #!/usr/bin/env bash
  set -e
  ID=$(aws --region {{REGION}} ec2 describe-instances --filters "Name=tag:Name,Values={{NAME}}" --output text --query "Reservations[*].Instances[*].InstanceId")
  if [ -z "${ID:-}" ]; then
    echo >&2 "ERROR: Machine {{NAME}} not found in region {{REGION}}"
    exit 1
  fi
  echo "$ID"

# Start an aws ec2 machine
aws-ec2-start NAME REGION:
  #!/usr/bin/env bash
  set -e
  ID=$(just aws-ec2-id {{NAME}} {{REGION}})
  aws --region {{REGION}} ec2 start-instances --instance-ids "$ID"

# Get an aws ec2 machine status
aws-ec2-status NAME REGION:
  #!/usr/bin/env bash
  set -e
  ID=$(just aws-ec2-id {{NAME}} {{REGION}})
  aws --region {{REGION}} ec2 describe-instance-status --include-all-instances --instance-ids "$ID"

# Stop an aws ec2 machine
aws-ec2-stop NAME REGION:
  #!/usr/bin/env bash
  set -e
  ID=$(just aws-ec2-id {{NAME}} {{REGION}})
  aws --region {{REGION}} ec2 stop-instances --instance-ids "$ID"
