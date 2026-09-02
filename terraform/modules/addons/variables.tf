variable "cluster_name" {
  description = "Nome do cluster EKS, passado ao AWS Load Balancer Controller."
  type        = string
}

variable "aws_region" {
  description = "Região AWS, passada ao AWS Load Balancer Controller."
  type        = string
}

variable "vpc_id" {
  description = "VPC do cluster, passada ao AWS Load Balancer Controller."
  type        = string
}

variable "enable_secrets_store_csi_driver" {
  description = "Instala o Secrets Store CSI Driver e o provider da AWS."
  type        = bool
  default     = true
}

variable "enable_aws_load_balancer_controller" {
  description = "Instala o AWS Load Balancer Controller."
  type        = bool
  default     = true
}

variable "enable_keda" {
  description = "Instala o KEDA."
  type        = bool
  default     = true
}

variable "keda_namespace" {
  description = "Namespace do KEDA. Precisa bater com o TriggerAuthentication do analytics-service."
  type        = string
  default     = "keda"
}

# Versões nulas resolvem para a mais recente do repositório. Fixe-as antes de
# entregar o trabalho: é o que garante que o apply de amanhã instale
# exatamente o que você validou hoje.
variable "secrets_store_csi_driver_version" {
  description = "Versão do chart secrets-store-csi-driver. Nulo usa a mais recente."
  type        = string
  default     = null
}

variable "secrets_store_csi_provider_aws_version" {
  description = "Versão do chart secrets-store-csi-driver-provider-aws. Nulo usa a mais recente."
  type        = string
  default     = null
}

variable "aws_load_balancer_controller_version" {
  description = "Versão do chart aws-load-balancer-controller. Nulo usa a mais recente."
  type        = string
  default     = null
}

variable "keda_version" {
  description = "Versão do chart keda. Nulo usa a mais recente."
  type        = string
  default     = null
}

variable "helm_timeout" {
  description = "Timeout em segundos para cada helm release."
  type        = number
  default     = 600
}
