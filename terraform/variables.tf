# ---------------------------------------------------------------------------
# Geral
# ---------------------------------------------------------------------------
variable "aws_region" {
  description = "Região AWS. O AWS Academy Learner Lab só permite us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Nome do projeto, usado como prefixo em nomes e tags."
  type        = string
  default     = "toggle-master"
}

variable "environment" {
  description = "Nome do ambiente, usado em nomes e tags."
  type        = string
  default     = "lab"
}

variable "extra_tags" {
  description = "Tags adicionais aplicadas a todos os recursos."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# IAM
#
# O Learner Lab nega iam:CreateRole, iam:CreatePolicy e
# iam:CreateOpenIDConnectProvider. Não criamos nenhuma role: reutilizamos a
# LabRole pré-provisionada tanto para o control plane quanto para os nodes, e é
# dela que os pods herdam credenciais AWS via IMDS.
# ---------------------------------------------------------------------------
variable "lab_role_name" {
  description = "Nome da role pré-provisionada do Learner Lab, consultada via data source."
  type        = string
  default     = "LabRole"
}

variable "lab_role_arn" {
  description = "ARN da LabRole informada manualmente. Preencha se iam:GetRole também estiver bloqueado na sua sessão; nesse caso o data source é ignorado."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Rede
# ---------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Número de Availability Zones."
  type        = number
  default     = 3
}

variable "enable_nat_gateway" {
  description = "Cria NAT Gateway para as subnets privadas. Necessário para os nodes puxarem imagens do ECR."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Compartilha um único NAT Gateway entre todas as AZs. Economiza ~US$ 65/mês em relação a um por AZ."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# EKS
# ---------------------------------------------------------------------------
variable "cluster_name" {
  description = "Nome do cluster EKS."
  type        = string
  default     = "eks-tc3-lab-001"
}

variable "cluster_version" {
  description = "Versão do Kubernetes. Em 2026-09-01 a conta do laboratório oferecia 1.31 a 1.36 em us-east-1; 1.33 deixa margem de suporte sem ser a mais recente. Reconfirme com ./scripts/check-lab-capabilities.sh."
  type        = string
  default     = "1.33"
}

variable "node_instance_types" {
  description = "Tipos de instância dos nodes. O Learner Lab restringe as famílias permitidas; c7i-flex.large (usada na Fase 2) não é aceita."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND ou SPOT. SPOT reduz o custo em ~70% ao preço de nodes que podem ser recuperados pela AWS."
  type        = string
  default     = "ON_DEMAND"
}

variable "node_desired_size" {
  description = "Quantidade desejada de nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Quantidade mínima de nodes."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Quantidade máxima de nodes."
  type        = number
  default     = 4
}

variable "cluster_public_access_cidrs" {
  description = "CIDRs autorizados no endpoint público da API. Restrinja ao seu IP (ex: [\"203.0.113.4/32\"]) para reduzir exposição."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_irsa" {
  description = "Cria o OIDC provider para IRSA. Precisa continuar false no Learner Lab."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# ECR
# ---------------------------------------------------------------------------
variable "ecr_repository_prefix" {
  description = "Prefixo dos repositórios ECR."
  type        = string
  default     = "fiap-fase2"
}

variable "services" {
  description = "Microserviços do projeto. Define os repositórios ECR criados."
  type        = list(string)
  default = [
    "auth-service",
    "flag-service",
    "targeting-service",
    "evaluation-service",
    "analytics-service",
  ]
}

# ---------------------------------------------------------------------------
# Banco de dados
# ---------------------------------------------------------------------------
variable "db_instance_class" {
  description = "Classe da instância RDS."
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version" {
  description = "Versão do PostgreSQL. Aceita apenas a major (ex: \"16\")."
  type        = string
  default     = "16"
}

variable "db_allocated_storage" {
  description = "Armazenamento do RDS em GB."
  type        = number
  default     = 20
}

variable "db_master_username" {
  description = "Usuário master do PostgreSQL, compartilhado pelos três bancos."
  type        = string
  default     = "toggle_master"
}

# ---------------------------------------------------------------------------
# Cache
# ---------------------------------------------------------------------------
variable "enable_cache" {
  description = "Cria o ElastiCache Redis. Com false, a REDIS_URL não é gerada e o evaluation-service passa a depender do fallback para flag-service e targeting-service."
  type        = bool
  default     = true
}

variable "cache_node_type" {
  description = "Tipo do node ElastiCache."
  type        = string
  default     = "cache.t3.micro"
}

# ---------------------------------------------------------------------------
# Mensageria
# ---------------------------------------------------------------------------
variable "sqs_queue_name" {
  description = "Nome da fila SQS de eventos de avaliação."
  type        = string
  default     = "ToggleMasterQueue"
}

variable "sqs_visibility_timeout_seconds" {
  description = "Visibility timeout da fila."
  type        = number
  default     = 30
}

variable "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB de eventos."
  type        = string
  default     = "ToggleMasterAnalytics"
}

# ---------------------------------------------------------------------------
# Add-ons
# ---------------------------------------------------------------------------
variable "enable_addons" {
  description = "Instala os add-ons Helm. Mantenha false no primeiro apply (o cluster ainda não existe) e passe a true na segunda fase."
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

variable "enable_secrets_store_csi_driver" {
  description = "Instala o Secrets Store CSI Driver e o provider da AWS."
  type        = bool
  default     = true
}

variable "enable_argocd" {
  description = "Instala o ArgoCD para GitOps contínuo na cluster."
  type        = bool
  default     = false
}
