variable "queue_name" {
  description = "Nome da fila SQS principal."
  type        = string
}

variable "visibility_timeout_seconds" {
  description = "Tempo que uma mensagem fica invisível depois de recebida. Precisa ser maior que o tempo de processamento do analytics-service."
  type        = number
  default     = 30
}

variable "message_retention_seconds" {
  description = "Retenção de mensagens na fila principal (60 a 1209600)."
  type        = number
  default     = 345600
}

variable "receive_wait_time_seconds" {
  description = "Long polling. Valores > 0 reduzem chamadas vazias de ReceiveMessage e, com isso, o custo do SQS."
  type        = number
  default     = 10

  validation {
    condition     = var.receive_wait_time_seconds >= 0 && var.receive_wait_time_seconds <= 20
    error_message = "receive_wait_time_seconds precisa estar entre 0 e 20."
  }
}

variable "enable_dlq" {
  description = "Cria uma dead-letter queue e associa via redrive policy."
  type        = bool
  default     = true
}

variable "max_receive_count" {
  description = "Tentativas de entrega antes de mover a mensagem para a DLQ."
  type        = number
  default     = 5
}

variable "dlq_message_retention_seconds" {
  description = "Retenção de mensagens na DLQ. O padrão é o máximo (14 dias) para dar tempo de investigar."
  type        = number
  default     = 1209600
}

variable "table_name" {
  description = "Nome da tabela DynamoDB de eventos."
  type        = string
}

variable "table_hash_key" {
  description = "Atributo de partition key da tabela (tipo string)."
  type        = string
  default     = "event_id"
}

variable "billing_mode" {
  description = "PAY_PER_REQUEST ou PROVISIONED. PAY_PER_REQUEST não gera custo quando a tabela está ociosa."
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.billing_mode)
    error_message = "billing_mode precisa ser PAY_PER_REQUEST ou PROVISIONED."
  }
}

variable "point_in_time_recovery_enabled" {
  description = "Habilita PITR na tabela (custo adicional por GB)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos do módulo."
  type        = map(string)
  default     = {}
}
