# SonarQube Data Center Edition on AWS EC2

This repository deploys a SonarQube Data Center Edition cluster on AWS with Terraform. It is intentionally focused on DCE: application nodes, search nodes, PostgreSQL on RDS, a public Network Load Balancer, TLS through ACM, and DNS through Route53.

## Architecture

```text
Users
  -> Route53 A record
  -> AWS Network Load Balancer :443
  -> SonarQube application nodes :9000
       -> RDS PostgreSQL :5432
       -> SonarQube search nodes :9005
            -> search-to-search transport :9001
```

Terraform creates or uses the following AWS resources:

- VPC, public subnets, private subnets, route tables, internet gateway, and NAT gateway when `vpc_id` is not provided.
- Existing VPC and subnets when `vpc_id` is provided.
- Security groups for application nodes, search nodes, and RDS.
- EC2 network interfaces for each app/search node. AWS assigns the private IPs dynamically.
- EC2 instances for application and search nodes, using either Amazon Linux 2023 or Windows Server 2025.
- RDS PostgreSQL database and subnet group.
- Network Load Balancer, TLS listener, and target group for application nodes (configured with source IP stickiness).
- Route53 hosted zone lookup/create/existing-zone integration.
- ACM certificate creation or use of an existing certificate.
- EC2 key pair and generated private key file.

Only application nodes are registered behind the public load balancer. Search nodes stay private and are reachable only from the application/security-group path required by the cluster.

## How Node IPs Work

Do not configure `private_ip` values for nodes. Each node gets an AWS-assigned private IP from its selected subnet.

Terraform creates each node's network interface first, reads the assigned private IP, and renders the cluster host lists into `sonar.properties` before the instance starts. The node lists therefore use this shape:

```json
"app_nodes": [
  {
    "name": "app1",
    "subnet_index": 0
  },
  {
    "name": "app2",
    "subnet_index": 0
  }
],
"search_nodes": [
  {
    "name": "search1",
    "subnet_index": 0
  },
  {
    "name": "search2",
    "subnet_index": 0
  },
  {
    "name": "search3",
    "subnet_index": 0
  }
]
```

`subnet_index` points at the index in `private_subnets`. The default examples keep every DCE app and search node on `subnet_index = 0`, which places the cluster in the first private subnet.

## Configure And Deploy

Create a variable file from the sample:

```bash
cp terraform.tfvars.json.sample terraform.tfvars.json
```

Edit `terraform.tfvars.json`, then run:

```bash
terraform init
terraform plan
terraform apply
```

The sample file is set up for a first test deployment without a public hosted zone or public certificate:

```json
"route53_zone_mode": "none",
"certificate_mode": "none",
"plaintext_listener_port": 9000
```

That mode skips Route53, skips ACM, and exposes the Network Load Balancer on TCP port `9000`.

You can also use one of the included examples:

```bash
terraform plan -var-file=examples/dce-new-vpc-linux.tfvars.json
terraform apply -var-file=examples/dce-new-vpc-linux.tfvars.json
```

For a Windows DCE cluster:

```bash
terraform plan -var-file=examples/dce-new-vpc-windows.tfvars.json
terraform apply -var-file=examples/dce-new-vpc-windows.tfvars.json
```

For an existing VPC:

```bash
terraform plan -var-file=examples/existing-vpc-dce-linux.tfvars.json
terraform apply -var-file=examples/existing-vpc-dce-linux.tfvars.json
```

## Required Configuration

Set these values for every deployment:

- `aws_region`: AWS region where resources are created.
- `hostname`: DNS host label, for example `sq-dce`.
- `domain_name`: Route53 hosted zone domain, for example `example.com`.
- `owner`: owner tag applied to resources.
- `rds_name`: RDS identifier and database-name source.
- `rds_instance_type`: RDS instance class.
- `private_subnets`: private subnet CIDRs for a new VPC, or private subnet IDs for an existing VPC.
- `public_subnets`: public subnet CIDRs for a new VPC, or public subnet IDs for an existing VPC/load balancer.

When creating a new VPC, also set:

- `vpc_id`: `null`
- `vpc_name`: name tag for the VPC.
- `vpn_cidr`: VPC CIDR block.
- `availability_zones`: one AZ per private/public subnet entry.

When using an existing VPC, set:

- `vpc_id`: existing VPC ID.
- `private_subnets`: existing private subnet IDs.
- `public_subnets`: existing public subnet IDs. If omitted, the load balancer uses `private_subnets`.

## What Is Configurable

Cluster shape:

- `app_nodes`: application node names and subnet placement.
- `search_nodes`: search node names and subnet placement.
- `app_instance_type`: EC2 type for application nodes.
- `search_instance_type`: EC2 type for search nodes.
- `search_volume_size_gb`: search node root volume size.
- `search_volume_type`: search node root volume type.

Operating system:

- `installation_os`: `linux` or `windows`.
- Linux deployments use Amazon Linux 2023 and `linux_sonar_dir`.
- Windows deployments use Windows Server 2025 and the Windows-specific variables below.
- `win_sonar_dir`: Windows application root. The active SonarQube home is `win_sonar_dir\prod`.
- `win_installer_dir`: Windows installer staging root. The default is `c:\Installers\SonarQube`.
- `win_java_url`: Windows Java installer URL.
- `win_java_filename`: Windows Java installer file name.
- `enable_rdp`: whether to expose RDP through the load balancer to application nodes.
- `rdp_allowed_cidr`: CIDR allowed to access RDP when enabled.
- `install_chromium`: whether to install Chromium on Windows nodes.

SonarQube version and distribution:

- `sonarqube_edition`: defaults to `datacenter`.
- `sonar_version`: version used to build the SonarSource download URL.
- `zip_download_url`: optional full installer URL override.
- `zip_filename`: file name used on each instance.
- `linux_sonar_dir`: install directory on each instance.

Cluster settings:

- `cluster_name`: SonarQube cluster name.
- `app_cluster_port`: application node cluster port, default `9003`.
- `app_web_cluster_port`: web process cluster port, default `9011`.
- `app_ce_cluster_port`: Compute Engine cluster port, default `9012`.
- `search_port`: app-to-search port, default `9005`.
- `es_port`: search-to-search transport port, default `9001`.
- `system_passcode`: SonarQube system passcode used by health/system endpoints.

Database:

- `rds_instance_type`: RDS instance class.
- `rds_allocated_storage`: allocated storage in GB.
- `rds_storage_type`: RDS storage type, default `gp3`.
- `rds_iops`: optional provisioned IOPS for supported storage types.
- `rds_multi_az`: whether to create RDS Multi-AZ. `false` is faster and cheaper for test deployments; `true` is better for HA.
- `rds_backup_retention_period`: automated backup retention in days.
- `rds_engine_version`: PostgreSQL engine version.
- `db_username`: database username.

DNS and TLS:

- `route53_zone_mode`: `lookup`, `create`, `existing`, or `none`.
- `route53_zone_id`: required when `route53_zone_mode = "existing"`.
- `certificate_mode`: `create`, `existing`, or `none`.
- `acm_certificate_arn`: required when `certificate_mode = "existing"`.
- `acm_validation_timeout`: timeout for ACM DNS validation.
- `plaintext_listener_port`: public TCP listener port when `certificate_mode = "none"`.

## Route53 Hosted Zone Modes

Use `lookup` when a public hosted zone already exists and can be found by `domain_name`:

```json
"route53_zone_mode": "lookup",
"route53_zone_id": null
```

Use `create` when Terraform should create the public hosted zone:

```json
"route53_zone_mode": "create",
"route53_zone_id": null
```

If the domain is registered outside Route53, update the registrar with the created zone's name servers before ACM validation can complete.

Use `existing` when you already know the hosted zone ID:

```json
"route53_zone_mode": "existing",
"route53_zone_id": "Z1234567890ABC"
```

Use `none` when you do not want Terraform to manage DNS records:

```json
"route53_zone_mode": "none",
"route53_zone_id": null
```

This is useful for early testing with the Network Load Balancer DNS name.

## Certificate Modes

Create a certificate and DNS validation records:

```json
"certificate_mode": "create",
"acm_certificate_arn": null,
"acm_validation_timeout": "45m"
```

Use an existing ACM certificate:

```json
"certificate_mode": "existing",
"acm_certificate_arn": "arn:aws:acm:REGION:ACCOUNT:certificate/ID"
```

The certificate must be in the same region as the Network Load Balancer.

Bypass ACM and TLS completely:

```json
"certificate_mode": "none",
"acm_certificate_arn": null,
"plaintext_listener_port": 9000
```

This creates a plain TCP listener on the Network Load Balancer and forwards to SonarQube on port `9000`. Use this when you do not have a public certificate yet.

## Outputs

Useful outputs after apply:

- `sonarqube_url`: public URL. This is HTTPS for ACM-backed deployments and HTTP with the NLB DNS name when `certificate_mode = "none"`.
- `app_node_private_ips`: AWS-assigned application node private IPs.
- `search_node_private_ips`: AWS-assigned search node private IPs.
- `rds_endpoint`: PostgreSQL endpoint.
- `nlb_dns_name`: Network Load Balancer DNS name.
- `rds_master_password`: generated database password, marked sensitive.
- `private_key_path`: generated EC2 private key path.
- `route53_zone_id`: hosted zone used by the deployment.
- `route53_name_servers`: name servers when Terraform creates a zone.
- `certificate_arn`: ACM certificate used by the TLS listener.

## Operational Notes

- Terraform state contains generated secrets, including the RDS password and EC2 private key material. Store state accordingly.
- This repository does not configure a remote backend; add one that matches your environment.
- DCE bootstrapping supports Linux and Windows; Linux uses Amazon Linux 2023 AMIs and Windows uses Windows Server AMIs.
- App/search node private IPs are dynamic but remain attached to their managed network interfaces until those ENIs are replaced.
- Changing node counts or subnet placement may replace network interfaces and update cluster host lists.
- Keep SSH and RDP disabled unless you are actively troubleshooting.
