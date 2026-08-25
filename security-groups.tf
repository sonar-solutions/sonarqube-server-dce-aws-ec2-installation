resource "aws_security_group" "app" {
  name        = substr("${local.sanitized_hostname}-app-sg", 0, 128)
  description = "SonarQube application node access"
  vpc_id      = local.vpc_id_effective

  ingress {
    description = "SonarQube web from load balancer"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = local.is_windows && var.enable_rdp ? [1] : []
    content {
      description = "RDP access"
      from_port   = 3389
      to_port     = 3389
      protocol    = "tcp"
      cidr_blocks = [var.rdp_allowed_cidr]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "${local.sanitized_hostname}-app"
    Owner = var.owner
  }
}

resource "aws_security_group" "search" {
  name        = substr("${local.sanitized_hostname}-search-sg", 0, 128)
  description = "SonarQube DCE search node access"
  vpc_id      = local.vpc_id_effective

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "${local.sanitized_hostname}-search"
    Owner = var.owner
  }
}

resource "aws_security_group" "db" {
  name        = substr("${local.rds_identifier}-db-sg", 0, 128)
  description = "Allow PostgreSQL from SonarQube application nodes"
  vpc_id      = local.vpc_id_effective

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "${local.rds_identifier}-db"
    Owner = var.owner
  }
}

resource "aws_security_group_rule" "db_from_app" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.app.id
  description              = "PostgreSQL from SonarQube application nodes"
}

resource "aws_security_group_rule" "app_to_app_cluster" {
  type                     = "ingress"
  from_port                = var.app_cluster_port
  to_port                  = var.app_cluster_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.app.id
  source_security_group_id = aws_security_group.app.id
  description              = "DCE app-to-app cluster traffic"
}

resource "aws_security_group_rule" "app_to_app_web" {
  type                     = "ingress"
  from_port                = var.app_web_cluster_port
  to_port                  = var.app_web_cluster_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.app.id
  source_security_group_id = aws_security_group.app.id
  description              = "DCE app web process cluster traffic"
}

resource "aws_security_group_rule" "app_to_app_ce" {
  type                     = "ingress"
  from_port                = var.app_ce_cluster_port
  to_port                  = var.app_ce_cluster_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.app.id
  source_security_group_id = aws_security_group.app.id
  description              = "DCE app compute engine cluster traffic"
}

resource "aws_security_group_rule" "search_from_app" {
  type                     = "ingress"
  from_port                = var.search_port
  to_port                  = var.search_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.search.id
  source_security_group_id = aws_security_group.app.id
  description              = "DCE application nodes to search service"
}

resource "aws_security_group_rule" "search_es_from_app" {
  type                     = "ingress"
  from_port                = var.es_port
  to_port                  = var.es_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.search.id
  source_security_group_id = aws_security_group.app.id
  description              = "DCE application nodes to Elasticsearch HTTP service"
}

resource "aws_security_group_rule" "search_to_search_es" {
  type                     = "ingress"
  from_port                = var.es_port
  to_port                  = var.es_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.search.id
  source_security_group_id = aws_security_group.search.id
  description              = "DCE search-to-search Elasticsearch transport"
}
