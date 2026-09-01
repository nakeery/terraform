# -------------------------------------------------------
# EKS CLUSTER (control plane)
# -------------------------------------------------------
resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = aws_subnet.public[*].id
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  # -------------------------------------------------------
  # ATTACK CHAIN STEP - NO CONTROL PLANE AUDIT LOGGING
  #
  # eks_phase_1 enables ["api", "audit", "authenticator"] specifically
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
# ATTACK CHAIN STEP - IMDSv1, NO HOP LIMIT (TODO - not yet wired up)
#
# This launch template is where the IMDS credential-theft step of the
# chain belongs (see iam.tf's AdministratorAccess comment for the
# full reasoning). It is NOT yet referenced by the node group below -
# that's the piece left for you to complete.
#
# What you need to research and add:
#   1. A `metadata_options` block on this launch template:
#        http_tokens               = "optional"  # allows IMDSv1 (no session token required)
#        http_put_response_hop_limit = 1          # or omit entirely for the more permissive default
#        http_endpoint              = "enabled"
#      (http_tokens = "required" would force IMDSv2 and close this
#      hole - that's the actual fix, useful to know for eks_phase_1
#      too, which doesn't set this explicitly either)
#   2. vpc_security_group_ids = [aws_security_group.node_vulnerable.id]
#      plus the cluster's own managed security group (see the TODO in
#      vpc.tf for how to look that up)
#   3. Reference this launch template from aws_eks_node_group.main
#      below via a `launch_template { id = ... version = ... }` block -
#      note that once you do this, instance_types/scaling config may
#      need to move onto the launch template instead of the node
#      group resource directly, depending on API version - read the
#      aws_eks_node_group docs carefully here, this is a common
#      source of "why won't this apply" errors.
# -------------------------------------------------------
resource "aws_launch_template" "node" {
  name_prefix = "${local.cluster_name}-node-"

  # metadata_options block goes here - see TODO above
}

# -------------------------------------------------------
# MANAGED NODE GROUP
#
# ATTACK CHAIN: subnet_ids points at the PUBLIC subnets, not private -
# compare directly against eks_phase_1's private-only placement.
# -------------------------------------------------------
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.cluster_name}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.public[*].id

  instance_types = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  # TODO: launch_template { id = aws_launch_template.node.id, version = "$Latest" }
  # once aws_launch_template.node above is finished - see its comment block.

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
