# -------------------------------------------------------
# EKS CLUSTER ROLE
# Allows the EKS control plane to manage AWS resources
# on your behalf (ENIs, load balancers, etc.)
# -------------------------------------------------------
resource "aws_iam_role" "cluster" {
  name = "${local.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "eks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# -------------------------------------------------------
# EKS NODE ROLE
# Allows EC2 worker nodes to join the cluster, pull images
# from ECR, and let kubelet report node status.
#
# IMPORTANT: this role's permissions are inherited by every
# pod on the node UNLESS that pod uses IRSA (below) to assume
# a more scoped-down role instead. Keep this role minimal.
# -------------------------------------------------------
resource "aws_iam_role" "node" {
  name = "${local.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# -------------------------------------------------------
# IRSA (IAM Roles for Service Accounts) - OIDC PROVIDER
#
# This is the security-critical piece. Without this, if a
# pod gets compromised, an attacker inherits the NODE's full
# IAM role - which might have far more access than that one
# pod actually needs.
#
# With IRSA, individual Kubernetes service accounts can be
# mapped to specific, scoped-down IAM roles. A compromised
# pod only gets the permissions of ITS service account role,
# not the whole node.
#
# This block sets up the trust relationship (OIDC provider)
# that makes IRSA possible. We're not creating any specific
# scoped-down roles yet in Phase 1 - that comes when we
# actually deploy something that needs AWS API access
# (e.g. an app that reads from S3). For now, nginx doesn't
# need AWS permissions, so this is foundational plumbing.
# -------------------------------------------------------
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
