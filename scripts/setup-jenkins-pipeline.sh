#!/usr/bin/env bash
# Configure Jenkins pipeline on EC2 after Jenkins is installed.
# Run on EC2: sudo bash scripts/setup-jenkins-pipeline.sh
set -euo pipefail

JENKINS_HOME="/var/lib/jenkins"
GITHUB_REPO="${GITHUB_REPO:-https://github.com/govindmaloo/devops-ci-cd-pipeline.git}"
JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER:-admin}"
JENKINS_ADMIN_PASS="${JENKINS_ADMIN_PASS:-Jenkins@2026}"
JOB_NAME="${JOB_NAME:-flask-pipeline}"

log() { echo "==> $*"; }

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo bash $0"; exit 1; }

log "Install flask-staging systemd service"
cp "$(dirname "$0")/flask-staging.service" /etc/systemd/system/flask-staging.service
mkdir -p /var/lib/jenkins/flask-staging
chown -R jenkins:jenkins /var/lib/jenkins/flask-staging
systemctl daemon-reload
systemctl enable flask-staging

log "Allow jenkins user to restart flask-staging"
echo "jenkins ALL=(ALL) NOPASSWD: /bin/systemctl restart flask-staging, /bin/systemctl status flask-staging" \
  > /etc/sudoers.d/jenkins-flask
chmod 440 /etc/sudoers.d/jenkins-flask

log "Bootstrap Jenkins admin user (skip setup wizard)"
mkdir -p "${JENKINS_HOME}/init.groovy.d"
cat > "${JENKINS_HOME}/init.groovy.d/basic-security.groovy" << GROOVY
import jenkins.model.*
import hudson.security.*
import jenkins.install.InstallState

def instance = Jenkins.getInstance()

if (instance.getSecurityRealm() == null || instance.getSecurityRealm().getClass().getName().contains('None')) {
    def realm = new HudsonPrivateSecurityRealm(false)
    realm.createAccount('${JENKINS_ADMIN_USER}', '${JENKINS_ADMIN_PASS}')
    instance.setSecurityRealm(realm)
}

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

if (!InstallState.getInstance().isSetupComplete()) {
    InstallState.getInstance().setInstallState(InstallState.INITIAL_SETUP_COMPLETED)
}

instance.save()
GROOVY

chown -R jenkins:jenkins "${JENKINS_HOME}/init.groovy.d"

log "Restart Jenkins to apply security bootstrap"
systemctl restart jenkins

log "Waiting for Jenkins..."
for i in $(seq 1 30); do
  if curl -sf -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASS}" \
       "http://127.0.0.1:8080/api/json" >/dev/null 2>&1; then
    log "Jenkins is ready"
    break
  fi
  sleep 5
done

log "Install Jenkins plugins"
PLUGIN_MANAGER="/tmp/jenkins-plugin-manager.jar"
curl -fsSL "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.13.2/jenkins-plugin-manager-2.13.2.jar" \
  -o "$PLUGIN_MANAGER"
java -jar "$PLUGIN_MANAGER" \
  --war /opt/jenkins/jenkins.war \
  --plugin-download-directory "${JENKINS_HOME}/plugins" \
  --plugins "git workflow-aggregator email-ext pipeline-stage-view workflow-job"
chown -R jenkins:jenkins "${JENKINS_HOME}/plugins"

systemctl restart jenkins
sleep 20

log "Create pipeline job: ${JOB_NAME}"
mkdir -p "${JENKINS_HOME}/jobs/${JOB_NAME}"
cat > "${JENKINS_HOME}/jobs/${JOB_NAME}/config.xml" << XMLEOF
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>Flask CI/CD Pipeline - Build, Test, Deploy to Staging</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps">
    <scm class="hudson.plugins.git.GitSCM" plugin="git">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>${GITHUB_REPO}</url>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/main</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
      <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
      <submoduleCfg class="empty-list"/>
      <extensions/>
    </scm>
    <scriptPath>Jenkinsfile</scriptPath>
    <lightweight>true</lightweight>
  </definition>
  <triggers>
    <hudson.triggers.SCMTrigger>
      <spec>H/2 * * * *</spec>
      <ignorePostCommitHooks>false</ignorePostCommitHooks>
    </hudson.triggers.SCMTrigger>
  </triggers>
  <disabled>false</disabled>
</flow-definition>
XMLEOF

chown -R jenkins:jenkins "${JENKINS_HOME}/jobs/${JOB_NAME}"
systemctl restart jenkins
sleep 15

PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

echo ""
echo "============================================"
echo " Jenkins pipeline configured"
echo "============================================"
echo " Jenkins URL:  http://${PUBLIC_IP}:8080"
echo " Admin user:   ${JENKINS_ADMIN_USER}"
echo " Admin pass:   ${JENKINS_ADMIN_PASS}"
echo " Pipeline job: ${JOB_NAME}"
echo " Staging app:  http://${PUBLIC_IP}:5000 (after first deploy)"
echo "============================================"
echo ""
echo "Next: open Jenkins → ${JOB_NAME} → Build Now"
