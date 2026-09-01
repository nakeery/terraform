# -------------------------------------------------------
# VPC
# -------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.cluster_name}-vpc"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.cluster_name}-igw"
  }
}

# -------------------------------------------------------
# ATTACK CHAIN STEP - WORKER NODES IN PUBLIC SUBNETS
#
# eks_phase_1 deliberately kept worker nodes in private subnets,
# reachable only outbound via a NAT Gateway. Here there's only ONE
# subnet tier - public - and the node group (in eks.tf) launches
# directly into it. No NAT Gateway needed at all, which also means
# nothing stands between a worker node's ENI and the internet except
# whatever the security group allows (see the security group below -
# that's step 2 of the chain, not this file).
#
# Compare directly against saa/eks_phase_1/terraform/vpc.tf's public/
# private split before building this out further.
# -------------------------------------------------------
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.cluster_name}-public-${count.index}"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                       = "1"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.cluster_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -------------------------------------------------------
# ATTACK CHAIN STEP - OVERLY PERMISSIVE NODE SECURITY GROUP
#
# EKS managed node groups normally get a reasonably locked-down
# default security group. This one deliberately widens it: kubelet's
# API port (10250) and SSH (22) both open to 0.0.0.0/0. Combined with
# the public-subnet placement above, this is what actually makes the
# node's kubelet API reachable from the open internet - a real,
# documented attack surface (unauthenticated/anonymous-auth kubelet
# API access has been used in real cluster compromises to run
# arbitrary commands via the exec/run endpoints).
#
# TODO (yours to complete): this security group needs to actually be
# attached to the node group's ENIs. A managed node group's default
# networking doesn't take security_group_ids directly - you attach
# custom security groups via a launch template (aws_launch_template's
# vpc_security_group_ids), then reference that launch template from
# aws_eks_node_group.main via a launch_template block. Research:
#   - aws_launch_template resource
#   - aws_eks_node_group's `launch_template` block
#   - you'll also want to keep (not replace) the cluster's own managed
#     security group so node<->control-plane communication still works -
#     look at data.aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
# -------------------------------------------------------
resource "aws_security_group" "node_vulnerable" {
  name_prefix = "${local.cluster_name}-node-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Kubelet API - open to the internet (do not do this)"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH - open to the internet (do not do this)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.cluster_name}-node-sg-VULNERABLE"
  }
}
