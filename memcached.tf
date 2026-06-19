module "elasticache" {
  source  = "guidion-digital/helper-elasticache/aws"
  version = "~> 0.0"

  for_each = var.elasticache

  project          = var.project
  application_name = var.application_name
  stage            = var.stage

  name                         = "${var.application_name}-${each.key}"
  engine                       = each.value.engine
  engine_version               = each.value.engine_version
  node_type                    = each.value.node_type
  apply_immediately            = each.value.apply_immediately
  transit_encryption_enabled   = each.value.transit_encryption_enabled
  auto_minor_version_upgrade   = each.value.auto_minor_version_upgrade
  maintenance_window           = each.value.maintenance_window
  parameters                   = each.value.parameters
  ip_discovery                 = each.value.ip_discovery
  network_type                 = each.value.network_type
  port                         = each.value.port
  notification_topic_arn       = each.value.notification_topic_arn
  az_mode                      = each.value.az_mode
  availability_zone            = each.value.availability_zone
  preferred_availability_zones = each.value.preferred_availability_zones
  vpc_id                       = each.value.vpc_id != null ? each.value.vpc_id : module.vpc[0].vpc_attributes.id
  subnet_ids                   = each.value.subnet_ids != null ? each.value.subnet_ids : [for _, value in module.vpc[0].private_subnet_attributes_by_az : value.id]
  security_group_rules         = each.value.security_group_rules
  security_group_ids           = each.value.security_group_ids
  allowed_cidrs                = each.value.allowed_cidrs
}
