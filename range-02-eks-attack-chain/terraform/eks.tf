# -------------------------------------------------------
# EKS CLUSTER (control plane)
# -------------------------------------------------------
resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids = aws_subnet.public[*].id

    endpoint_public_access = true
    # Locked to the operator's IP (see access.tf) instead of the 0.0.0.0/0
    # default, so only this machine can reach the Kubernetes API server.
    public_access_cidrs = local.allowed_source_cidrs

    # Enabled so worker nodes reach the control plane over the in-VPC private
    # path. Without this, restricting public_access_cidrs to the operator IP
    # would cut off the public-subnet nodes (they'd egress from a different IP)
    # and break the cluster. Not an attack-chain element - the exploit reaches
    # the API from inside the pod, not via this endpoint.
    endpoint_private_access = true
  }

  # -------------------------------------------------------
  # ATTACK CHAIN STEP - NO CONTROL PLANE AUDIT LOGGING
  #
  # range-01-eks-secure-baseline enables ["api", "audit", "authenticator", "controllerManager", "scheduler"] specifically
  # for forensic visibility. This is the closing beat of the attack
  # chain, deliberately left empty: even if every earlier step here
  # succeeds exactly as designed, there's no CloudWatch trail to
  # reconstruct how. Ties back to the OPSEC-monitoring theme from the
  # red-team side of this project - this is what it looks like from
  # the defender's side when that discipline is skipped.
  # -------------------------------------------------------
  enabled_cluster_log_types = []

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]

  tags = {
    Name = local.cluster_name
  }
}

data "aws_eks_cluster" "main" {
  name = aws_eks_cluster.main.name
}

data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
}

# -------------------------------------------------------
# NODE LAUNCH TEMPLATE
#
# ATTACK CHAIN STEP - IMDSv1 LEFT REACHABLE
#
# Without an explicit launch template, whether the unauthenticated IMDS
# request in solution/walkthrough.md Step 5
#   curl http://169.254.169.254/latest/meta-data/iam/security-credentials/
# succeeds depends on the account/region/AMI default for http_tokens - it
# is not pinned by the config. This template pins it: http_tokens =
# "optional" explicitly leaves IMDSv1 enabled, so the credential-theft step
# is actually built and deterministic rather than incidental.
#
# A hop limit of 1 is all the host-networked pod from Step 2 needs, because
# that pod shares the node's network namespace and reaches IMDS as the host.
# The one-line fix that closes this step is http_tokens = "required"
# (IMDSv2), which range-01-eks-secure-baseline's hardened posture implies.
#
# The AMI and bootstrap user-data are intentionally omitted so the EKS
# managed node group keeps injecting the EKS-optimized AMI and its own
# bootstrap script; this template only overrides the metadata options.
# -------------------------------------------------------
resource "aws_launch_template" "node" {
  name_prefix = "${local.cluster_name}-node-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.cluster_name}-node"
    }
  }
}

# -------------------------------------------------------
# MANAGED NODE GROUP
#
# ATTACK CHAIN: subnet_ids points at the PUBLIC subnets, not private,
# so worker nodes receive public IPs - the inverse of
# range-01-eks-secure-baseline's private-only node placement.
# -------------------------------------------------------
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.cluster_name}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.public[*].id

  instance_types = [var.node_instance_type]

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

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
    aws_iam_role_policy_attachment.node_ecr_policy,
    aws_iam_role_policy_attachment.node_admin
  ]

  tags = {
    Name = "${local.cluster_name}-node"
  }
}
