variable "aws_region" {
  description = "Região onde o bucket de state e a tabela de lock são criados. Precisa ser a mesma configurada no backend."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Nome do projeto, usado para compor o nome do bucket."
  type        = string
  default     = "toggle-master"
}

variable "state_bucket_name" {
  description = "Nome explícito do bucket de state. Nulo gera <project>-tfstate-<account_id>."
  type        = string
  default     = null
}

variable "state_key" {
  description = "Caminho do arquivo de state dentro do bucket."
  type        = string
  default     = "toggle-master/lab/terraform.tfstate"
}

variable "lock_table_name" {
  description = "Nome da tabela DynamoDB de lock."
  type        = string
  default     = "toggle-master-tflock"
}

variable "noncurrent_version_expiration_days" {
  description = "Dias após os quais versões antigas do state são removidas."
  type        = number
  default     = 90
}
