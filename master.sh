#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/k8s-master-init.log) 2>&1

echo "==> [1/7] System preparation"
hostnamectl set-hostname master
dnf update -y

# Disable swap (K8s requirement)
swapoff -a
sed -i '/swap/d' /etc/fstab

# Load required kernel modules
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# Sysctl settings for K8s networking
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

echo "==> [2/7] Installing containerd (CRI)"
dnf install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
# Use systemd cgroup driver (required for kubeadm)
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

echo "==> [3/7] Adding Kubernetes ${k8s_version} repo"
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${k8s_version}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${k8s_version}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

echo "==> [4/7] Installing kubeadm, kubelet, kubectl"
dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet

echo "==> [5/7] Initialising control plane with kubeadm"
MASTER_PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
MASTER_PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

kubeadm init \
  --pod-network-cidr="${pod_network_cidr}" \
  --apiserver-advertise-address="$MASTER_PRIVATE_IP" \
  --apiserver-cert-extra-sans="$MASTER_PUBLIC_IP" \
  --node-name="master" \
  --ignore-preflight-errors=NumCPU \
  2>&1 | tee /var/log/kubeadm-init.log

echo "==> [6/7] Configuring kubectl for ec2-user"
mkdir -p /home/ec2-user/.kube
cp /etc/kubernetes/admin.conf /home/ec2-user/.kube/config
chown ec2-user:ec2-user /home/ec2-user/.kube/config

# Also set up for root
export KUBECONFIG=/etc/kubernetes/admin.conf

echo "==> [7/7] Installing Flannel CNI"
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# ── Save the join command so you can use it on the worker ──────────────────
JOIN_CMD=$(kubeadm token create --print-join-command)
echo "$JOIN_CMD" > /home/ec2-user/worker-join-command.sh
chmod +x /home/ec2-user/worker-join-command.sh
chown ec2-user:ec2-user /home/ec2-user/worker-join-command.sh

echo ""
echo "============================================================"
echo "  ✅  Master node ready!"
echo "  JOIN COMMAND saved at: ~/worker-join-command.sh"
echo "  Run: cat ~/worker-join-command.sh"
echo "============================================================"
