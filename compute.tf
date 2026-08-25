resource "aws_network_interface" "app" {
  count = length(var.app_nodes)

  subnet_id       = local.private_subnet_ids[var.app_nodes[count.index].subnet_index]
  security_groups = [aws_security_group.app.id]

  tags = {
    Name  = "${local.sanitized_hostname}-${var.app_nodes[count.index].name}-eni"
    Role  = "sonarqube-app"
    Owner = var.owner
  }
}

resource "aws_network_interface" "search" {
  count = length(var.search_nodes)

  subnet_id       = local.private_subnet_ids[var.search_nodes[count.index].subnet_index]
  security_groups = [aws_security_group.search.id]

  tags = {
    Name  = "${local.sanitized_hostname}-${var.search_nodes[count.index].name}-eni"
    Role  = "sonarqube-search"
    Owner = var.owner
  }
}

resource "aws_instance" "search" {
  count = length(var.search_nodes)

  ami                         = data.aws_ami.selected.id
  instance_type               = var.search_instance_type
  key_name                    = aws_key_pair.ec2.key_name
  user_data_replace_on_change = true

  primary_network_interface {
    network_interface_id = aws_network_interface.search[count.index].id
  }

  root_block_device {
    volume_size = var.search_volume_size_gb
    volume_type = var.search_volume_type
    encrypted   = true
  }

  user_data = local.is_windows ? templatefile("${path.module}/templates/windows_user_data.ps1.tftpl", {
    url              = local.sonar_zip_url
    path             = var.win_sonar_dir
    java_url         = var.win_java_url
    java_filename    = var.win_java_filename
    zip_filename     = var.zip_filename
    installer_path   = var.win_installer_dir
    install_chromium = var.install_chromium
    jdbc_url         = local.jdbc_url
    db_password      = random_password.db_admin.result
    db_username      = var.db_username
    cluster_config = templatefile("${path.module}/templates/sonar-cluster.properties.tftpl", {
      node_type            = "search"
      node_name            = var.search_nodes[count.index].name
      static_ip            = aws_network_interface.search[count.index].private_ip
      cluster_name         = var.cluster_name
      jwt_secret           = random_password.jwt_secret.result
      system_passcode      = var.system_passcode
      app_cluster_hosts    = local.app_cluster_hosts
      search_hosts         = local.search_hosts
      es_hosts             = local.es_hosts
      app_cluster_port     = var.app_cluster_port
      app_web_cluster_port = var.app_web_cluster_port
      app_ce_cluster_port  = var.app_ce_cluster_port
      search_port          = var.search_port
      es_port              = var.es_port
      data_path            = local.sonar_data_path
      temp_path            = local.sonar_temp_path
    })
    }) : templatefile("${path.module}/templates/linux_user_data.sh.tftpl", {
    url          = local.sonar_zip_url
    path         = var.linux_sonar_dir
    zip_filename = var.zip_filename
    jdbc_url     = local.jdbc_url
    db_password  = random_password.db_admin.result
    db_username  = var.db_username
    node_role    = "search"
    cluster_config = templatefile("${path.module}/templates/sonar-cluster.properties.tftpl", {
      node_type            = "search"
      node_name            = var.search_nodes[count.index].name
      static_ip            = aws_network_interface.search[count.index].private_ip
      cluster_name         = var.cluster_name
      jwt_secret           = random_password.jwt_secret.result
      system_passcode      = var.system_passcode
      app_cluster_hosts    = local.app_cluster_hosts
      search_hosts         = local.search_hosts
      es_hosts             = local.es_hosts
      app_cluster_port     = var.app_cluster_port
      app_web_cluster_port = var.app_web_cluster_port
      app_ce_cluster_port  = var.app_ce_cluster_port
      search_port          = var.search_port
      es_port              = var.es_port
      data_path            = local.sonar_data_path
      temp_path            = local.sonar_temp_path
    })
  })

  tags = {
    Name        = "${local.sanitized_hostname}-${var.search_nodes[count.index].name}"
    Role        = "sonarqube-search"
    Domain      = local.domain_fqdn
    OperatingOS = var.installation_os
    Owner       = var.owner
  }

  depends_on = [aws_db_instance.postgres]
}

resource "aws_instance" "app" {
  count = length(var.app_nodes)

  ami                         = data.aws_ami.selected.id
  instance_type               = var.app_instance_type
  key_name                    = aws_key_pair.ec2.key_name
  user_data_replace_on_change = true

  primary_network_interface {
    network_interface_id = aws_network_interface.app[count.index].id
  }

  user_data = local.is_windows ? templatefile("${path.module}/templates/windows_user_data.ps1.tftpl", {
    url              = local.sonar_zip_url
    path             = var.win_sonar_dir
    java_url         = var.win_java_url
    java_filename    = var.win_java_filename
    zip_filename     = var.zip_filename
    installer_path   = var.win_installer_dir
    install_chromium = var.install_chromium
    jdbc_url         = local.jdbc_url
    db_password      = random_password.db_admin.result
    db_username      = var.db_username
    cluster_config = templatefile("${path.module}/templates/sonar-cluster.properties.tftpl", {
      node_type            = "application"
      node_name            = var.app_nodes[count.index].name
      static_ip            = aws_network_interface.app[count.index].private_ip
      cluster_name         = var.cluster_name
      jwt_secret           = random_password.jwt_secret.result
      system_passcode      = var.system_passcode
      app_cluster_hosts    = local.app_cluster_hosts
      search_hosts         = local.search_hosts
      es_hosts             = local.es_hosts
      app_cluster_port     = var.app_cluster_port
      app_web_cluster_port = var.app_web_cluster_port
      app_ce_cluster_port  = var.app_ce_cluster_port
      search_port          = var.search_port
      es_port              = var.es_port
      data_path            = local.sonar_data_path
      temp_path            = local.sonar_temp_path
    })
    }) : templatefile("${path.module}/templates/linux_user_data.sh.tftpl", {
    url          = local.sonar_zip_url
    path         = var.linux_sonar_dir
    zip_filename = var.zip_filename
    jdbc_url     = local.jdbc_url
    db_password  = random_password.db_admin.result
    db_username  = var.db_username
    node_role    = "application"
    cluster_config = templatefile("${path.module}/templates/sonar-cluster.properties.tftpl", {
      node_type            = "application"
      node_name            = var.app_nodes[count.index].name
      static_ip            = aws_network_interface.app[count.index].private_ip
      cluster_name         = var.cluster_name
      jwt_secret           = random_password.jwt_secret.result
      system_passcode      = var.system_passcode
      app_cluster_hosts    = local.app_cluster_hosts
      search_hosts         = local.search_hosts
      es_hosts             = local.es_hosts
      app_cluster_port     = var.app_cluster_port
      app_web_cluster_port = var.app_web_cluster_port
      app_ce_cluster_port  = var.app_ce_cluster_port
      search_port          = var.search_port
      es_port              = var.es_port
      data_path            = local.sonar_data_path
      temp_path            = local.sonar_temp_path
    })
  })

  tags = {
    Name        = "${local.sanitized_hostname}-${var.app_nodes[count.index].name}"
    Role        = "sonarqube-app"
    Domain      = local.domain_fqdn
    OperatingOS = var.installation_os
    Owner       = var.owner
  }

  depends_on = [aws_db_instance.postgres, aws_instance.search]
}

resource "aws_lb_target_group_attachment" "app" {
  count = length(aws_instance.app)

  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app[count.index].id
  port             = 9000
}
