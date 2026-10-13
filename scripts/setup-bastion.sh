#!/bin/bash
# One-time setup of the EKS bastion host (Amazon Linux 2023, also works on Amazon Linux 2).
# Installs: Jenkins, Java 21, git, AWS CLI v2, kubectl, Helm.
# Run as:  sudo bash scripts/setup-bastion.sh
set -euo pipefail

# Re-run as root if started as a normal user (e.g. ec2-user)
if [ "$(id -u)" -ne 0 ]; then
    exec sudo bash "$0" "$@"
fi

# dnf on Amazon Linux 2023, yum on Amazon Linux 2
PKG=$(command -v dnf || command -v yum)

# x86_64 or ARM (Graviton)
ARCH=$(uname -m)                                  # x86_64 | aarch64
[ "$ARCH" = "aarch64" ] && K8S_ARCH=arm64 || K8S_ARCH=amd64

$PKG install -y java-21-amazon-corretto-headless git unzip tar

# Jenkins
curl -fsSL https://pkg.jenkins.io/redhat-stable/jenkins.repo -o /etc/yum.repos.d/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
$PKG install -y jenkins
systemctl daemon-reload
systemctl enable --now jenkins

# AWS CLI v2 (Amazon Linux 2023 already has it; Amazon Linux 2 ships v1)
if ! aws --version 2>/dev/null | grep -q "aws-cli/2"; then
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o /tmp/awscliv2.zip
    unzip -qo /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install --update
fi

# kubectl
KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${K8S_ARCH}/kubectl" -o /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl

# Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Jenkins runs pipelines with a minimal PATH; make the tools visible to it
ln -sf /usr/local/bin/kubectl /usr/bin/kubectl
ln -sf /usr/local/bin/helm    /usr/bin/helm
[ -x /usr/local/bin/aws ] && ln -sf /usr/local/bin/aws /usr/bin/aws

echo
echo "Done. Open Jenkins at http://<bastion-ip>:8080"
echo "Initial admin password: $(cat /var/lib/jenkins/secrets/initialAdminPassword)"
