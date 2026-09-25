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
  description = "CIDRs the API endpoint and nginx NLB are locked to (auto-detected operator IP unless overridden)"
  value       = local.allowed_source_cidrs
}

output "service_url" {
  description = "URL of the nginx NLB - reachable only from allowed_source_cidrs"
  value       = "http://${kubernetes_service_v1.nginx.status[0].load_balancer[0].ingress[0].hostname}"
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (where worker nodes live)"
  value       = aws_subnet.private[*].id
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN - needed later for IRSA role trust policies"
  value       = aws_iam_openid_connect_provider.eks.arn
}
