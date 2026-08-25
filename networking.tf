resource "aws_vpc" "this" {
  count = local.create_vpc ? 1 : 0

  cidr_block           = var.vpn_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name  = var.vpc_name
    Owner = var.owner
  }

  lifecycle {
    precondition {
      condition     = var.vpc_name != null && trimspace(var.vpc_name) != ""
      error_message = "vpc_name must be provided when creating a new VPC."
    }
    precondition {
      condition     = var.vpn_cidr != null && trimspace(var.vpn_cidr) != ""
      error_message = "vpn_cidr must be provided when creating a new VPC."
    }
    precondition {
      condition     = var.public_subnets != null && length(var.public_subnets) > 0
      error_message = "public_subnets must be provided when creating a new VPC."
    }
    precondition {
      condition     = length(var.availability_zones) == length(var.private_subnets) && length(var.availability_zones) == length(var.public_subnets)
      error_message = "availability_zones, private_subnets, and public_subnets must have matching lengths when creating a new VPC."
    }
  }
}

resource "aws_subnet" "private" {
  for_each = local.az_to_cidr

  vpc_id                  = aws_vpc.this[0].id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = {
    Name  = format("%s-private-%s", var.vpc_name, each.key)
    Owner = var.owner
  }
}

resource "aws_subnet" "public" {
  for_each = local.az_to_public_cidr

  vpc_id                  = aws_vpc.this[0].id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = {
    Name  = format("%s-public-%s", var.vpc_name, each.key)
    Owner = var.owner
  }
}

resource "aws_internet_gateway" "this" {
  count = local.create_vpc ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  tags = {
    Name  = format("%s-igw", var.vpc_name)
    Owner = var.owner
  }
}

resource "aws_route_table" "public" {
  count = local.create_vpc ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }

  tags = {
    Name  = format("%s-public-rt", var.vpc_name)
    Owner = var.owner
  }
}

resource "aws_route_table_association" "public" {
  for_each = local.az_to_public_cidr

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_eip" "nat" {
  count = local.create_vpc ? 1 : 0

  domain = "vpc"

  tags = {
    Name  = format("%s-nat-eip", var.vpc_name)
    Owner = var.owner
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.create_vpc ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = [for subnet in values(aws_subnet.public) : subnet.id][0]

  tags = {
    Name  = format("%s-nat", var.vpc_name)
    Owner = var.owner
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  count = local.create_vpc ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[0].id
  }

  tags = {
    Name  = format("%s-private-rt", var.vpc_name)
    Owner = var.owner
  }
}

resource "aws_route_table_association" "private" {
  for_each = local.az_to_cidr

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[0].id
}
