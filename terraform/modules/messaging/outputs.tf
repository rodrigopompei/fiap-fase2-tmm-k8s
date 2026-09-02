output "queue_url" {
  description = "URL da fila. Vai no env AWS_SQS_URL dos serviços e no queueURL do ScaledObject do KEDA."
  value       = aws_sqs_queue.this.url
}

output "queue_arn" {
  description = "ARN da fila principal."
  value       = aws_sqs_queue.this.arn
}

output "queue_name" {
  description = "Nome da fila principal."
  value       = aws_sqs_queue.this.name
}

output "dlq_url" {
  description = "URL da dead-letter queue. Nulo quando enable_dlq = false."
  value       = var.enable_dlq ? aws_sqs_queue.dlq[0].url : null
}

output "dlq_arn" {
  description = "ARN da dead-letter queue. Nulo quando enable_dlq = false."
  value       = var.enable_dlq ? aws_sqs_queue.dlq[0].arn : null
}

output "table_name" {
  description = "Nome da tabela DynamoDB. Vai no env AWS_DYNAMODB_TABLE do analytics-service."
  value       = aws_dynamodb_table.this.name
}

output "table_arn" {
  description = "ARN da tabela DynamoDB."
  value       = aws_dynamodb_table.this.arn
}
