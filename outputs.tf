output "sonarqube_url" {
  value       = var.certificate_mode == "none" ? "http://${local.public_host}:${var.plaintext_listener_port}" : "https://${local.public_host}"
  description = "Public URL to access SonarQube."
}

output "app_node_private_ips" {
  value       = aws_instance.app[*].private_ip
  description = "DCE application node private IPs."
}

output "search_node_private_ips" {
  value       = aws_instance.search[*].private_ip
  description = "DCE search node private IPs."
}

output "rds_endpoint" {
  value       = aws_db_instance.postgres.address
  description = "Endpoint of the PostgreSQL RDS instance."
}

output "nlb_dns_name" {
  value       = aws_lb.nlb.dns_name
  description = "Network Load Balancer DNS name."
}

output "rds_master_password" {
  value       = random_password.db_admin.result
  description = "Generated master password for the PostgreSQL instance."
  sensitive   = true
}

output "key_pair_name" {
  value       = aws_key_pair.ec2.key_name
  description = "Name of the EC2 key pair."
}

output "private_key_path" {
  value       = local_file.private_key.filename
  description = "Path to the saved private key file."
}

output "route53_zone_id" {
  value       = local.route53_zone_id
  description = "Route53 hosted zone ID used for DNS records."
}

output "route53_name_servers" {
  value       = local.route53_name_servers
  description = "Name servers for the created hosted zone. Empty unless route53_zone_mode is create."
}

output "certificate_arn" {
  value       = local.certificate_arn
  description = "ACM certificate ARN used by the load balancer listener. Null when certificate_mode is none."
}
