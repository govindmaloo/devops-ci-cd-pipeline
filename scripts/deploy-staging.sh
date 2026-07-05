#!/usr/bin/env bash
# Deploy Flask app to staging on EC2. Called by Jenkins Deploy stage.
set -euo pipefail

STAGING_DIR="${STAGING_DIR:-/var/lib/jenkins/flask-staging}"
WORKSPACE="${WORKSPACE:-$(pwd)}"
MONGO_URI="${MONGO_URI:-mongodb://localhost:27017/studentDB}"
SECRET_KEY="${SECRET_KEY:-staging-secret-key}"

log() { echo "[deploy] $*"; }

log "Deploying from ${WORKSPACE} to ${STAGING_DIR}"

mkdir -p "$STAGING_DIR"
rsync -a --delete \
  --exclude 'venv' \
  --exclude '.git' \
  --exclude '__pycache__' \
  --exclude '.pytest_cache' \
  "${WORKSPACE}/" "${STAGING_DIR}/"

cat > "${STAGING_DIR}/.env" << EOF
MONGO_URI=${MONGO_URI}
SECRET_KEY=${SECRET_KEY}
EOF

if [[ ! -d "${STAGING_DIR}/venv" ]]; then
  python3 -m venv "${STAGING_DIR}/venv"
fi

source "${STAGING_DIR}/venv/bin/activate"
pip install --upgrade pip -q
pip install -r "${STAGING_DIR}/requirements.txt" -q

sudo systemctl restart flask-staging
sleep 3

if curl -sf http://127.0.0.1:5000/ > /dev/null; then
  PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
  log "Staging app is live at http://${PUBLIC_IP}:5000"
else
  log "WARNING: App may still be starting. Check: sudo systemctl status flask-staging"
fi

log "Deploy complete"
