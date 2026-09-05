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

  # Carves the /16 into /20s. Public subnets take netnum 0..N,
  # private subnets take netnum 100..100+N — the offset keeps the
  # two ranges visually and numerically separated so a human
  # scanning raw CIDRs can tell public from private at a glance.
  /* */
  public_subnet_cidrs  = [for i in range(var.az_count) : cidrsubnet(local.base_cidr, 4, i)]
  private_subnet_cidrs = [for i in range(var.az_count) : cidrsubnet(local.base_cidr, 4, i + 100)]
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


# for_each keyed by AZ name, if az_count ever changes, or AZ
# ordering shifts, each subnet stays tied to its actual AZ identity
# instead of a positional index that could get reassigned.
/* */
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

# count, not for_each, is correct here: this is an on/off switch
# (0 or 1), not a loop over a collection of distinct items.
/* */
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = merge(local.tags, { Name = "${local.vpc_name}-nat-eip" })
}

/* */
resource "aws_nat_gateway" "cob_ngw" {
  count = var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id

  # A single NAT gateway in the first public subnet is sufficient for
  # most workloads and keeps cost down. One NAT per AZ is a valid
  # upgrade later if private-subnet resilience against an AZ outage
  # becomes a real requirement — deliberately not built in yet.
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

  # dynamic block: only generate a default route if NAT is actually
  # enabled. Without this guard, the route table would either fail
  # to create (no NAT gateway ID to reference) or need an awkward
  # placeholder value when NAT is off.
  /* */
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