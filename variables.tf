variable "aws_region" {
  type        = string
  description = "AWS region to deploy resources into."
}

variable "app_instance_type" {
  type        = string
  description = "EC2 instance type for DCE application nodes."
  default     = "m6a.xlarge"
}

variable "search_instance_type" {
  type        = string
  description = "EC2 instance type for DCE search nodes."
  default     = "m6a.2xlarge"
}

variable "installation_os" {
  type        = string
  description = "Operating system selector for DCE nodes. Supported values: windows, linux."
  default     = "linux"

  validation {
    condition     = contains(["windows", "linux"], var.installation_os)
    error_message = "installation_os must be windows or linux."
  }
}

variable "vpc_id" {
  type        = string
  description = "Existing VPC ID. Leave empty or null to create a new VPC."
  default     = null
}

variable "vpc_name" {
  type        = string
  description = "Name tag for the VPC when one is created."
  default     = null
}

variable "vpn_cidr" {
  type        = string
  description = "CIDR block for the new VPC. Only required when creating a VPC."
  default     = null
}

variable "private_subnets" {
  type        = list(string)
  description = "When creating a VPC, private subnet CIDR blocks. When using an existing VPC, existing private subnet IDs."

  validation {
    condition     = length(var.private_subnets) > 0
    error_message = "private_subnets must include at least one subnet CIDR or subnet ID."
  }
}

variable "public_subnets" {
  type        = list(string)
  description = "When creating a VPC, public subnet CIDR blocks. When using an existing VPC, existing public subnet IDs. If null with an existing VPC, private_subnets are reused for the load balancer."
  default     = null
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones to span subnets. Used when creating a new VPC."
  default     = []
}

variable "hostname" {
  type        = string
  description = "Host label to use for DNS and resource names."
}

variable "domain_name" {
  type        = string
  description = "Route53 hosted zone domain, for example example.com."
}

variable "rds_name" {
  type        = string
  description = "Identifier/base name for the PostgreSQL instance and initial database."
}

variable "rds_instance_type" {
  type        = string
  description = "Instance class for the PostgreSQL database."
}

variable "rds_allocated_storage" {
  type        = number
  description = "Allocated storage in GB for the PostgreSQL database."
  default     = 100
}

variable "rds_storage_type" {
  type        = string
  description = "Storage type for the PostgreSQL database."
  default     = "gp3"
}

variable "rds_iops" {
  type        = number
  description = "Provisioned IOPS for supported RDS storage types. Leave null to let AWS use the storage default."
  default     = null
}

variable "rds_multi_az" {
  type        = bool
  description = "Whether to create the PostgreSQL database as Multi-AZ. Disable for faster/lower-cost test deployments."
  default     = false
}

variable "rds_backup_retention_period" {
  type        = number
  description = "Number of days to retain PostgreSQL automated backups."
  default     = 7
}

variable "rds_engine_version" {
  type        = string
  description = "PostgreSQL engine version for the RDS instance."
  default     = "17.7"
}

variable "db_username" {
  type        = string
  description = "Username for the PostgreSQL database."
  default     = "sonarqube"
}

variable "owner" {
  type        = string
  description = "Owner tag value for all resources."
}

variable "rdp_allowed_cidr" {
  type        = string
  description = "CIDR block allowed to access RDP port 3389 on Windows application nodes when enable_rdp is true."
  default     = "0.0.0.0/0"
}

variable "install_chromium" {
  type        = bool
  description = "Whether to install Chromium on Windows nodes."
  default     = false
}

variable "enable_rdp" {
  type        = bool
  description = "Whether to enable RDP access to Windows application nodes through the load balancer."
  default     = false
}

variable "zip_download_url" {
  type        = string
  description = "Optional full URL to download the SonarQube installer zip. When null or empty, the URL is built from sonarqube_edition and sonar_version."
  default     = null
}

variable "sonar_version" {
  type        = string
  description = "SonarQube version to install when zip_download_url is not set."
  default     = "2026.1.0.119033"
}

variable "sonarqube_edition" {
  type        = string
  description = "Commercial SonarQube distribution to install when zip_download_url is not set."
  default     = "datacenter"

  validation {
    condition     = contains(["enterprise", "datacenter"], var.sonarqube_edition)
    error_message = "sonarqube_edition must be enterprise or datacenter."
  }
}

variable "zip_filename" {
  type        = string
  description = "Name of the SonarQube installer file on the instance."
  default     = "SonarQube.zip"
}

variable "linux_sonar_dir" {
  type        = string
  description = "Linux path where SonarQube will be downloaded and unzipped."
  default     = "/opt"
}

variable "win_sonar_dir" {
  type        = string
  description = "Windows application root. The active DCE home is created under the prod subdirectory."
  default     = "c:\\SonarQube"
}

variable "win_installer_dir" {
  type        = string
  description = "Windows path where SonarQube and Java installer files are downloaded."
  default     = "c:\\Installers\\SonarQube"
}

variable "win_java_url" {
  type        = string
  description = "URL to download the Windows Java installer."
  default     = "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.9%2B10/OpenJDK21U-jdk_x64_windows_hotspot_21.0.9_10.msi"
}

variable "win_java_filename" {
  type        = string
  description = "Name of the Java installer file on Windows instances."
  default     = "Java.msi"
}

variable "cluster_name" {
  type        = string
  description = "SonarQube DCE cluster name."
  default     = "sonarqube-dce"
}

variable "app_nodes" {
  type = list(object({
    name         = string
    subnet_index = number
  }))
  description = "DCE application nodes. AWS assigns each node's private IP dynamically through its network interface."
  default = [
    {
      name         = "app1"
      subnet_index = 0
    },
    {
      name         = "app2"
      subnet_index = 0
    },
    {
      name         = "app3"
      subnet_index = 0
    },
    {
      name         = "app4"
      subnet_index = 0
    }
  ]

  validation {
    condition     = length(var.app_nodes) >= 1
    error_message = "app_nodes must include at least one application node."
  }
}

variable "search_nodes" {
  type = list(object({
    name         = string
    subnet_index = number
  }))
  description = "DCE search nodes. AWS assigns each node's private IP dynamically through its network interface."
  default = [
    {
      name         = "search1"
      subnet_index = 0
    },
    {
      name         = "search2"
      subnet_index = 0
    },
    {
      name         = "search3"
      subnet_index = 0
    }
  ]

  validation {
    condition     = length(var.search_nodes) >= 1
    error_message = "search_nodes must include at least one search node."
  }
}

variable "app_cluster_port" {
  type        = number
  description = "DCE application node cluster port."
  default     = 9003
}

variable "app_web_cluster_port" {
  type        = number
  description = "DCE application node web process cluster port."
  default     = 9011
}

variable "app_ce_cluster_port" {
  type        = number
  description = "DCE application node Compute Engine cluster port."
  default     = 9012
}

variable "search_port" {
  type        = number
  description = "DCE app-to-search port."
  default     = 9005
}

variable "es_port" {
  type        = number
  description = "DCE search-to-search Elasticsearch transport port."
  default     = 9001
}

variable "system_passcode" {
  type        = string
  description = "SonarQube system passcode used by health checks and system endpoints."
  default     = "healthcheck"
  sensitive   = true
}

variable "search_volume_size_gb" {
  type        = number
  description = "Root EBS volume size for DCE search nodes."
  default     = 100
}

variable "search_volume_type" {
  type        = string
  description = "Root EBS volume type for DCE search nodes."
  default     = "gp3"
}

variable "route53_zone_mode" {
  type        = string
  description = "How to select the public Route53 hosted zone: lookup, create, existing, or none."
  default     = "lookup"

  validation {
    condition     = contains(["lookup", "create", "existing", "none"], var.route53_zone_mode)
    error_message = "route53_zone_mode must be lookup, create, existing, or none."
  }
}

variable "route53_zone_id" {
  type        = string
  description = "Existing public Route53 hosted zone ID. Required when route53_zone_mode is existing."
  default     = null
}

variable "certificate_mode" {
  type        = string
  description = "How to provide the load balancer certificate: create, existing, or none."
  default     = "create"

  validation {
    condition     = contains(["create", "existing", "none"], var.certificate_mode)
    error_message = "certificate_mode must be create, existing, or none."
  }
}

variable "acm_certificate_arn" {
  type        = string
  description = "Existing ACM certificate ARN. Required when certificate_mode is existing."
  default     = null
}

variable "acm_validation_timeout" {
  type        = string
  description = "How long Terraform waits for ACM DNS validation when certificate_mode is create."
  default     = "45m"
}

variable "plaintext_listener_port" {
  type        = number
  description = "Public NLB listener port used when certificate_mode is none."
  default     = 9000
}
