#!/usr/bin/env bash
# Jenkins controller + build tools + a tiny artifact repository.
#   Jenkins UI       http://jenkins.lab.internal:8080
#   Artifact repo    http://jenkins.lab.internal:8081/   (nginx; stand-in for Nexus/Artifactory)
# Tools for the pipelines: JDK 21 + Maven (Java build), Cinc Workstation
# (knife, cinc, cookstyle, chefspec, kitchen, cinc-auditor) and Docker (Test Kitchen).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo ">> Java 21, Maven, Git, Docker, nginx"
apt-get install -y -qq fontconfig openjdk-21-jdk maven git docker.io nginx python3 jq unzip >/dev/null

if ! dpkg -s jenkins >/dev/null 2>&1; then
  echo ">> Jenkins LTS"
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key -o /etc/apt/keyrings/jenkins-keyring.asc
  echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
    > /etc/apt/sources.list.d/jenkins.list
  apt-get update -qq
  apt-get install -y -qq jenkins >/dev/null
fi

if ! command -v cinc >/dev/null 2>&1; then
  echo ">> Cinc Workstation 26 (knife, cookstyle, kitchen, chefspec, cinc-auditor)"
  curl -fsSL https://omnitruck.cinc.sh/install.sh | bash -s -- -P cinc-workstation -v 26
fi

echo ">> let Jenkins run Docker (needed by Test Kitchen / kitchen-dokken)"
usermod -aG docker jenkins

# knife ssh / ssh record node host keys here
install -d -o jenkins -g jenkins -m 0700 /var/lib/jenkins/.ssh

echo ">> artifact repository on :8081"
install -d -o jenkins -g jenkins -m 0755 /var/www/artifacts /var/www/artifacts/myapp
cat > /etc/nginx/sites-available/artifacts <<'EOF'
server {
    listen 8081;
    server_name _;
    root /var/www/artifacts;
    autoindex on;            # browse http://jenkins.lab.internal:8081/myapp/
    location / { try_files $uri $uri/ =404; }
}
EOF
ln -sf /etc/nginx/sites-available/artifacts /etc/nginx/sites-enabled/artifacts
rm -f /etc/nginx/sites-enabled/default
systemctl enable --now nginx
systemctl reload nginx

systemctl enable jenkins
systemctl restart jenkins

echo ">> waiting for Jenkins to write its initial admin password"
for i in $(seq 1 60); do
  [ -f /var/lib/jenkins/secrets/initialAdminPassword ] && break
  sleep 5
done

echo
echo "=================================================================="
echo " Jenkins:  http://$(hostname -f):8080"
echo " Initial admin password: $(cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || echo 'not ready yet - run: sudo cat /var/lib/jenkins/secrets/initialAdminPassword')"
echo " Artifacts: http://$(hostname -f):8081/"
echo "=================================================================="
