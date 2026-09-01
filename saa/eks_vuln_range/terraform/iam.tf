# -------------------------------------------------------
# EKS CLUSTER ROLE
# Same as eks_phase_1 - the control plane's own permissions aren't
# part of the attack chain here, so this is left correctly scoped.
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
# ATTACK CHAIN STEP - OVER-PRIVILEGED NODE ROLE
#
# eks_phase_1's node role attaches exactly three scoped managed
# policies (worker node, CNI, ECR read-only) - the minimum needed for
# a node to function, and its own comments warn that pod compromise
# inherits this role's permissions. This is that warning, made real:
# AdministratorAccess attached to the node role instead.
#
# Chained with the public kubelet API (vpc.tf) and IMDSv1 with no hop
# limit (eks.tf's launch template - TODO there), this is the same
# shape as the 2019 Capital One breach: SSRF/exec access on a compute
# resource -> steal its instance role credentials via IMDS -> those
# credentials turn out to be far broader than the workload needed.
#
# TODO (yours to complete, optional stretch goal): try scoping this
# down to something "plausibly over-permissioned" instead of literal
# AdministratorAccess - e.g. a custom policy with s3:*, iam:*, or
# ec2:* wildcards. AdministratorAccess is the clearest teaching
# example but a real-world overprivileged role rarely looks this
# obviously bad - a narrower-but-still-wildcarded policy is closer to
# what you'd actually find in an audit.
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

resource "aws_iam_role_policy_attachment" "node_admin" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Still needed regardless of the vuln - without these, nodes can't
# join the cluster or pull images at all, and the range wouldn't come
# up. The vulnerability is ADDING AdministratorAccess on top, not
# removing these.
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
# NO IRSA / OIDC PROVIDER HERE - DELIBERATELY OMITTED
#
# eks_phase_1's iam.tf sets up an OIDC provider specifically so pods
# COULD assume narrowly-scoped roles instead of inheriting the node's
# role. This project skips that entirely, on purpose - it's the
# absence of IRSA (not a misconfigured version of it) that's the
# point: with no per-pod scoping mechanism at all, EVERY pod on the
# node gets the node role's permissions by default, no exceptions.
# -------------------------------------------------------
