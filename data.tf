
locals {

    services_default    = var.services

    #
    # @use: datasets that isolate a load balancer fronted service (http) and a daemon/job service (daemon)
    #       which allows us to support multiple of each and dynamically configure requirements were needed (eg: lb)
    #
    services_http   = {for key,value in var.services : key => value if value["loadbalancer"]["enabled"] == true}
    services_daemon = {for key,value in var.services : key => value if value["loadbalancer"]["enabled"] == false}

    #
    # need to null out zone_id|zone_name to allow looking up based on one or the other.
    # @use: dataset to create new route53 records from
    #
    list_of_domains_to_create   = flatten([
        for service_key,service in local.services_http: [
            for domain_key,config in service.domains: merge(config, {
                service_key = service_key
                index       = domain_key
                zone_id     = lookup(config, "zone_id", "") != "" ? lookup(config, "zone_id") : null
                zone_name   = lookup(config, "zone_name", "") != "" ? lookup(config, "zone_name") : null
            }) if config.create_dns
        ]
    ])
    map_of_domains_to_create    =  { for item in local.list_of_domains_to_create : "${item.service_key}.${item.index}" => item }

    list_of_domains   = flatten([
        for service_key,service in local.services_http: [
            for domain_key,config in service.domains: merge(config, {
                service_key = service_key
                index       = domain_key
                zone_id     = lookup(config, "zone_id", "") != "" ? lookup(config, "zone_id") : null
                zone_name   = lookup(config, "zone_name", "") != "" ? lookup(config, "zone_name") : null
            })
        ]
    ])
    map_of_domains    =  { for item in local.list_of_domains : "${item.service_key}.${item.index}" => item }

    #
    # @use: dataset to add ssl certs to loadbalancer records from
    #
    list_of_certs_to_add    = flatten([
        for service_key,service in local.services_http: [
            for domain_key,config in service.domains: [
                for cert_key,cert in config.cert_arns: {
                    cert        = cert
                    index       = cert_key
                    domain_key  = domain_key
                    service_key = service_key
                }
            ]
        ]
    ])
    map_of_certs_to_add         =  { for item in local.list_of_certs_to_add : "${item.service_key}-${item.domain_key}.${item.index}" => item }
}

data "aws_region" "current" {}

data "aws_lb_listener" "cluster" {
    for_each    = local.services_http
    arn         = lookup(lookup(each.value, "loadbalancer"), "listener_arn")
}

data "aws_lb" "cluster" {
    for_each    = local.services_http
    arn         = data.aws_lb_listener.cluster[each.key].load_balancer_arn
}

data "aws_route53_zone" "service" {
    for_each    = local.map_of_domains_to_create
    name        = lookup(each.value, "zone_name", null)
    zone_id     = lookup(each.value, "zome_id", null)
}

data "aws_ecs_cluster" "service" {
    for_each            = var.services
    cluster_name        = format("%s", lookup(each.value, "ecs_cluster_name"))
}

data "aws_iam_policy_document" "service_role_assume" {
    for_each    = var.services

    statement {
        sid       = "ServiceAllow"
        effect    = "Allow"
        actions   = ["sts:AssumeRole"]
        principals {
            identifiers = ["ec2.amazonaws.com", "ecs.amazonaws.com"]
            type = "Service"
        }
    }
}

data "aws_iam_policy_document" "service_role_policy" {
    for_each    = var.services

    statement {
        sid     = "ECRAccess"
        effect  = "Allow"
        actions = [
            "ecr:GetAuthorizationToken",
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetDownloadUrlForLayer",
            "ecr:GetRepositoryPolicy",
            "ecr:DescribeRepositories",
            "ecr:ListImages",
            "ecr:DescribeImages",
            "ecr:BatchGetImage"
        ]
        resources = [
            format("%s", aws_ecr_repository.service[each.key].arn),
            format("%s/*", aws_ecr_repository.service[each.key].arn)
        ]
    }

    statement {
        sid     = "EC2Access"
        actions = [
            "Tag:get*",
            "ec2:Describe*",
        ]
        resources = ["*"]
    }
}

data "aws_iam_policy_document" "service_role_policy_compiled" {
    for_each    = var.services
    source_json = data.aws_iam_policy_document.service_role_policy[each.key].json

    dynamic "statement" {
        for_each = lookup(each.value, "service_iam_policy_statements", null)

        content {
            actions         = lookup(statement.value, "actions", null)
            not_actions     = lookup(statement.value, "not_actions", null)
            effect          = lookup(statement.value, "effect", null)
            resources       = lookup(statement.value, "resources", null)
            not_resources   = lookup(statement.value, "not_resources", null)

            dynamic "condition" {
                for_each    = lookup(statement.value, "conditions", null)
                content {
                    test        = lookup(condition.value, "test", null)
                    variable    = lookup(condition.value, "variable", null)
                    values      = lookup(condition.value, "values", null)
                }
            }

            dynamic "principals" {
                for_each    = lookup(statement.value, "principals", null)
                content {
                    type        = lookup(principals.value, "type", null)
                    identifiers = lookup(principals.value, "identifiers", null)
                }
            }

             dynamic "not_principals" {
                for_each    = lookup(statement.value, "not_principals", null)
                content {
                    type        = lookup(not_principals.value, "type", null)
                    identifiers = lookup(not_principals.value, "identifiers", null)
                }
            }
        }
    }
}