output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "configure_kubectl" {
  description = "Run this command to configure kubectl to talk to your cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.main.name}"
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (worker nodes live here in this project - see vpc.tf comments)"
  value       = aws_subnet.public[*].id
}

output "warning" {
  description = "Read this before you forget you built this"
  value       = "This cluster is intentionally vulnerable. Do not leave it running. Do not reuse any part of it for a real workload. Destroy it the same session you stood it up."
}
