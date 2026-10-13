#!/bin/bash
# One-time setup of the EKS bastion host (Ubuntu 22.04 / 24.04).
# Installs: Jenkins, Java, git, AWS CLI v2, kubectl, Helm.
# Run as:  sudo bash scripts/setup-bastion.sh
set -euo pipefail

apt-get update
apt-get install -y openjdk-21-jre-headless git curl unzip ca-certificates gnupg

# Jenkins
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key -o /usr/share/keyrings/jenkins-keyring.asc
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" > /etc/apt/sources.list.d/jenkins.list
apt-get update
apt-get install -y jenkins
systemctl enable --now jenkins

# AWS CLI v2
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -qo /tmp/awscliv2.zip -d /tmp
/tmp/aws/install --update

# kubectl
KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl

# Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo
echo "Done. Open Jenkins at http://<bastion-ip>:8080"
echo "Initial admin password: $(cat /var/lib/jenkins/secrets/initialAdminPassword)"
