/* This data source block reads for available AZs in the consumer's region at apply time*/
data "aws_availability_zones" "available" {
  state = "available"
}

/* */
locals {
  vpc_name = "COB-${var.team}-${var.environment}-vpc"

  tags = {
    Team        = var.team
    Environment = var.environment
    ManagedBy   = "COB"
  }

  
  # Hardcoded on purpose: callers never supply CIDR notation. Every
  # VPC this module creates uses the same /16 today.
 
  base_cidr = "10.0.0.0/16"

  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  
  /*the slicing logic then decides how the address gets divided up and labeled, consistently,
   every time, without ever asking the caller to think about addresses at all */
  public_subnet_cidrs  = [for i in range(var.az_count) : cidrsubnet(local.base_cidr, 4, i)]
  private_subnet_cidrs = [for i in range(var.az_count) : cidrsubnet(local.base_cidr, 4, i + var.az_count)]
}

resource "aws_vpc" "cob_vpc" {
  cidr_block           = local.base_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = local.vpc_name })
}

/* */
resource "aws_internet_gateway" "cob_igw" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${local.vpc_name}-igw" })
}


/* each.key = the AZ name  used to place the subnet in the right AZ.
 each.value =  used below to pick the matching CIDR block, so this subnet gets the CIDR that was
  calculated specifically for it, not a random one. */
resource "aws_subnet" "public" {
  for_each = { for idx, az in local.azs : az => idx }

  vpc_id                  = aws_vpc.cob_vpc.id
  availability_zone       = each.key
  cidr_block              = local.public_subnet_cidrs[each.value]
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name = "${local.vpc_name}-public-${each.key}"
    Tier = "public"
  })
}

/* */
resource "aws_subnet" "private" {
  for_each = { for idx, az in local.azs : az => idx }

  vpc_id            = aws_vpc.cob_vpc.id
  availability_zone = each.key
  cidr_block        = local.private_subnet_cidrs[each.value]

  tags = merge(local.tags, {
    Name = "${local.vpc_name}-private-${each.key}"
    Tier = "private"
  })
}


/*This creates an elastic Ip only if the consumer asks for a NAT */
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = merge(local.tags, { Name = "${local.vpc_name}-nat-eip" })
}

/* */
resource "aws_nat_gateway" "cob_ngw" {
  count = var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id

#One nat gatway per AZ is a limitation to be worked on
  subnet_id = values(aws_subnet.public)[0].id

  tags = merge(local.tags, { Name = "${local.vpc_name}-nat" })

  depends_on = [aws_internet_gateway.cob_igw]
}

/* */
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.cob_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cob_igw.id
  }

  tags = merge(local.tags, { Name = "${local.vpc_name}-public-rt" })
}

/* */
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.cob_vpc.id


  /* dynamic block: only generate a default route if NAT is actually
  enabled.*/
  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.cob_ngw.id
    }
  }

  tags = merge(local.tags, { Name = "${local.vpc_name}-private-rt" })
}

/* */
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

/* */
resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}