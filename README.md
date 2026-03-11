# Kubernetes Cluster on AWS (kubeadm) — Amazon Linux 2023
> Terraform setup: 1 Master + 1 Worker | Flannel CNI | ap-south-1

---

## Architecture

```
Your Machine
    │
    │  terraform apply
    ▼
AWS VPC (10.0.0.0/16)
└── Public Subnet (10.0.1.0/24)
    ├── Master EC2 (t3.medium)  ← kubeadm init, API Server :6443
    └── Worker EC2 (t3.medium)  ← kubeadm join
```

---

## Prerequisites

| Tool        | Version     | Install |
|-------------|-------------|---------|
| Terraform   | >= 1.5      | https://developer.hashicorp.com/terraform/install |
| AWS CLI     | >= 2.x      | `pip install awscli` |
| SSH key     | RSA/ED25519 | `ssh-keygen -t rsa -b 4096` |

### AWS credentials
```bash
aws configure
# Enter: Access Key, Secret Key, region (ap-south-1), output (json)
```

---

## Quick Start

```bash
# 1. Clone / copy this directory
cd k8s-kubeadm-terraform

# 2. Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars          # Set your IP, key path, etc.

# 3. Initialise Terraform
terraform init

# 4. Preview what will be created
terraform plan

# 5. Deploy (takes ~5 minutes)
terraform apply
```

---

## After `terraform apply`

Terraform will print outputs like:
```
master_public_ip  = "13.x.x.x"
worker_public_ip  = "13.x.x.y"
ssh_master        = "ssh -i ~/.ssh/id_rsa ec2-user@13.x.x.x"
```

### Step 1 — Wait for cloud-init to finish (~3–5 min)
```bash
# SSH into master and watch the log
ssh -i ~/.ssh/id_rsa ec2-user@<MASTER_IP>
sudo tail -f /var/log/k8s-master-init.log
# Wait until you see: ✅ Master node ready!
```

### Step 2 — Get the join command
```bash
# Still on master:
cat ~/worker-join-command.sh
# Example output:
# kubeadm join 10.0.1.x:6443 --token abc.xyz \
#   --discovery-token-ca-cert-hash sha256:...
```

### Step 3 — Join the worker
```bash
# Open a new terminal, SSH into worker
ssh -i ~/.ssh/id_rsa ec2-user@<WORKER_IP>
sudo tail -f /var/log/k8s-worker-init.log   # wait for ✅
sudo kubeadm join 10.0.1.x:6443 --token abc.xyz \
  --discovery-token-ca-cert-hash sha256:...
```

### Step 4 — Verify from master
```bash
# Back on master:
kubectl get nodes
# NAME     STATUS   ROLES           AGE   VERSION
# master   Ready    control-plane   5m    v1.29.x
# worker   Ready    <none>          1m    v1.29.x
```

### Step 5 — Copy kubeconfig to your local machine (optional)
```bash
# On your local machine:
scp -i ~/.ssh/id_rsa ec2-user@<MASTER_IP>:~/.kube/config ./kubeconfig
export KUBECONFIG=./kubeconfig
kubectl get nodes   # works from local!
```

---

## Ports Reference

| Port  | Protocol | Node   | Purpose                 |
|-------|----------|--------|-------------------------|
| 22    | TCP      | Both   | SSH access              |
| 6443  | TCP      | Master | Kubernetes API Server   |
| 2379–2380 | TCP  | Master | etcd                    |
| 10250 | TCP      | Both   | Kubelet API             |
| 10257 | TCP      | Master | kube-controller-manager |
| 10259 | TCP      | Master | kube-scheduler          |
| 8472  | UDP      | Both   | Flannel VXLAN           |
| 30000–32767 | TCP | Worker | NodePort services    |

---

## Test Your Cluster

```bash
# Deploy a test nginx pod
kubectl run nginx --image=nginx --port=80
kubectl expose pod nginx --type=NodePort --port=80

# Get the NodePort assigned
kubectl get svc nginx
# Access: http://<WORKER_IP>:<NodePort>
```

---

## Cleanup

```bash
terraform destroy
# Type 'yes' to confirm — this deletes all AWS resources
```

---

## Common Troubleshooting

| Problem | Fix |
|---------|-----|
| Node stuck in `NotReady` | Check Flannel: `kubectl get pods -n kube-flannel` |
| `kubectl` connection refused | Wait for master init to complete |
| Worker can't join | Token expired? Re-run: `kubeadm token create --print-join-command` on master |
| containerd errors | Check: `sudo systemctl status containerd` |
