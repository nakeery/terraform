# -------------------------------------------------------
# EKS CLUSTER (control plane)
#
# The control plane runs in subnets you specify, but AWS
# manages the actual control plane infrastructure (API
# server, etcd, etc.) - you don't see or manage those servers.
#
# We reference BOTH public and private subnets here so the
# control plane's elastic network interfaces can reach nodes
# in either. The nodes themselves (below) only launch in
# private subnets.
# -------------------------------------------------------
resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)

    # For a learning project, public access is fine so you can
    # run kubectl from your laptop. In a real hardened deployment
    # you'd set endpoint_public_access = false and connect via
    # VPN/bastion instead - worth doing as a follow-up exercise
    # once Phase 1 works, given this role's security focus.
    endpoint_public_access = true
    endpoint_private_access = true
  }

  # Enables control plane logging to CloudWatch - useful for
  # security monitoring (who called the API server, when) and
  # directly relevant to the "infrastructure hardening" and
  # audit requirements you'd document in an ATO package.
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]

  tags = {
    Name = local.cluster_name
  }
}

# Data source to read back cluster info (used by the
# kubernetes provider config in main.tf)
data "aws_eks_cluster" "main" {
  name = aws_eks_cluster.main.name
}

data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
}

# -------------------------------------------------------
# MANAGED NODE GROUP
# Worker nodes that actually run your pods. "Managed" means
# AWS handles the underlying EC2 lifecycle (patching AMIs,
# rolling updates) rather than you managing raw EC2 instances.
#
# Nodes launch in PRIVATE subnets only - no direct internet
# route in. This is the security-conscious default worth
# highlighting in your portfolio write-up.
# -------------------------------------------------------
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.cluster_name}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.private[*].id

  instance_types = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy
  ]

  tags = {
    Name = "${local.cluster_name}-node"
  }
}
