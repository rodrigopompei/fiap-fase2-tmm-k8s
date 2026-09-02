variable "name" {
  description = "Nome (cluster_id) do cluster ElastiCache."
  type        = string
}

variable "vpc_id" {
  description = "VPC onde o security group é criado."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets privadas do subnet group."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups autorizados a conectar no Redis. Normalmente apenas o SG dos nodes do EKS."
  type        = list(string)
}

variable "node_type" {
  description = "Tipo do node. O Learner Lab restringe os tipos permitidos; cache.t3.micro é segura."
  type        = string
  default     = "cache.t3.micro"
}

variable "engine_version" {
  description = "Versão do Redis."
  type        = string
  default     = "7.1"
}

variable "parameter_group_name" {
  description = "Parameter group. Precisa corresponder à família da engine_version escolhida."
  type        = string
  default     = "default.redis7"
}

variable "port" {
  description = "Porta do Redis."
  type        = number
  default     = 6379
}

variable "apply_immediately" {
  description = "Aplica mudanças na hora em vez de esperar a janela de manutenção."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos do módulo."
  type        = map(string)
  default     = {}
}
