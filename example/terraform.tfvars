#
# Define variables
#

tags    = {
    Project         = "example-api"
    Environment     = "Production"
    Description     = "Example API Service"
    ManagedBy       = "terraform"
}

services = {
    landing-pages = {
        name                        = "example-api"
        tags                        = {
            ServiceType = "http"
        }
        ecr_scan_on_push            = true
        ecs_cluster_name            = "example-ecs-cluster"
        deploy_max_percent          = 200
        deploy_min_healthy_percent  = 75
        deployment_type             = "ECS"
        num_services                = 1
        log_retention_days          = 30
        log_group_name              = "example-api"
        scheduling_strategy         = "REPLICA"
        network_mode                = "bridge"
        ipc_mode                    = "none"
        pid_mode                    = "task"
        ports                       = {
            host_port        = ""
            container_port   = "80"
            protocol_port    = "tcp"
        }
        volumes                             = []
        task_definition_enabled             = true
        task_definition_containers_path     = "containers.json"
        task_placement_strategies           = [{type = "spread", field = "instanceId"}]
        placement_constraints               = []
        task_definition_vars                = {
            task_name       = "example-api"
            container_image = "kitematic/hello-world-nginx:latest"
        }
        service_iam_policy_statements   = []
        domains    = {
            example_ecr = {
                name        = "example-ecr"
                type        = "A"
                zone_name   = "example.net"
                zone_id     = ""
                create_dns  = true
                cert_arns   = []
                lb_route_matches = "*example-ecr.example.net"
            }
        }

        loadbalancer    = {
            enabled                 = true
            listener_arn            = "arn:aws:elasticloadbalancing:%REGION%:%ACCOUNT_ID%:listener/app/%LISTENER_ID%"
            deregistration_delay    = 120
            port                    = 80
            target_type             = "instance"
            protocol                = "HTTP"
            slow_start              = 30
            vpc_id                  = "vpc-%VPC_ID%"
            stickiness  = {
                type            = "lb_cookie"
                cookie_duration = 86400
                enabled         = false
            }
            health_check = {
                enabled             = true
                interval            = 61
                path                = "/error.html"
                port                = "traffic-port"
                protocol            = "HTTP"
                timeout             = 60
                healthy_threshold   = 2
                unhealthy_threshold = 5
                matcher             = 200
            }
        }
    }
}