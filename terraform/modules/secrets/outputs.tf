output "managed_secret_arns" {
  description = "Mapa nome => ARN dos segredos gerenciados pelo Terraform."
  value       = { for name, secret in aws_secretsmanager_secret.managed : name => secret.arn }
}

output "external_secret_arns" {
  description = "Mapa nome => ARN dos segredos preenchidos em runtime."
  value       = { for name, secret in aws_secretsmanager_secret.external : name => secret.arn }
}

output "all_secret_names" {
  description = "Todos os nomes de segredo criados pelo módulo."
  value       = concat(var.managed_secret_names, var.external_secret_names)
}
