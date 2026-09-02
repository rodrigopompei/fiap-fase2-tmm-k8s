output "registry_url" {
  description = "Host do registry ECR da conta, usado no docker login."
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
}

output "repository_urls" {
  description = "Mapa nome do repositório => URL completa, pronta para usar no campo image do Deployment."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "repository_arns" {
  description = "Mapa nome do repositório => ARN."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}
