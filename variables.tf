variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"  # Mumbai – closest to Bengaluru
}

variable "cluster_name" {
  description = "Prefix used for all resource names"
  type        = string
  default     = "k8s-kubeadm"
}

variable "master_instance_type" {
  description = "EC2 instance type for the master node (min: t3.medium for kubeadm)"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "EC2 instance type for the worker node"
  type        = string
  default     = "t3.medium"
}

variable "public_key_path" {
  description = "Path to your local SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into nodes (use your IP: x.x.x.x/32)"
  type        = string
  default     = "0.0.0.0/0"   # ⚠️  Restrict this to your IP in production
}

variable "pod_network_cidr" {
  description = "Pod network CIDR (must match Flannel default)"
  type        = string
  default     = "10.244.0.0/16"
}

variable "k8s_version" {
  description = "Kubernetes version to install (e.g. 1.29)"
  type        = string
  default     = "1.29"
}

variable "ami_id" {
  description = "AMI ID to use for both master and worker nodes"
  type        = string
}
