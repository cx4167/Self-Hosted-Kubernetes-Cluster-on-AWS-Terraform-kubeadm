output "master_public_ip" {
  description = "Public IP of the master node"
  value       = aws_instance.master.public_ip
}

output "master_private_ip" {
  description = "Private IP of the master node"
  value       = aws_instance.master.private_ip
}

output "worker_public_ip" {
  description = "Public IP of the worker node"
  value       = aws_instance.worker.public_ip
}

output "worker_private_ip" {
  description = "Private IP of the worker node"
  value       = aws_instance.worker.private_ip
}

output "ssh_master" {
  description = "SSH command for master node"
  value       = "ssh -i ~/.ssh/id_rsa ec2-user@${aws_instance.master.public_ip}"
}

output "ssh_worker" {
  description = "SSH command for worker node"
  value       = "ssh -i ~/.ssh/id_rsa ec2-user@${aws_instance.worker.public_ip}"
}

output "kubeconfig_command" {
  description = "Command to copy kubeconfig from master to your local machine"
  value       = "scp -i ~/.ssh/id_rsa ec2-user@${aws_instance.master.public_ip}:~/.kube/config ./kubeconfig && export KUBECONFIG=./kubeconfig"
}
