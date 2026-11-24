locals {
  agentic_app_setup = var.deploy_agentic_containers ? templatefile(
    "${path.module}/templates/${local.is_windows ? "windows_agentic.ps1" : "linux_agentic_app.sh"}.tftpl", {
      bucket     = aws_s3_bucket.agentic["bootstrap"].id
      jobs       = aws_s3_bucket.agentic["jobs"].id
      region     = var.aws_region
      host       = aws_route53_record.agents[0].fqdn
      access_key = aws_iam_access_key.agentic_storage[0].id
      secret_key = aws_iam_access_key.agentic_storage[0].secret
  }) : ""
  agentic_fqdn  = "agentic.${local.domain_fqdn}"
  agentic_roles = var.deploy_agentic_containers ? toset(["app", "agents"]) : toset([])
}

data "aws_ami" "agents" {
  count       = var.deploy_agentic_containers ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = local.ami_lookup["amazon-linux-2023"].filters.name
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_s3_bucket" "agentic" {
  for_each      = var.deploy_agentic_containers ? toset(["bootstrap", "jobs"]) : toset([])
  bucket_prefix = "${substr(local.sanitized_hostname, 0, 20)}-${each.key}-"
  force_destroy = false
  tags = {
    Owner = var.owner
    Role  = "sonarqube-agentic-${each.key}"
  }
}

resource "aws_s3_bucket_public_access_block" "agentic" {
  for_each                = aws_s3_bucket.agentic
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "agentic" {
  for_each = aws_s3_bucket.agentic
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "agentic" {
  for_each = aws_s3_bucket.agentic
  bucket   = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [each.value.arn, "${each.value.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

resource "aws_iam_user" "agentic_storage" {
  count = var.deploy_agentic_containers ? 1 : 0
  name  = "${substr(local.sanitized_hostname, 0, 48)}-agentic-storage"
  tags  = { Owner = var.owner }
}

resource "aws_iam_access_key" "agentic_storage" {
  count = var.deploy_agentic_containers ? 1 : 0
  user  = aws_iam_user.agentic_storage[0].name
}

resource "aws_iam_user_policy" "agentic_storage" {
  count = var.deploy_agentic_containers ? 1 : 0
  user  = aws_iam_user.agentic_storage[0].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:ListBucket", "s3:GetBucketLocation"], Resource = aws_s3_bucket.agentic["jobs"].arn },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = "${aws_s3_bucket.agentic["jobs"].arn}/*" }
    ]
  })
}

resource "aws_iam_role" "agentic" {
  for_each    = local.agentic_roles
  name_prefix = "${substr(local.sanitized_hostname, 0, 20)}-${each.key}-"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = { Owner = var.owner }
}

resource "aws_iam_instance_profile" "agentic" {
  for_each = local.agentic_roles
  role     = aws_iam_role.agentic[each.key].name
}

resource "aws_iam_role_policy" "agentic" {
  for_each = local.agentic_roles
  role     = aws_iam_role.agentic[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = each.key == "app" ? [
          "${aws_s3_bucket.agentic["bootstrap"].arn}/app-config.json"
        ] : ["${aws_s3_bucket.agentic["bootstrap"].arn}/identity.json"]
      }
      ], each.key == "agents" ? [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.agentic["bootstrap"].arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${aws_s3_bucket.agentic["bootstrap"].arn}/identity.json", "${aws_s3_bucket.agentic["bootstrap"].arn}/app-config.json"]
      }
    ] : [])
  })
}

resource "aws_security_group" "agents" {
  count       = var.deploy_agentic_containers ? 1 : 0
  name_prefix = "${local.sanitized_hostname}-agents-"
  description = "Private agent TLS endpoints from DCE application nodes"
  vpc_id      = local.vpc_id_effective
  ingress {
    from_port       = 8443
    to_port         = 8445
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Owner = var.owner }
}

resource "aws_security_group_rule" "db_from_agents" {
  count                    = var.deploy_agentic_containers ? 1 : 0
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.agents[0].id
  description              = "PostgreSQL from the agentic host"
}

resource "aws_route53_zone" "agentic" {
  count = var.deploy_agentic_containers ? 1 : 0
  name  = local.agentic_fqdn
  vpc {
    vpc_id = local.vpc_id_effective
  }
  tags = { Owner = var.owner }
}

resource "aws_route53_record" "agents" {
  count   = var.deploy_agentic_containers ? 1 : 0
  zone_id = aws_route53_zone.agentic[0].zone_id
  name    = local.agentic_fqdn
  type    = "A"
  ttl     = 30
  records = [aws_instance.agents[0].private_ip]
}

resource "aws_instance" "agents" {
  lifecycle {
    precondition {
      condition     = can(regex("sonarqube-datacenter-2026\\.5\\.[0-9]+\\.[0-9]+\\.zip([?#].*)?$", local.sonar_zip_url)) && var.agentic_generator_revision != "" && var.mcp_image != ""
      error_message = "Enable the agentic pack only with a DCE 2026.5 distribution, a pinned generator commit and a pinned MCP image."
    }
  }
  count                       = var.deploy_agentic_containers ? 1 : 0
  ami                         = data.aws_ami.agents[0].id
  instance_type               = var.agentic_instance_type
  subnet_id                   = local.private_subnet_ids[var.app_nodes[0].subnet_index]
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.agents[0].id]
  iam_instance_profile        = aws_iam_instance_profile.agentic["agents"].name
  user_data_replace_on_change = true
  user_data_base64 = base64gzip(templatefile("${path.module}/templates/agentic_linux.sh.tftpl", {
    bucket   = aws_s3_bucket.agentic["bootstrap"].id
    region   = var.aws_region
    sq_host  = local.domain_fqdn
    revision = var.agentic_generator_revision
    mcp      = var.mcp_image
    profile = jsonencode({
      edition                   = "none"
      db_mode                   = "external"
      db_host                   = aws_db_instance.postgres.address
      db_port                   = "5432"
      db_name                   = local.rds_database_name
      db_user                   = var.db_username
      db_password               = random_password.db_admin.result
      storage                   = "s3"
      s3_bucket                 = aws_s3_bucket.agentic["jobs"].id
      s3_region                 = var.aws_region
      s3_access_key             = aws_iam_access_key.agentic_storage[0].id
      s3_secret_key             = aws_iam_access_key.agentic_storage[0].secret
      s3_path_style             = "false"
      tls                       = "on"
      tls_server_name           = local.agentic_fqdn
      sonarqube_external_host   = local.domain_fqdn
      sonarqube_external_port   = "443"
      sonarqube_external_scheme = "https"
      sandbox                   = "runsc"
      llm_domains               = join(",", var.agentic_llm_domains)
      custom_ca_dir             = "./custom-ca"
      project_name              = "sonarqube-agentic"
    })
  }))
  root_block_device {
    volume_size           = var.agentic_root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  tags = {
    Name  = "${var.hostname}-agents"
    Owner = var.owner
  }
  depends_on = [aws_iam_role_policy.agentic, aws_iam_user_policy.agentic_storage, aws_security_group_rule.db_from_agents, aws_route_table_association.private, aws_s3_bucket_policy.agentic]
}

output "agentic_host_id" {
  value       = var.deploy_agentic_containers ? aws_instance.agents[0].id : null
  description = "Separate Linux agent host for the DCE application nodes."
}

output "agentic_jobs_bucket" {
  value       = var.deploy_agentic_containers ? aws_s3_bucket.agentic["jobs"].id : null
  description = "Private shared agent storage for DCE and the Linux agent host."
}

variable "deploy_agentic_containers" {
  type        = bool
  description = "Deploy the 2026.5 agentic pack and hosted MCP on a shared Linux host."
  default     = false
}

variable "agentic_instance_type" {
  type        = string
  description = "x86_64 EC2 instance type for the separate Amazon Linux agent host in DCE deployments."
  default     = "m6a.2xlarge"
}

variable "agentic_generator_revision" {
  type        = string
  description = "Pinned 40-character commit of SonarSource/docker-sonarqube with 2026.5 agentic-compose-generator defaults."
  default     = ""

  validation {
    condition     = var.agentic_generator_revision == "" || can(regex("^[0-9a-f]{40}$", var.agentic_generator_revision))
    error_message = "Set agentic_generator_revision to a full commit SHA before enabling container deployment."
  }
}

variable "agentic_llm_domains" {
  type        = list(string)
  description = "Explicit LLM provider hostnames permitted by the agent runtime egress proxy."
  default     = ["api.anthropic.com"]

  validation {
    condition = length(var.agentic_llm_domains) > 0 && alltrue([
      for domain in var.agentic_llm_domains : can(regex("^[A-Za-z0-9][A-Za-z0-9.-]*$", domain))
    ])
    error_message = "Supply explicit LLM hostnames, without schemes, ports, or wildcards."
  }
}

variable "mcp_image" {
  type        = string
  description = "Release-compatible hosted MCP image, pinned by version tag or sha256 digest."
  default     = ""

  validation {
    condition = var.mcp_image == "" || (
      can(regex("^[A-Za-z0-9./_-]+:[0-9][A-Za-z0-9._-]*$", var.mcp_image)) ||
      can(regex("^[A-Za-z0-9./:_-]+@sha256:[0-9a-f]{64}$", var.mcp_image))
    )
    error_message = "Set mcp_image to a version-pinned image or sha256 digest, not latest."
  }
}

variable "agentic_root_volume_size" {
  type        = number
  description = "Root gp3 volume size in GiB when agentic containers are enabled, including sandbox writable layers."
  default     = 150

  validation {
    condition     = var.agentic_root_volume_size >= 100 && floor(var.agentic_root_volume_size) == var.agentic_root_volume_size
    error_message = "agentic_root_volume_size must be a whole number of at least 100 GiB."
  }
}