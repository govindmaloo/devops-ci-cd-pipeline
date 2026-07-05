#!/usr/bin/env bash
# Provision EC2 on AWS and install Jenkins + dependencies.
# Run from your local machine (requires AWS CLI and SSH).
#
# Usage:
#   ./aws/setup.sh              # Full setup (provision + configure EC2)
#   ./aws/setup.sh provision    # AWS resources only (key, SG, EC2)
#   ./aws/setup.sh configure    # EC2 software only (SSH into existing instance)
#   ./aws/setup.sh status       # Show instance IP and Jenkins URL
#   ./aws/setup.sh destroy      # Terminate instance and delete key/SG
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Config (override via env vars) ---
AWS_REGION="${AWS_REGION:-ap-south-1}"
KEY_NAME="${KEY_NAME:-jenkins-flask-key}"
SG_NAME="${SG_NAME:-jenkins-flask-sg}"
INSTANCE_NAME="${INSTANCE_NAME:-jenkins-flask-server}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.micro}"
VOLUME_SIZE_GB="${VOLUME_SIZE_GB:-20}"
KEY_PATH="${KEY_PATH:-$HOME/Downloads/${KEY_NAME}.pem}"
GITHUB_REPO="${GITHUB_REPO:-https://github.com/govindmaloo/devops-ci-cd-pipeline.git}"
STATE_FILE="${STATE_FILE:-$SCRIPT_DIR/.setup-state}"

# Ubuntu 22.04 LTS — fetched dynamically; override if needed
AMI_ID="${AMI_ID:-}"

log()  { echo "==> $*"; }
warn() { echo "WARNING: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed."
}

save_state() {
  # shellcheck disable=SC2086
  echo "$@" > "$STATE_FILE"
}

load_state() {
  [[ -f "$STATE_FILE" ]] || return 1
  # shellcheck disable=SC1090
  source "$STATE_FILE"
}

get_ubuntu_ami() {
  if [[ -n "$AMI_ID" ]]; then
    echo "$AMI_ID"
    return
  fi
  aws ec2 describe-images \
    --owners 099720109477 \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
              "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text \
    --region "$AWS_REGION"
}

provision_key_pair() {
  if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$AWS_REGION" &>/dev/null; then
    warn "Key pair '$KEY_NAME' already exists in AWS."
    [[ -f "$KEY_PATH" ]] || die "Key file missing at $KEY_PATH — delete the key pair in AWS or set KEY_PATH."
  else
    log "Creating key pair: $KEY_NAME"
    aws ec2 create-key-pair \
      --key-name "$KEY_NAME" \
      --region "$AWS_REGION" \
      --query 'KeyMaterial' \
      --output text > "$KEY_PATH"
    chmod 400 "$KEY_PATH"
    log "Saved private key to $KEY_PATH"
  fi
}

provision_security_group() {
  local vpc_id sg_id
  vpc_id=$(aws ec2 describe-vpcs \
    --filters "Name=isDefault,Values=true" \
    --query 'Vpcs[0].VpcId' --output text --region "$AWS_REGION")

  sg_id=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$vpc_id" \
    --query 'SecurityGroups[0].GroupId' --output text --region "$AWS_REGION" 2>/dev/null || echo "None")

  if [[ "$sg_id" == "None" || -z "$sg_id" ]]; then
    log "Creating security group: $SG_NAME"
    sg_id=$(aws ec2 create-security-group \
      --group-name "$SG_NAME" \
      --description "Jenkins + Flask app (SSH 22, Jenkins 8080, Flask 5000)" \
      --vpc-id "$vpc_id" \
      --region "$AWS_REGION" \
      --query 'GroupId' --output text)

    for port in 22 8080 5000; do
      aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" --protocol tcp --port "$port" \
        --cidr 0.0.0.0/0 --region "$AWS_REGION" >/dev/null
      log "Opened port $port"
    done
  else
    warn "Security group '$SG_NAME' already exists: $sg_id"
  fi

  echo "$sg_id"
}

provision_instance() {
  local ami_id sg_id instance_id ec2_ip

  ami_id=$(get_ubuntu_ami)
  [[ -n "$ami_id" && "$ami_id" != "None" ]] || die "Could not resolve Ubuntu 22.04 AMI in $AWS_REGION"

  sg_id=$(provision_security_group)

  # Reuse running/stopped instance if tagged with our name
  instance_id=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME" \
              "Name=instance-state-name,Values=running,stopped,pending" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text --region "$AWS_REGION" 2>/dev/null || echo "None")

  if [[ "$instance_id" != "None" && -n "$instance_id" ]]; then
    warn "Instance '$INSTANCE_NAME' already exists: $instance_id"
    local state
    state=$(aws ec2 describe-instances --instance-ids "$instance_id" \
      --query 'Reservations[0].Instances[0].State.Name' --output text --region "$AWS_REGION")
    if [[ "$state" == "stopped" ]]; then
      log "Starting stopped instance"
      aws ec2 start-instances --instance-ids "$instance_id" --region "$AWS_REGION" >/dev/null
      aws ec2 wait instance-running --instance-ids "$instance_id" --region "$AWS_REGION"
    fi
  else
    log "Launching EC2 instance ($INSTANCE_TYPE, AMI $ami_id)"
    instance_id=$(aws ec2 run-instances \
      --image-id "$ami_id" \
      --instance-type "$INSTANCE_TYPE" \
      --key-name "$KEY_NAME" \
      --security-group-ids "$sg_id" \
      --region "$AWS_REGION" \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
      --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":${VOLUME_SIZE_GB},\"VolumeType\":\"gp3\"}}]" \
      --query 'Instances[0].InstanceId' --output text)

    aws ec2 wait instance-running --instance-ids "$instance_id" --region "$AWS_REGION"
  fi

  ec2_ip=$(aws ec2 describe-instances --instance-ids "$instance_id" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text --region "$AWS_REGION")

  save_state "INSTANCE_ID=$instance_id" "EC2_IP=$ec2_ip" "SG_ID=$sg_id" "KEY_PATH=$KEY_PATH" "AWS_REGION=$AWS_REGION"

  log "Instance ready: $instance_id @ $ec2_ip"
  echo "$ec2_ip"
}

wait_for_ssh() {
  local ec2_ip="$1" key_path="$2"
  log "Waiting for SSH on $ec2_ip"
  for i in $(seq 1 30); do
    if ssh -i "$key_path" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
         "ubuntu@$ec2_ip" "echo ok" &>/dev/null; then
      log "SSH connected"
      return 0
    fi
    sleep 10
  done
  die "SSH not available after 5 minutes"
}

configure_ec2() {
  local ec2_ip key_path

  if [[ -n "${1:-}" ]]; then
    ec2_ip="$1"
    key_path="${2:-$KEY_PATH}"
  elif load_state; then
    ec2_ip="$EC2_IP"
    key_path="$KEY_PATH"
  else
    die "No EC2 IP found. Run './aws/setup.sh provision' first or pass: configure <EC2_IP>"
  fi

  [[ -f "$key_path" ]] || die "SSH key not found: $key_path"
  wait_for_ssh "$ec2_ip" "$key_path"

  log "Running ec2-setup.sh on $ec2_ip"
  scp -i "$key_path" -o StrictHostKeyChecking=no \
    "$SCRIPT_DIR/ec2-setup.sh" "ubuntu@$ec2_ip:/tmp/ec2-setup.sh"
  ssh -i "$key_path" -o StrictHostKeyChecking=no "ubuntu@$ec2_ip" \
    "chmod +x /tmp/ec2-setup.sh && GITHUB_REPO='$GITHUB_REPO' /tmp/ec2-setup.sh"
}

show_status() {
  if ! load_state; then
    warn "No state file at $STATE_FILE"
    instance_id=$(aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" \
      --query 'Reservations[0].Instances[0].InstanceId' --output text --region "$AWS_REGION" 2>/dev/null || echo "None")
    [[ "$instance_id" != "None" ]] || die "No running instance found"
    ec2_ip=$(aws ec2 describe-instances --instance-ids "$instance_id" \
      --query 'Reservations[0].Instances[0].PublicIpAddress' --output text --region "$AWS_REGION")
  else
    instance_id="$INSTANCE_ID"
    ec2_ip="$EC2_IP"
  fi

  echo ""
  echo "Instance ID : $instance_id"
  echo "Public IP   : $ec2_ip"
  echo "Region      : $AWS_REGION"
  echo "SSH         : ssh -i $KEY_PATH ubuntu@$ec2_ip"
  echo "Jenkins URL : http://$ec2_ip:8080"
  echo ""
  ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
    "ubuntu@$ec2_ip" \
    "sudo cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null" \
    && echo "(Jenkins initial admin password above)" \
    || echo "(Could not fetch Jenkins password — instance may still be starting)"
}

destroy_resources() {
  load_state || true

  if [[ -n "${INSTANCE_ID:-}" ]]; then
    log "Terminating instance $INSTANCE_ID"
    aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" >/dev/null
    aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
  fi

  if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$AWS_REGION" &>/dev/null; then
    log "Deleting key pair $KEY_NAME"
    aws ec2 delete-key-pair --key-name "$KEY_NAME" --region "$AWS_REGION"
  fi

  local sg_id
  sg_id=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" \
    --query 'SecurityGroups[0].GroupId' --output text --region "$AWS_REGION" 2>/dev/null || echo "None")
  if [[ "$sg_id" != "None" && -n "$sg_id" ]]; then
    log "Deleting security group $sg_id"
    aws ec2 delete-security-group --group-id "$sg_id" --region "$AWS_REGION" || \
      warn "Could not delete SG (may need a retry after instance terminates)"
  fi

  rm -f "$STATE_FILE"
  log "Cleanup complete"
}

main() {
  require_cmd aws
  require_cmd ssh
  require_cmd scp

  aws sts get-caller-identity --region "$AWS_REGION" >/dev/null \
    || die "AWS CLI not authenticated. Run 'aws configure'."

  local cmd="${1:-all}"
  case "$cmd" in
    all)
      provision_key_pair
      provision_instance >/dev/null
      configure_ec2
      show_status
      ;;
    provision)
      provision_key_pair
      provision_instance
      ;;
    configure)
      configure_ec2 "${2:-}" "${3:-}"
      ;;
    status)
      show_status
      ;;
    destroy)
      read -r -p "Terminate EC2 and delete key/SG? [y/N] " confirm
      [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
      destroy_resources
      ;;
    *)
      die "Unknown command: $cmd. Use: all | provision | configure | status | destroy"
      ;;
  esac
}

main "$@"
