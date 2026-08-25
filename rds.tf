resource "aws_db_subnet_group" "this" {
  name       = "${local.rds_identifier}-subnets"
  subnet_ids = local.private_subnet_ids

  tags = {
    Name  = "${local.rds_identifier}-subnets"
    Owner = var.owner
  }
}

resource "aws_db_instance" "postgres" {
  identifier              = local.rds_identifier
  db_name                 = local.rds_database_name
  engine                  = "postgres"
  engine_version          = var.rds_engine_version
  instance_class          = var.rds_instance_type
  allocated_storage       = var.rds_allocated_storage
  storage_type            = var.rds_storage_type
  iops                    = var.rds_iops
  storage_encrypted       = true
  multi_az                = var.rds_multi_az
  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  username                = var.db_username
  password                = random_password.db_admin.result
  publicly_accessible     = false
  backup_retention_period = var.rds_backup_retention_period
  deletion_protection     = false
  skip_final_snapshot     = true
  apply_immediately       = true

  tags = {
    Name  = local.rds_identifier
    Owner = var.owner
  }
}
