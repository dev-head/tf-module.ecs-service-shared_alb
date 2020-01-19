
resource "aws_ecr_repository" "service" {
    for_each                = var.services
    name                    = format("%s", lookup(each.value, "name"))
    image_tag_mutability    = "MUTABLE"
    tags                    = merge({"Name": format("%s", lookup(each.value, "name"))}, lookup(each.value, "tags"), var.tags)

    image_scanning_configuration {
        scan_on_push = lookup(each.value, "ecr_scan_on_push", true)
    }
}

resource "aws_ecr_lifecycle_policy" "service" {
    for_each    = var.services
    repository  = aws_ecr_repository.service[each.key].name
    policy = <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Expire untagged images older than 14 days",
            "selection": {
                "tagStatus": "untagged",
                "countType": "sinceImagePushed",
                "countUnit": "days",
                "countNumber": 14
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
}

resource "aws_iam_role" "service_role" {
    for_each            = var.services
    name                = format("%s-sr", lookup(each.value, "name"))
    assume_role_policy  = data.aws_iam_policy_document.service_role_assume[each.key].json
}

resource "aws_iam_policy" "service_role" {
    for_each = var.services
    name    = format("%sRolePolicy", lookup(each.value, "name"))
    path    = "/"
    policy  = data.aws_iam_policy_document.service_role_policy_compiled[each.key].json
}

resource "aws_iam_role_policy_attachment" "project_default" {
    for_each    = var.services
    role        = aws_iam_role.service_role[each.key].name
    policy_arn  = aws_iam_policy.service_role[each.key].arn
}

resource "aws_iam_role_policy_attachment" "ecs_autoscale" {
    for_each    = var.services
    role        = aws_iam_role.service_role[each.key].name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceAutoscaleRole"
}

resource "aws_iam_role_policy_attachment" "ecs_service_ec2" {
    for_each    = var.services
    role        = aws_iam_role.service_role[each.key].name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecs_service" {
    for_each    = var.services
    role        = aws_iam_role.service_role[each.key].name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
}

resource "aws_iam_role_policy_attachment" "ecs_service_full" {
    for_each    = var.services
    role        = aws_iam_role.service_role[each.key].name
    policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerServiceFullAccess"
}

resource "aws_cloudwatch_log_group" "service" {
    for_each            = var.services
    name                = format("%s", lookup(each.value, "log_group_name"))
    retention_in_days   = lookup(each.value, "log_retention_days")
    tags                = merge({"Name": format("%s", lookup(each.value, "name"))}, lookup(each.value, "tags"), var.tags)
}

resource "aws_ecs_task_definition" "service" {
    for_each            = var.services
    family              = format("%s", lookup(each.value, "name"))
    task_role_arn       = lookup(each.value, "task_role_arn", null)
    execution_role_arn  = lookup(each.value, "execution_role_arn", null)
    network_mode        = lookup(each.value, "network_mode")
    cpu                 = lookup(each.value, "task_cpu", null)
    memory              = lookup(each.value, "task_memory", null)
    tags                = merge({"Name": format("%s", lookup(each.value, "name"))}, lookup(each.value, "tags"), var.tags)

    dynamic "volume" {
        for_each = lookup(each.value, "volumes", null)
        content {
            name        = lookup(volume.value, "name")
            host_path   = lookup(volume.value, "host_path")

            dynamic "docker_volume_configuration" {
                for_each = lookup(volume.value, "docker_volume_configuration")
                content {
                    scope           = lookup(docker_volume_configuration.value, "scope", null)
                    autoprovision   = lookup(docker_volume_configuration.value, "autoprovision", null)
                    driver          = lookup(docker_volume_configuration.value, "driver", null)
                    driver_opts     = lookup(docker_volume_configuration.value, "driver_opts", {})
                    labels          = lookup(docker_volume_configuration.value, "labels", {})
                }
            }
        }
    }

    container_definitions = templatefile(
        lookup(each.value, "task_definition_containers_path"),
        merge(lookup(each.value, "task_definition_vars"), {
                "aws_region":       data.aws_region.current,
                "ecr_url":          aws_ecr_repository.service[each.key].repository_url,
                "log_group_name":   lookup(each.value, "log_group_name")
                "task_name":        format("%s", lookup(each.value, "name"))
            }, lookup(each.value, "tags"), var.tags, lookup(each.value, "ports")
        )
    )

}

resource "aws_ecs_service" "service_ec2_daemon" {
    for_each            = local.services_daemon
    name                = format("%s", lookup(each.value, "name"))
    cluster             = data.aws_ecs_cluster.service[each.key].id
    task_definition     = aws_ecs_task_definition.service[each.key].arn
    desired_count       = lookup(each.value, "num_services")
    iam_role            = aws_iam_role.service_role[each.key].arn
    launch_type         = "EC2"
    scheduling_strategy = lookup(each.value, "scheduling_strategy")
    health_check_grace_period_seconds    = lookup(each.value, "health_check_grace_period_seconds", null)

    deployment_controller {
        type = upper(lookup(each.value, "deployment_type", "ECS"))
    }
    deployment_maximum_percent          = lookup(each.value, "deploy_max_percent")
    deployment_minimum_healthy_percent  = lookup(each.value, "deploy_min_healthy_percent")

    # Not supported until root account opts in to ECS Manged Tags
    # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-account-settings.html#ecs-resource-ids

    #enable_ecs_managed_tags             = false
    #propagate_tags                      = "TASK_DEFINITION"
    #tags                                = merge({"Name": format("%s", lookup(each.value, "name"))}, lookup(each.value, "tags"), var.tags)

    dynamic "ordered_placement_strategy" {
        for_each = lookup(each.value, "task_placement_strategies", null)
        content {
            type    = lookup(ordered_placement_strategy.value, "type")
            field   = lookup(ordered_placement_strategy.value, "field")
        }
    }

    dynamic "placement_constraints" {
        for_each = lookup(each.value, "placement_constraints", null)
        content {
            type        = lookup(placement_constraints.value, "type")
            expression  = lookup(placement_constraints.value, "expression")

        }
    }
}

resource "aws_ecs_service" "service_ec2_http" {
    for_each            = local.services_http
    name                = format("%s", lookup(each.value, "name"))
    cluster             = data.aws_ecs_cluster.service[each.key].id
    task_definition     = aws_ecs_task_definition.service[each.key].arn
    desired_count       = lookup(each.value, "num_services")
    iam_role            = aws_iam_role.service_role[each.key].arn
    launch_type         = "EC2"
    scheduling_strategy = lookup(each.value, "scheduling_strategy")
    health_check_grace_period_seconds    = lookup(each.value, "health_check_grace_period_seconds", null)

    deployment_controller {
        type = upper(lookup(each.value, "deployment_type", "ECS"))
    }
    deployment_maximum_percent          = lookup(each.value, "deploy_max_percent")
    deployment_minimum_healthy_percent  = lookup(each.value, "deploy_min_healthy_percent")

    # Not supported until root account opts in to ECS Manged Tags
    # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-account-settings.html#ecs-resource-ids
    #enable_ecs_managed_tags             = false
    #propagate_tags                      = "TASK_DEFINITION"
    #tags                                = merge({"Name": format("%s", lookup(each.value, "name"))}, lookup(each.value, "tags"), var.tags)

    dynamic "ordered_placement_strategy" {
        for_each = lookup(each.value, "task_placement_strategies", null)
        content {
            type    = lookup(ordered_placement_strategy.value, "type")
            field   = lookup(ordered_placement_strategy.value, "field")
        }
    }

    dynamic "placement_constraints" {
        for_each = lookup(each.value, "placement_constraints", null)
        content {
            type        = lookup(placement_constraints.value, "type")
            expression  = lookup(placement_constraints.value, "expression")

        }
    }

    load_balancer {
        container_name      = format("%s", lookup(each.value, "name"))
        container_port      = lookup(lookup(each.value, "ports"), "container_port")
        target_group_arn    = aws_lb_target_group.targets[each.key].arn
    }
}

resource "aws_lb_target_group" "targets" {
    for_each                = local.services_http
    vpc_id                  = lookup(lookup(each.value, "loadbalancer"), "vpc_id")
    tags                    = merge({"Name": format("%s", lookup(each.value, "name"))}, lookup(each.value, "tags"), var.tags)
    name                    = format("%s", lookup(each.value, "name"))
    port                    = lookup(lookup(each.value, "loadbalancer"), "port")
    protocol                = lookup(lookup(each.value, "loadbalancer"), "protocol")
    deregistration_delay    = lookup(lookup(each.value, "loadbalancer"), "deregistration_delay")
    target_type             = lookup(lookup(each.value, "loadbalancer"), "target_type")
    slow_start              = lookup(lookup(each.value, "loadbalancer"), "slow_start")

    stickiness  {
        type            = lookup(lookup(lookup(each.value, "loadbalancer"), "stickiness", {}), "type", "lb_cookie")
        cookie_duration = lookup(lookup(lookup(each.value, "loadbalancer"), "stickiness", {}), "cookie_duration", 86400)
        enabled         = lookup(lookup(lookup(each.value, "loadbalancer"), "stickiness", {}), "enabled", false)
    }

    health_check {
        enabled             = lookup(lookup(lookup(each.value, "loadbalancer"), "health_check", {}), "enabled", true)
        interval            = lookup(lookup(lookup(each.value, "loadbalancer"), "health_check", {}), "interval", null)
        path                = lookup(lookup(lookup(each.value, "loadbalancer"), "health_check", {}), "path", null)
        port                = lookup(lookup(lookup(each.value, "loadbalancer"), "health_check", {}), "port", null)
        protocol            = lookup(lookup(lookup(each.value, "loadbalancer"), "health_check", {}), "protocol", null)
        timeout             = lookup(lookup(lookup(each.value, "loadbalancer"), "health_check", {}), "timeout", null)
        healthy_threshold   = lookup(lookup(lookup(each.value, "loadbalancer"), "health_check", {}), "healthy_threshold", null)
        unhealthy_threshold = lookup(lookup(lookup(each.value, "loadbalancer"), "health_check", {}), "unhealthy_threshold", null)
        matcher             = lookup(lookup(lookup(each.value, "loadbalancer"), "health_check", {}), "matcher", null)
    }

    lifecycle {
        ignore_changes  = []
    }
}

resource "aws_route53_record" "domain_aliases" {
    for_each    = local.map_of_domains_to_create
    zone_id     = data.aws_route53_zone.service[each.key].zone_id
    name        = lookup(each.value, "name")
    type        = lookup(each.value, "type", "A")

    alias {
        name                    = data.aws_lb.cluster[lookup(each.value, "service_key")].dns_name
        zone_id                 = data.aws_lb.cluster[lookup(each.value, "service_key")].zone_id
        evaluate_target_health  = true
    }
}

resource "aws_lb_listener_rule" "domain_forward" {
    for_each        = local.map_of_domains
    listener_arn    = data.aws_lb_listener.cluster[lookup(each.value, "service_key")].arn

    action {
        type             = "forward"
        target_group_arn = aws_lb_target_group.targets[lookup(each.value, "service_key")].arn
    }

    condition {
        field = "host-header"
        values = [lookup(each.value, "lb_route_matches")]
    }
}

resource "aws_lb_listener_certificate" "service_certs" {
    for_each        = local.map_of_certs_to_add
    certificate_arn = lookup(each.value, "cert")
    listener_arn    = data.aws_lb_listener.cluster[lookup(each.value, "service_key")].arn
}

