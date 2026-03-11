#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/k8s-worker-init.log) 2>&1

echo "==> [1/5] System preparation"
hostnamectl set-hostname worker
dnf update -y

# Disable swap
swapoff -a
sed -i '/swap/d' /etc/fstab

# Kernel modules
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# Sysctl
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

echo "==> [2/5] Installing containerd"
dnf install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

echo "==> [3/5] Adding Kubernetes ${k8s_version} repo"
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${k8s_version}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${k8s_version}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

echo "==> [4/5] Installing kubeadm, kubelet, kubectl"
dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet

echo ""
echo "============================================================"
echo "  ✅  Worker node packages ready!"
echo ""
echo "  ⚠️  MANUAL STEP REQUIRED:"
echo "  1. SSH into the master node"
echo "  2. Run: cat ~/worker-join-command.sh"
echo "  3. Copy the kubeadm join command"
echo "  4. SSH into this worker and run it as root:"
echo "     sudo <paste-join-command>"
echo "============================================================"

echo "==> [5/5] Worker setup complete — waiting for manual join"
