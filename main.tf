locals {
  create_vpc            = var.vpc_id == null || trimspace(var.vpc_id) == ""
  is_windows            = var.installation_os == "windows"
  sanitized_hostname    = lower(replace(var.hostname, "/[^a-z0-9-]/", "-"))
  load_balancer_name    = substr(local.sanitized_hostname, 0, 32)
  target_group_name     = substr("${local.sanitized_hostname}-tg", 0, 32)
  rdp_target_group_name = substr("${local.sanitized_hostname}-rdp-tg", 0, 32)
  domain_fqdn           = format("%s.%s", var.hostname, trim(var.domain_name, "."))
  route53_zone_name     = "${trim(var.domain_name, ".")}."
  route53_zone_id       = var.route53_zone_mode == "none" ? null : (var.route53_zone_mode == "existing" ? var.route53_zone_id : (var.route53_zone_mode == "create" ? aws_route53_zone.primary[0].zone_id : data.aws_route53_zone.primary[0].zone_id))
  route53_name_servers  = var.route53_zone_mode == "create" ? aws_route53_zone.primary[0].name_servers : []
  certificate_arn       = var.certificate_mode == "none" ? null : (var.certificate_mode == "existing" ? var.acm_certificate_arn : aws_acm_certificate_validation.nlb[0].certificate_arn)
  public_host           = var.route53_zone_mode == "none" ? aws_lb.nlb.dns_name : local.domain_fqdn
  rds_identifier        = substr(replace(lower(var.rds_name), "/[^a-z0-9-]/", "-"), 0, 63)
  rds_database_name     = substr(replace(lower(var.rds_name), "/[^a-z0-9]/", ""), 0, 63)
  jdbc_url              = "jdbc:postgresql://${aws_db_instance.postgres.address}:5432/${local.rds_database_name}"
  sonar_version_clean   = trimsuffix(var.sonar_version, ".zip")
  sonar_zip_url         = var.zip_download_url != null && trimspace(var.zip_download_url) != "" ? var.zip_download_url : "https://binaries.sonarsource.com/CommercialDistribution/sonarqube-${var.sonarqube_edition}/sonarqube-${var.sonarqube_edition}-${local.sonar_version_clean}.zip"
  linux_sonar_base      = trimsuffix(var.linux_sonar_dir, "/")
  windows_sonar_base    = replace(trimsuffix(var.win_sonar_dir, "\\"), "\\", "/")
  sonar_data_path       = local.is_windows ? "${local.windows_sonar_base}/prod/data" : "${local.linux_sonar_base}/sonarqube/data"
  sonar_temp_path       = local.is_windows ? "${local.windows_sonar_base}/prod/temp" : "${local.linux_sonar_base}/sonarqube/temp"

  ami_lookup = {
    "amazon-linux-2023" = {
      owners = ["amazon"]
      filters = {
        name                  = ["al2023-ami-*-x86_64"]
        "virtualization-type" = ["hvm"]
      }
    }
    "windows-2025" = {
      owners = ["801119661308"]
      filters = {
        name                  = ["Windows_Server-2025-English-Full-Base-*"]
        "virtualization-type" = ["hvm"]
      }
    }
  }

  os_to_ami_key = {
    linux   = "amazon-linux-2023"
    windows = "windows-2025"
  }

  selected_ami_key = local.os_to_ami_key[var.installation_os]

  vpc_id_effective   = local.create_vpc ? aws_vpc.this[0].id : var.vpc_id
  az_to_cidr         = local.create_vpc ? zipmap(var.availability_zones, var.private_subnets) : {}
  az_to_public_cidr  = local.create_vpc ? zipmap(var.availability_zones, var.public_subnets) : {}
  private_subnet_ids = local.create_vpc ? [for subnet in values(aws_subnet.private) : subnet.id] : var.private_subnets
  public_subnet_ids  = local.create_vpc ? [for subnet in values(aws_subnet.public) : subnet.id] : (var.public_subnets != null ? var.public_subnets : var.private_subnets)

  app_private_ips    = aws_network_interface.app[*].private_ip
  search_private_ips = aws_network_interface.search[*].private_ip
  app_cluster_hosts  = join(",", local.app_private_ips)
  search_hosts       = join(",", [for ip in local.search_private_ips : "${ip}:${var.search_port}"])
  es_hosts           = join(",", local.search_private_ips)
}

resource "terraform_data" "validations" {
  lifecycle {
    precondition {
      condition     = var.sonarqube_edition == "datacenter" || (var.zip_download_url != null && trimspace(var.zip_download_url) != "")
      error_message = "DCE mode requires the datacenter distribution unless zip_download_url points to a valid DCE installer."
    }
    precondition {
      condition     = var.certificate_mode != "create" || var.route53_zone_mode != "none"
      error_message = "route53_zone_mode cannot be none when certificate_mode is create because ACM DNS validation needs a hosted zone."
    }
    precondition {
      condition     = var.route53_zone_mode != "existing" || (var.route53_zone_id != null && trimspace(var.route53_zone_id) != "")
      error_message = "route53_zone_id must be provided when route53_zone_mode is existing."
    }
    precondition {
      condition     = var.certificate_mode != "existing" || (var.acm_certificate_arn != null && trimspace(var.acm_certificate_arn) != "")
      error_message = "acm_certificate_arn must be provided when certificate_mode is existing."
    }
    precondition {
      condition     = length(var.app_nodes) >= 2
      error_message = "DCE mode should include at least two application nodes."
    }
    precondition {
      condition     = length(var.search_nodes) >= 3
      error_message = "DCE mode should include at least three search nodes."
    }
    precondition {
      condition     = !local.create_vpc || length(var.availability_zones) == length(var.private_subnets) && length(var.availability_zones) == length(var.public_subnets)
      error_message = "availability_zones, private_subnets, and public_subnets must have matching lengths when creating a new VPC."
    }
  }
}

data "aws_ami" "selected" {
  most_recent = true
  owners      = local.ami_lookup[local.selected_ami_key].owners

  dynamic "filter" {
    for_each = local.ami_lookup[local.selected_ami_key].filters
    content {
      name   = filter.key
      values = filter.value
    }
  }
}

resource "random_password" "db_admin" {
  length           = 32
  special          = true
  override_special = "!#%^&*()_+-=[]{}|;:,.<>?"
}

resource "random_password" "jwt_secret" {
  length  = 48
  special = false
}

resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ec2" {
  key_name   = "${local.sanitized_hostname}-key"
  public_key = tls_private_key.ec2_key.public_key_openssh

  tags = {
    Name  = "${local.sanitized_hostname}-key"
    Owner = var.owner
  }
}

resource "local_file" "private_key" {
  content         = tls_private_key.ec2_key.private_key_pem
  filename        = "${local.sanitized_hostname}-key.pem"
  file_permission = "0600"
}
