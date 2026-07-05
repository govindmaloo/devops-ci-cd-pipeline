#!/usr/bin/env bash
# Deploy Flask app to EC2 from GitHub Actions.
# Usage: gh-deploy.sh <staging|production>
set -euo pipefail

ENV_TARGET="${1:?Usage: gh-deploy.sh <staging|production>}"

: "${EC2_HOST:?EC2_HOST secret is required}"
: "${EC2_SSH_PRIVATE_KEY:?EC2_SSH_PRIVATE_KEY secret is required}"
: "${MONGO_URI:?MONGO_URI secret is required}"
: "${SECRET_KEY:?SECRET_KEY secret is required}"

case "$ENV_TARGET" in
  staging)
    DEPLOY_DIR="/home/ubuntu/flask-staging-gh"
    SERVICE="flask-staging-gh"
    PORT="5000"
    ;;
  production)
    DEPLOY_DIR="/home/ubuntu/flask-production"
    SERVICE="flask-production"
    PORT="5001"
    ;;
  *)
    echo "Unknown environment: $ENV_TARGET"
    exit 1
    ;;
esac

log() { echo "[gh-deploy] $*"; }

log "Deploying to $ENV_TARGET on $EC2_HOST"

mkdir -p ~/.ssh
echo "$EC2_SSH_PRIVATE_KEY" > ~/.ssh/gh_deploy_key
chmod 600 ~/.ssh/gh_deploy_key
ssh-keyscan -H "$EC2_HOST" >> ~/.ssh/known_hosts 2>/dev/null

scp -i ~/.ssh/gh_deploy_key flask-app.tar.gz "ubuntu@${EC2_HOST}:/tmp/flask-app.tar.gz"

ssh -i ~/.ssh/gh_deploy_key "ubuntu@${EC2_HOST}" \
  "DEPLOY_DIR='${DEPLOY_DIR}' SERVICE='${SERVICE}' PORT='${PORT}' \
   MONGO_URI='${MONGO_URI}' SECRET_KEY='${SECRET_KEY}' bash -s" \
  < "$(dirname "$0")/gh-deploy-remote.sh"

log "Deployed to http://${EC2_HOST}:${PORT}"
