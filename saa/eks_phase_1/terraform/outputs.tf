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

output "private_subnet_ids" {
  description = "Private subnet IDs (where worker nodes live)"
  value       = aws_subnet.private[*].id
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN - needed later for IRSA role trust policies"
  value       = aws_iam_openid_connect_provider.eks.arn
}
