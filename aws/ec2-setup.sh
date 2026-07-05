#!/usr/bin/env bash
# Runs ON the EC2 instance. Installs Jenkins, MongoDB, Python, and clones the app.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

GITHUB_REPO="${GITHUB_REPO:-https://github.com/govindmaloo/devops-ci-cd-pipeline.git}"
APP_DIR="${APP_DIR:-/home/ubuntu/devops-ci-cd-pipeline}"
JENKINS_HOME="${JENKINS_HOME:-/var/lib/jenkins}"

log() { echo "==> $*"; }

log "System update"
sudo apt-get update -y
sudo apt-get upgrade -y

log "Base packages"
sudo apt-get install -y git curl wget unzip software-properties-common gnupg

log "Java 21 (required by latest Jenkins)"
sudo apt-get install -y openjdk-21-jre-headless
JAVA_BIN=$(update-alternatives --list java | grep java-21 | head -1)
java -version

log "Jenkins (WAR + systemd — avoids apt repo GPG issues)"
sudo useradd -r -m -d "$JENKINS_HOME" -s /bin/bash jenkins 2>/dev/null || true
sudo mkdir -p /opt/jenkins
sudo wget -q -O /opt/jenkins/jenkins.war https://get.jenkins.io/war-stable/latest/jenkins.war
sudo chown -R jenkins:jenkins /opt/jenkins "$JENKINS_HOME"

sudo tee /etc/systemd/system/jenkins.service > /dev/null << EOF
[Unit]
Description=Jenkins Automation Server
After=network.target

[Service]
Type=simple
User=jenkins
Group=jenkins
Environment="JENKINS_HOME=${JENKINS_HOME}"
Environment="JAVA_OPTS=-Djava.awt.headless=true"
ExecStart=${JAVA_BIN} -jar /opt/jenkins/jenkins.war --httpPort=8080
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable jenkins
sudo systemctl start jenkins

log "Waiting for Jenkins to start"
for i in $(seq 1 30); do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/login 2>/dev/null || echo "000")
  if [[ "$CODE" == "200" || "$CODE" == "403" ]]; then
    echo "Jenkins ready (HTTP $CODE)"
    break
  fi
  sleep 5
done

log "Python 3"
sudo apt-get install -y python3 python3-pip python3-venv

log "MongoDB 7"
if ! command -v mongosh >/dev/null 2>&1; then
  curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc \
    | sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor
  echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" \
    | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
  sudo apt-get update -y
  sudo apt-get install -y mongodb-org
fi
sudo systemctl enable mongod
sudo systemctl restart mongod
sleep 3
mongosh --quiet --eval "db.runCommand({ ping: 1 })"

log "Clone application repo"
if [[ -d "$APP_DIR/.git" ]]; then
  cd "$APP_DIR" && git pull origin main
else
  git clone "$GITHUB_REPO" "$APP_DIR"
  cd "$APP_DIR"
fi

log "Python venv and dependencies"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip -q
pip install -r requirements.txt -q

cat > .env << 'EOF'
MONGO_URI=mongodb://localhost:27017/studentDB
SECRET_KEY=ec2-dev-secret
EOF

log "Run tests"
pytest test_app.py -v

PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

echo ""
echo "============================================"
echo " EC2 setup complete"
echo "============================================"
echo " Jenkins URL:      http://${PUBLIC_IP}:8080"
echo " Jenkins password: $(sudo cat ${JENKINS_HOME}/secrets/initialAdminPassword)"
echo " App directory:    ${APP_DIR}"
echo " SSH:              ssh -i <key.pem> ubuntu@${PUBLIC_IP}"
echo "============================================"
