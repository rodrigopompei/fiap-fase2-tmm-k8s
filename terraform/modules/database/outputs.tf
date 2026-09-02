output "address" {
  description = "Hostname da instância RDS."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Porta do PostgreSQL."
  value       = aws_db_instance.this.port
}

output "endpoint" {
  description = "Endpoint no formato host:porta."
  value       = aws_db_instance.this.endpoint
}

output "master_username" {
  description = "Usuário master."
  value       = aws_db_instance.this.username
}

output "master_password" {
  description = "Senha master gerada pelo Terraform."
  value       = random_password.master.result
  sensitive   = true
}

output "initial_database_name" {
  description = "Banco criado junto com a instância."
  value       = aws_db_instance.this.db_name
}

output "security_group_id" {
  description = "Security group da instância."
  value       = aws_security_group.this.id
}
