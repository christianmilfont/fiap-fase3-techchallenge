resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnets"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, { Name = "${var.name}-db-subnets" })
}

resource "aws_security_group" "this" {
  name        = "${var.name}-rds-sg"
  description = "Acesso PostgreSQL as instancias RDS"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL"
    from_port       = var.port
    to_port         = var.port
    protocol        = "tcp"
    cidr_blocks     = var.allowed_cidr_blocks
    security_groups = var.allowed_security_group_ids
  }

  egress {
    description = "Saida liberada"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-rds-sg" })
}

resource "random_password" "this" {
  for_each = var.databases

  length           = 20
  special          = true
  override_special = "!#$%*()-_=+[]{}<>:?"
}

resource "aws_db_instance" "this" {
  for_each = var.databases

  identifier     = "${var.name}-${each.key}"
  engine         = "postgres"
  engine_version = coalesce(each.value.engine_version, var.engine_version)
  instance_class = coalesce(each.value.instance_class, var.instance_class)

  allocated_storage     = coalesce(each.value.allocated_storage, var.allocated_storage)
  max_allocated_storage = coalesce(each.value.max_allocated_storage, var.max_allocated_storage)
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = each.value.db_name
  username = coalesce(each.value.username, var.master_username)
  password = random_password.this[each.key].result
  port     = var.port

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  multi_az               = coalesce(each.value.multi_az, var.multi_az)
  publicly_accessible    = false

  backup_retention_period = var.backup_retention_period
  deletion_protection     = var.deletion_protection
  skip_final_snapshot     = var.skip_final_snapshot
  apply_immediately       = true

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })
}
