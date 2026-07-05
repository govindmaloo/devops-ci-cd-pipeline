#!/usr/bin/env bash
# Runs ON EC2 — called by gh-deploy.sh via SSH.
set -euo pipefail

: "${DEPLOY_DIR:?}"
: "${SERVICE:?}"
: "${PORT:?}"
: "${MONGO_URI:?}"
: "${SECRET_KEY:?}"

log() { echo "[remote-deploy] $*"; }

log "Setting up ${SERVICE} in ${DEPLOY_DIR} on port ${PORT}"

sudo mkdir -p "$DEPLOY_DIR"
sudo tar -xzf /tmp/flask-app.tar.gz -C "$DEPLOY_DIR"
sudo rm -f /tmp/flask-app.tar.gz

sudo tee "${DEPLOY_DIR}/.env" > /dev/null << EOF
MONGO_URI=${MONGO_URI}
SECRET_KEY=${SECRET_KEY}
PORT=${PORT}
EOF

sudo chown -R ubuntu:ubuntu "$DEPLOY_DIR"

if [[ ! -d "${DEPLOY_DIR}/venv" ]]; then
  sudo -u ubuntu python3 -m venv "${DEPLOY_DIR}/venv"
fi

sudo -u ubuntu bash -c "
  cd '${DEPLOY_DIR}'
  source venv/bin/activate
  pip install --upgrade pip -q
  pip install -r requirements.txt -q
"

# Install systemd unit if missing
UNIT_FILE="/etc/systemd/system/${SERVICE}.service"
if [[ ! -f "$UNIT_FILE" ]]; then
  sudo tee "$UNIT_FILE" > /dev/null << EOF
[Unit]
Description=Flask Student App (${SERVICE})
After=network.target mongod.service

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=${DEPLOY_DIR}
EnvironmentFile=${DEPLOY_DIR}/.env
ExecStart=${DEPLOY_DIR}/venv/bin/python app.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable "$SERVICE"
fi

sudo systemctl restart "$SERVICE"
sleep 3

if curl -sf "http://127.0.0.1:${PORT}/" > /dev/null; then
  PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
  log "App live at http://${PUBLIC_IP}:${PORT}"
else
  log "WARNING: health check failed — check: sudo systemctl status ${SERVICE}"
  exit 1
fi

log "Deploy complete"
