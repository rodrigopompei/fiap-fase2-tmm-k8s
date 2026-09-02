# ---------------------------------------------------------------------------
# SQS + DynamoDB
#
# O evaluation-service publica eventos na fila; o analytics-service os consome
# e grava no DynamoDB. O KEDA lê a profundidade da fila para escalar o worker,
# por isso o queue_url é exportado: ele vai direto no ScaledObject.
# ---------------------------------------------------------------------------
resource "aws_sqs_queue" "dlq" {
  count = var.enable_dlq ? 1 : 0

  name                      = "${var.queue_name}-dlq"
  message_retention_seconds = var.dlq_message_retention_seconds

  tags = merge(var.tags, {
    Name = "${var.queue_name}-dlq"
  })
}

resource "aws_sqs_queue" "this" {
  name                       = var.queue_name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds

  # Sem DLQ, uma mensagem que falha no processamento reaparece na fila
  # indefinidamente e mantém o KEDA escalando o worker sem necessidade.
  redrive_policy = var.enable_dlq ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = var.max_receive_count
  }) : null

  tags = merge(var.tags, {
    Name = var.queue_name
  })
}

resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = var.billing_mode
  hash_key     = var.table_hash_key

  attribute {
    name = var.table_hash_key
    type = "S"
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery_enabled
  }

  tags = merge(var.tags, {
    Name = var.table_name
  })
}
