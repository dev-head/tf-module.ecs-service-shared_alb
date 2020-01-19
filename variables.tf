
variable "tags" {
    description = "Optional, Map of tags to apply to resources."
    type        = map(any)
    default     = {}
}

variable "services" {
    description = "Required, Map of Service configuration object."
    type = map(object({
        name                        = string
        tags                        = map(any)
        ecr_scan_on_push            = bool
        ecs_cluster_name            = string
        deploy_max_percent          = number
        deploy_min_healthy_percent  = number
        deployment_type             = string
        num_services                = number
        log_retention_days          = number
        log_group_name              = string
        scheduling_strategy         = string
        network_mode                = string
        ipc_mode                    = string
        pid_mode                    = string
        domains                = map(object({
            name        = string
            type        = string
            zone_name   = string
            zone_id     = string
            create_dns  = bool
            cert_arns   = list(string)
            lb_route_matches = string
        }))
        loadbalancer    = object({
            enabled                 = bool
            listener_arn            = string
            deregistration_delay    = number
            vpc_id                  = string
            port                    = number
            protocol                = string
            slow_start              = number
            target_type             = string
            stickiness              = object({
                type            = string
                cookie_duration = string
                enabled         = string
            })
            health_check    = object({
                enabled             = bool
                interval            = number
                path                = string
                port                = string
                protocol            = string
                timeout             = number
                healthy_threshold   = number
                unhealthy_threshold = number
                matcher             = number
            })
        })
        ports   = object({
            host_port           = string
            container_port      = string
            protocol_port       = string

        })
        volumes = list(object({
            name    = string
            host_path   = string
            docker_volume_configuration = object({
                scope           = string
                autoprovision   = bool
                driver          = string
                driver_opts     = map(any)
                labels          = map(any)
            })
        }))
        task_definition_enabled             = bool
        task_definition_containers_path     = string
        task_placement_strategies          = list(object({
            type    = string
            field   = string
        }))
        task_definition_vars                = map(any)
        placement_constraints   = list(object({
            type        = string
            expression  = string
        }))
        service_iam_policy_statements   = list(object({
            actions         = list(string)
            not_actions     = list(string)
            effect          = string
            resources       = list(string)
            not_resources   = list(string)
            principals      = list(object({
                type        = string
                identifiers = list(string)
            }))
            not_principals  = list(object({
                type        = string
                identifiers = list(string)
            }))
            conditions  = list(object({
                test    = string
                variable = string
                    values  = list(string)
            }))
        }))

    }))
}