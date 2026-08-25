resource "aws_lb" "nlb" {
  name                             = local.load_balancer_name
  internal                         = false
  load_balancer_type               = "network"
  subnets                          = local.public_subnet_ids
  enable_cross_zone_load_balancing = true

  tags = {
    Name  = local.load_balancer_name
    Owner = var.owner
  }
}

resource "aws_lb_target_group" "app" {
  name        = local.target_group_name
  port        = 9000
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = local.vpc_id_effective

  stickiness {
    enabled = true
    type    = "source_ip"
  }

  health_check {
    port                = "9000"
    protocol            = "TCP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = {
    Name  = "${local.load_balancer_name}-tg"
    Owner = var.owner
  }
}

resource "aws_lb_target_group" "rdp" {
  count = local.is_windows && var.enable_rdp ? 1 : 0

  name        = local.rdp_target_group_name
  port        = 3389
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = local.vpc_id_effective

  health_check {
    port                = "3389"
    protocol            = "TCP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = {
    Name  = "${local.load_balancer_name}-rdp-tg"
    Owner = var.owner
  }
}

resource "aws_lb_target_group_attachment" "app_rdp" {
  count = local.is_windows && var.enable_rdp ? length(aws_instance.app) : 0

  target_group_arn = aws_lb_target_group.rdp[0].arn
  target_id        = aws_instance.app[count.index].id
  port             = 3389
}

resource "aws_lb_listener" "rdp" {
  count = local.is_windows && var.enable_rdp ? 1 : 0

  load_balancer_arn = aws_lb.nlb.arn
  port              = 3389
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rdp[0].arn
  }
}

data "aws_route53_zone" "primary" {
  count = var.route53_zone_mode == "lookup" ? 1 : 0

  name         = local.route53_zone_name
  private_zone = false
}

resource "aws_route53_zone" "primary" {
  count = var.route53_zone_mode == "create" ? 1 : 0

  name = local.route53_zone_name

  tags = {
    Name  = local.route53_zone_name
    Owner = var.owner
  }
}

resource "aws_acm_certificate" "nlb" {
  count = var.certificate_mode == "create" ? 1 : 0

  domain_name       = local.domain_fqdn
  validation_method = "DNS"

  tags = {
    Name  = local.domain_fqdn
    Owner = var.owner
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in var.certificate_mode == "create" ? aws_acm_certificate.nlb[0].domain_validation_options : [] : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  zone_id         = local.route53_zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 300
  records         = [each.value.record]
}

resource "aws_acm_certificate_validation" "nlb" {
  count = var.certificate_mode == "create" ? 1 : 0

  certificate_arn         = aws_acm_certificate.nlb[0].arn
  validation_record_fqdns = [for record in values(aws_route53_record.cert_validation) : record.fqdn]

  timeouts {
    create = var.acm_validation_timeout
  }
}

resource "aws_lb_listener" "tls" {
  count = var.certificate_mode == "none" ? 0 : 1

  load_balancer_arn = aws_lb.nlb.arn
  port              = 443
  protocol          = "TLS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = local.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  depends_on = [aws_acm_certificate_validation.nlb]
}

resource "aws_lb_listener" "plaintext" {
  count = var.certificate_mode == "none" ? 1 : 0

  load_balancer_arn = aws_lb.nlb.arn
  port              = var.plaintext_listener_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_route53_record" "app_alias" {
  count = var.route53_zone_mode == "none" ? 0 : 1

  zone_id = local.route53_zone_id
  name    = var.hostname
  type    = "A"

  alias {
    name                   = aws_lb.nlb.dns_name
    zone_id                = aws_lb.nlb.zone_id
    evaluate_target_health = true
  }
}
