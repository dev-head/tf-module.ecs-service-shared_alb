ECS Service :: Shared Application Load Balancer
===============================================

Description
-----------
Terraform module to create a group of ECS services that are attached to a provided Application load balancer. 

*[Note]* this project is focused on a specific use case for ECS hosting of a service. 

Architectural Components 
------------------------
* Route53 
* ECS EC2 Cluster 
* Application Load Balancer
* ECS Service with one or more domains pointed to the ALB 


Links 
-----
* [Example](./example/) found in `./example`
