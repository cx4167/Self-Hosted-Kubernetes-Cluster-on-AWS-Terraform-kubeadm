#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/k8s-worker-init.log) 2>&1

echo "==> [1/4] System preparation"
hostnamectl set-hostname worker
dnf update -y

swapoff -a
sed -i '/swap/d' /etc/fstab

cat <<MODULES > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
MODULES
modprobe overlay
modprobe br_netfilter

cat <<SYSCTL > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
SYSCTL
sysctl --system

echo "==> [2/4] Installing containerd"
dnf install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

echo "==> [3/4] Adding Kubernetes ${k8s_version} repo"
cat <<REPO > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${k8s_version}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${k8s_version}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
REPO

echo "==> [4/4] Installing kubeadm kubelet kubectl"
dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet

echo "============================================================"
echo "  Worker node ready!"
echo "  Now run the kubeadm join command from the master"
echo "============================================================"
