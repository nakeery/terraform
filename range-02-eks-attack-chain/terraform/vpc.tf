# -------------------------------------------------------
# VPC
# -------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name                                          = "${local.cluster_name}-vpc"
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
# range-01-eks-secure-baseline deliberately kept worker nodes in private subnets,
# reachable only outbound via a NAT Gateway. Here there's only ONE
# subnet tier - public - and the node group (in eks.tf) launches
# directly into it. No NAT Gateway needed at all, which also means a
# worker node's ENI sits on a public subnet with a public IP, exposed
# at the edge of whatever the node's security group allows rather than
# tucked behind a private tier.
#
# Contrast with range-01-eks-secure-baseline/terraform/vpc.tf's
# public/private subnet split.
# -------------------------------------------------------
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                          = "${local.cluster_name}-public-${count.index}"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
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
