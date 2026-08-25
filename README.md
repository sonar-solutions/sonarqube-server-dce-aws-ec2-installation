# SonarQube DCE on AWS EC2

Terraform-only deployment for SonarQube Data Center Edition on AWS EC2. This project creates a DCE cluster with separate application and search nodes, PostgreSQL on RDS, a Network Load Balancer, optional Route53 DNS, and optional ACM TLS.

There is no Ansible playbook in this deployment.

## Architecture

```text
Users
  -> Network Load Balancer
       -> app nodes on :9000
            -> RDS PostgreSQL on :5432
            -> search nodes on :9005 and :9001
```

Terraform creates:

- VPC, public/private subnets, route tables, internet gateway, NAT gateway when `vpc_id = null`.
- Or uses an existing VPC/subnets when `vpc_id` is set.
- EC2 network interfaces for app and search nodes with AWS-assigned private IPs.
- EC2 app nodes and search nodes.
- RDS PostgreSQL.
- Network Load Balancer and app-node target group.
- Optional TLS listener with ACM.
- Optional Route53 record and hosted zone handling.
- EC2 key pair and local private key file.

Only app nodes are registered behind the public SonarQube listener. Search nodes stay private.

## Directory Layout On Nodes

Linux:

```text
/opt/sonarqube-<version>/
/opt/sonarqube -> /opt/sonarqube-<version>
```

Windows:

```text
C:\Installers\SonarQube\
  SonarQube.zip
  Java.msi

C:\SonarQube\
  prod\
    bin\
    conf\
    data\
    logs\
    temp\
```

For Windows, `C:\SonarQube\prod` is the SonarQube home.

## Quick Start

Create and edit a tfvars file:

```bash
cp terraform.tfvars.json.sample terraform.tfvars.json
```

Validate and deploy:

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

For a no-DNS/no-certificate test deployment, use:

```json
"route53_zone_mode": "none",
"certificate_mode": "none",
"plaintext_listener_port": 9000
```

Then use:

```bash
terraform output sonarqube_url
```

## Examples

Linux, new VPC:

```bash
terraform apply -var-file=examples/dce-new-vpc-linux.tfvars.json
```

Windows, new VPC:

```bash
terraform apply -var-file=examples/dce-new-vpc-windows.tfvars.json
```

Linux, existing VPC:

```bash
terraform apply -var-file=examples/existing-vpc-dce-linux.tfvars.json
```

## Node Placement

Nodes are configured with `app_nodes` and `search_nodes`. Do not set static private IPs. Terraform creates ENIs first, reads the assigned private IPs, and renders the DCE host lists into `sonar.properties`.

Example:

```json
"app_nodes": [
  { "name": "app1", "subnet_index": 0 },
  { "name": "app2", "subnet_index": 0 },
  { "name": "app3", "subnet_index": 0 },
  { "name": "app4", "subnet_index": 0 }
],
"search_nodes": [
  { "name": "search1", "subnet_index": 0 },
  { "name": "search2", "subnet_index": 0 },
  { "name": "search3", "subnet_index": 0 }
]
```

`subnet_index` points to an entry in `private_subnets`. The default examples place every DCE node in the first private subnet.

## Required Variables

- `aws_region`: AWS region.
- `owner`: owner tag.
- `hostname`: load balancer/DNS host label.
- `domain_name`: DNS zone domain.
- `rds_name`: RDS identifier and database-name source.
- `rds_instance_type`: RDS instance class.
- `private_subnets`: new VPC private subnet CIDRs, or existing private subnet IDs.
- `public_subnets`: new VPC public subnet CIDRs, or existing public subnet IDs.

For a new VPC:

- `vpc_id`: `null`.
- `vpc_name`: VPC name tag.
- `vpn_cidr`: VPC CIDR block.
- `availability_zones`: one AZ per subnet entry.

For an existing VPC:

- `vpc_id`: existing VPC ID.
- `private_subnets`: existing private subnet IDs.
- `public_subnets`: existing public subnet IDs.

## Main Options

Cluster sizing:

- `app_nodes`: app node names and private subnet indexes.
- `search_nodes`: search node names and private subnet indexes.
- `app_instance_type`: EC2 type for app nodes.
- `search_instance_type`: EC2 type for search nodes.
- `search_volume_size_gb`: search node root disk size.
- `search_volume_type`: search node root disk type.

Operating system:

- `installation_os`: `linux` or `windows`.
- `linux_sonar_dir`: Linux install root, default `/opt`.
- `win_sonar_dir`: Windows app root, default `c:\SonarQube`. SonarQube home is `win_sonar_dir\prod`.
- `win_installer_dir`: Windows staging root, default `c:\Installers\SonarQube`.
- `win_java_url`: Windows Java MSI URL.
- `win_java_filename`: Windows Java MSI filename.
- `install_chromium`: Windows-only optional Chromium install.

SonarQube distribution:

- `sonarqube_edition`: should be `datacenter` for DCE.
- `sonar_version`: version used in the default SonarSource URL. It may include or omit `.zip`.
- `zip_download_url`: full zip URL override.
- `zip_filename`: local installer zip filename.

DCE ports:

- `app_cluster_port`: default `9003`.
- `app_web_cluster_port`: default `9011`.
- `app_ce_cluster_port`: default `9012`.
- `search_port`: default `9005`.
- `es_port`: default `9001`.
- `system_passcode`: passcode for system/health endpoints.

Database:

- `rds_allocated_storage`: storage size in GB.
- `rds_storage_type`: default `gp3`.
- `rds_iops`: optional provisioned IOPS.
- `rds_multi_az`: enable Multi-AZ for HA.
- `rds_backup_retention_period`: backup retention days.
- `rds_engine_version`: PostgreSQL version.
- `db_username`: database username.

RDP:

- `enable_rdp`: optional Windows app-node RDP listener through the NLB.
- `rdp_allowed_cidr`: allowed CIDR when `enable_rdp = true`.

## DNS And TLS

Route53:

- `route53_zone_mode = "lookup"`: use a public hosted zone found by `domain_name`.
- `route53_zone_mode = "create"`: create a public hosted zone.
- `route53_zone_mode = "existing"`: use `route53_zone_id`.
- `route53_zone_mode = "none"`: do not manage DNS.

Certificate:

- `certificate_mode = "create"`: create ACM certificate and DNS validation records.
- `certificate_mode = "existing"`: use `acm_certificate_arn`.
- `certificate_mode = "none"`: no TLS listener; creates a plain TCP listener on `plaintext_listener_port`.

For early testing without a public certificate:

```json
"route53_zone_mode": "none",
"certificate_mode": "none",
"plaintext_listener_port": 9000
```

## Outputs

- `sonarqube_url`: public URL.
- `nlb_dns_name`: NLB DNS name.
- `app_node_private_ips`: app node private IPs.
- `search_node_private_ips`: search node private IPs.
- `rds_endpoint`: RDS endpoint.
- `rds_master_password`: generated RDS password.
- `key_pair_name`: EC2 key pair name.
- `private_key_path`: generated private key path.
- `route53_zone_id`: hosted zone ID when applicable.
- `route53_name_servers`: created hosted zone name servers.
- `certificate_arn`: ACM certificate ARN when applicable.

## Windows Notes

The Windows bootstrap writes progress and failures to:

```text
C:\Userdata.log
```

It writes DCE/JDBC settings to:

```text
C:\SonarQube\prod\conf\sonar.properties
```

It installs and starts the service with:

```text
C:\SonarQube\prod\bin\windows-x86-64\SonarService.bat
```

Windows paths rendered into `sonar.properties` use forward slashes so Java does not treat backslashes as escape characters.

## Operational Notes

- Terraform state contains generated secrets, including the RDS password and EC2 private key material.
- Add a remote backend before using this beyond local testing.
- `user_data_replace_on_change = true`; bootstrap changes replace app/search instances.
- Changing node subnet placement replaces ENIs and usually replaces instances.
- Search nodes are not exposed publicly.
- Disable RDP when not actively troubleshooting.
