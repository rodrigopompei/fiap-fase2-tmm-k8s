variable "identifier" {
  description = "Identificador da instância RDS."
  type        = string
}

variable "vpc_id" {
  description = "VPC onde o security group da instância é criado."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets privadas do subnet group. Precisa cobrir no mínimo 2 AZs."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "O RDS exige um subnet group com subnets em pelo menos 2 Availability Zones."
  }
}

variable "allowed_security_group_ids" {
  description = "Security groups autorizados a conectar na porta do PostgreSQL. Normalmente apenas o SG dos nodes do EKS."
  type        = list(string)
}

variable "engine_version" {
  description = "Versão do PostgreSQL. Pode ser apenas a major (ex: \"16\"), deixando a AWS escolher a minor mais recente."
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = "Classe da instância. O Learner Lab restringe as classes permitidas; db.t3.micro é segura."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Armazenamento inicial em GB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Limite do autoscaling de storage em GB. Use 0 para desabilitar."
  type        = number
  default     = 0
}

variable "storage_type" {
  description = "Tipo de volume EBS (gp2, gp3)."
  type        = string
  default     = "gp2"
}

variable "storage_encrypted" {
  description = "Criptografa o storage com a chave KMS padrão do RDS."
  type        = bool
  default     = true
}

variable "initial_database_name" {
  description = "Banco criado junto com a instância. Os demais precisam ser criados via SQL (ver scripts/init-databases.sh)."
  type        = string
}

variable "master_username" {
  description = "Usuário master do PostgreSQL. Não pode ser uma palavra reservada como \"postgres\" em algumas versões."
  type        = string
  default     = "toggle_master"
}

variable "port" {
  description = "Porta do PostgreSQL."
  type        = number
  default     = 5432
}

variable "multi_az" {
  description = "Habilita standby em outra AZ. Dobra o custo da instância."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Dias de retenção de backup automático. 0 desabilita os backups."
  type        = number
  default     = 1
}

variable "skip_final_snapshot" {
  description = "Pula o snapshot final ao destruir. true evita que um snapshot órfão continue gerando custo no laboratório."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Impede a exclusão da instância."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Aplica mudanças na hora em vez de esperar a janela de manutenção."
  type        = bool
  default     = true
}

variable "performance_insights_enabled" {
  description = "Habilita o Performance Insights (custo adicional)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos do módulo."
  type        = map(string)
  default     = {}
}
