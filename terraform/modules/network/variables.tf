variable "name_prefix" {
  description = "Prefixo aplicado ao Name de todos os recursos de rede."
  type        = string
}

variable "cluster_name" {
  description = "Nome do cluster EKS. Usado na tag kubernetes.io/cluster/<nome> das subnets, obrigatória para a descoberta de subnets pelo AWS Load Balancer Controller."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR da VPC. Precisa ser no mínimo /20 para acomodar az_count subnets públicas e privadas."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr precisa ser um bloco CIDR IPv4 válido (ex: 10.0.0.0/16)."
  }
}

variable "az_count" {
  description = "Quantidade de Availability Zones. O EKS exige no mínimo 2."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "az_count precisa estar entre 2 e 4 (o EKS exige no mínimo 2 AZs)."
  }
}

variable "enable_nat_gateway" {
  description = "Cria NAT Gateway(s) para dar saída à internet às subnets privadas. Necessário para os nodes puxarem imagens do ECR e falarem com o control plane. Desligue apenas se colocar os nodes em subnets públicas."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Usa um único NAT Gateway compartilhado por todas as subnets privadas em vez de um por AZ. Reduz o custo em ~66% ao preço de perder redundância entre AZs."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos do módulo."
  type        = map(string)
  default     = {}
}
