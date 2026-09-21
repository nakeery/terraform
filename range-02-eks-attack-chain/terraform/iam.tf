# -------------------------------------------------------
# EKS CLUSTER ROLE
# Same as range-01-eks-secure-baseline - the control plane's own permissions aren't
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
# range-01-eks-secure-baseline's node role attaches exactly three scoped managed
# policies (worker node, CNI, ECR read-only) - the minimum needed for
# a node to function, and its own comments warn that pod compromise
# inherits this role's permissions. This is that warning, made real:
# AdministratorAccess attached to the node role instead.
#
# Reached through the node's IMDS from the privileged, host-networked
# pod (k8s/vulnerable-dashboard.yaml), this is the same shape as the
# 2019 Capital One breach: code execution on a compute resource ->
# steal its instance role credentials via IMDS -> those credentials
# turn out to be far broader than the workload needed.
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
# range-01-eks-secure-baseline's iam.tf sets up an OIDC provider specifically so pods
# COULD assume narrowly-scoped roles instead of inheriting the node's
# role. This project skips that entirely, on purpose - it's the
# absence of IRSA (not a misconfigured version of it) that's the
# point: with no per-pod scoping mechanism at all, EVERY pod on the
# node gets the node role's permissions by default, no exceptions.
# -------------------------------------------------------
