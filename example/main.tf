
terraform {
    required_version = ">= 0.12.18"
}

provider "aws" {
    region  = var.aws_region
    profile = var.aws_profile
    version = ">= 2.28.1"
}

module "ecs-service" {
    source      = "../"
    tags        = var.tags
    services    = var.services
}

output "tags" { value = module.ecs-service.tags }
output "map_of_domains_to_create" { value = module.ecs-service.map_of_domains_to_create }
