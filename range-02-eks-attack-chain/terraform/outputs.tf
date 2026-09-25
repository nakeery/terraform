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

output "allowed_source_cidrs" {
  description = "CIDRs the API endpoint and dashboard load balancer are locked to (auto-detected operator IP unless overridden)"
  value       = local.allowed_source_cidrs
}

output "dashboard_url" {
  description = "URL of the vulnerable dashboard NLB - reachable only from allowed_source_cidrs"
  value       = "http://${kubernetes_service_v1.vulnerable_dashboard.status[0].load_balancer[0].ingress[0].hostname}"
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
