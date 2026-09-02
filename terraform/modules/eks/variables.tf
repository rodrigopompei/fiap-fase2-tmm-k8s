variable "cluster_name" {
  description = "Nome do cluster EKS."
  type        = string
}

variable "cluster_version" {
  description = "Versão do Kubernetes. Confirme que ainda está em suporte padrão com: aws eks describe-addon-versions."
  type        = string
  default     = "1.33"
}

variable "cluster_role_arn" {
  description = "ARN da IAM role assumida pelo control plane. No Learner Lab, a ARN da LabRole."
  type        = string
}

variable "node_role_arn" {
  description = "ARN da IAM role de instância dos nodes. No Learner Lab é também a LabRole, e é dela que os pods herdam credenciais AWS na ausência de IRSA."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets onde ficam as ENIs do control plane e os nodes. Normalmente as privadas."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "O EKS exige subnets em pelo menos 2 Availability Zones."
  }
}

variable "endpoint_public_access" {
  description = "Expõe o endpoint da API publicamente. Necessário para rodar kubectl/helm de fora da VPC."
  type        = bool
  default     = true
}

variable "endpoint_private_access" {
  description = "Habilita o endpoint privado da API dentro da VPC."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDRs autorizados a alcançar o endpoint público. Restrinja ao seu IP para reduzir exposição."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "authentication_mode" {
  description = "Modo de autenticação do cluster: API, API_AND_CONFIG_MAP ou CONFIG_MAP."
  type        = string
  default     = "API_AND_CONFIG_MAP"

  validation {
    condition     = contains(["API", "API_AND_CONFIG_MAP", "CONFIG_MAP"], var.authentication_mode)
    error_message = "authentication_mode precisa ser API, API_AND_CONFIG_MAP ou CONFIG_MAP."
  }
}

variable "enabled_cluster_log_types" {
  description = "Tipos de log do control plane enviados ao CloudWatch (api, audit, authenticator, controllerManager, scheduler). Cada um gera custo de ingestão."
  type        = list(string)
  default     = []
}

variable "instance_types" {
  description = "Tipos de instância dos nodes. O Learner Lab restringe as famílias permitidas; t3.medium é uma escolha segura."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "capacity_type" {
  description = "ON_DEMAND ou SPOT. SPOT reduz o custo em ~70%, mas os nodes podem ser recuperados pela AWS no meio de uma demo."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "capacity_type precisa ser ON_DEMAND ou SPOT."
  }
}

variable "disk_size" {
  description = "Tamanho do disco EBS de cada node, em GB."
  type        = number
  default     = 20
}

variable "desired_size" {
  description = "Quantidade desejada de nodes."
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Quantidade mínima de nodes."
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Quantidade máxima de nodes."
  type        = number
  default     = 4
}

variable "enable_irsa" {
  description = "Cria o OIDC provider para IRSA. Mantenha false no Learner Lab: iam:CreateOpenIDConnectProvider é negado pelos guardrails."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos do módulo."
  type        = map(string)
  default     = {}
}
