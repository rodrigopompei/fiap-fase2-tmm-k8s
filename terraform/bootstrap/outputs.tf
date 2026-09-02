output "state_bucket_name" {
  description = "Bucket S3 que armazena o state da stack principal."
  value       = aws_s3_bucket.state.id
}

output "lock_table_name" {
  description = "Tabela DynamoDB usada para lock de state."
  value       = aws_dynamodb_table.lock.name
}

output "backend_config_path" {
  description = "Arquivo de configuração parcial do backend gerado para a stack principal."
  value       = local_file.backend_config.filename
}

output "init_command" {
  description = "Comando para inicializar a stack principal com este backend."
  value       = "terraform -chdir=.. init -backend-config=backend.hcl"
}
