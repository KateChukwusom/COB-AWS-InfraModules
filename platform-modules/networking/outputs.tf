# ------------------------------------------------------------------
# These outputs are the module's real public interface — every other
# COB primitive (compute, rds, secure-data-bucket) will consume
# these rather than reaching into this module's internals. Keep the
# names stable once other modules start depending on them.
# ------------------------------------------------------------------
output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr_block" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  value = [for s in aws_subnet.private : s.id]
}

output "availability_zones" {
  value = local.azs
}