locals {
  name = "cob-${var.team}-${var.environment}-${var.purpose}"

  tags = merge(var.tags, {
    Team        = var.team
    Environment = var.environment
    ManagedBy   = "COB"
  })

  deletion_protection = var.environment == "prod"
  skip_final_snapshot  = var.environment != "prod"
}

# ------------------------------------------------------------------
# random_password and the manual aws_secretsmanager_secret /
# aws_secretsmanager_secret_version resources have been removed
# entirely. AWS's native manage_master_user_password feature (used
# on aws_db_instance below) replaces all three - RDS generates the
# password, stores it in Secrets Manager, and owns its entire
# lifecycle internally, including rotation, which the manual
# approach had no mechanism for at all.
# ------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = local.tags
}

resource "aws_security_group" "this" {
  name        = "${local.name}-sg"
  description = "Security group for ${local.name}"
  vpc_id      = var.vpc_id

  # Port fixed at 5432 - PostgreSQL's standard port. No engine
  # branching needed; this module provisions PostgreSQL only.
  dynamic "ingress" {
    for_each = var.allowed_security_group_id
    content {
      description     = "PostgreSQL access from ${ingress.value}"
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name}-sg" })
}

resource "aws_db_instance" "this" {
  identifier = local.name

  # Hardcoded - this module provisions PostgreSQL only.
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_encrypted = true

  # Only the empty database itself is created here. No schema,
  # tables, or roles are created by this module - see README's
  # "Known limitations" for the reasoning and the planned path for
  # schema management.
  db_name  = var.database_name
  username = var.master_username

  # AWS generates and owns the master password entirely. No
  # password argument exists on this resource - there is nothing
  # for a caller to supply, see, or accidentally hardcode.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]

  publicly_accessible = false

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_period

  deletion_protection       = local.deletion_protection
  skip_final_snapshot       = local.skip_final_snapshot
  final_snapshot_identifier = local.skip_final_snapshot ? null : "${local.name}-final-snapshot"

  tags = merge(local.tags, { Name = local.name })
}