data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# IAM: reutilizamos a LabRole em vez de criar roles
#
# O Learner Lab nega iam:CreateRole. A LabRole é a única role assumível
# disponível, e ela serve a três papéis ao mesmo tempo aqui:
#   - role do control plane do EKS
#   - role de instância dos nodes
#   - origem das credenciais AWS dos pods (via IMDS, no lugar de IRSA)
#
# Se iam:GetRole também estiver bloqueado, informe var.lab_role_arn e o data
# source deixa de ser avaliado.
# ---------------------------------------------------------------------------
data "aws_iam_role" "lab" {
  count = var.lab_role_arn == null ? 1 : 0

  name = var.lab_role_name
}

locals {
  lab_role_arn = coalesce(var.lab_role_arn, one(data.aws_iam_role.lab[*].arn))
}

# Chave mestra do auth-service. special = false porque ela viaja em um header
# Authorization: Bearer, onde caracteres especiais só criam problema.
resource "random_password" "auth_master_key" {
  length  = 48
  special = false
}

# ---------------------------------------------------------------------------
# Rede
# ---------------------------------------------------------------------------
module "network" {
  source = "./modules/network"

  name_prefix        = local.name_prefix
  cluster_name       = var.cluster_name
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Cluster EKS
# ---------------------------------------------------------------------------
module "eks" {
  source = "./modules/eks"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_role_arn = local.lab_role_arn
  node_role_arn    = local.lab_role_arn

  subnet_ids          = module.network.private_subnet_ids
  public_access_cidrs = var.cluster_public_access_cidrs

  instance_types = var.node_instance_types
  capacity_type  = var.node_capacity_type
  desired_size   = var.node_desired_size
  min_size       = var.node_min_size
  max_size       = var.node_max_size

  enable_irsa = var.enable_irsa

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Registry de imagens
# ---------------------------------------------------------------------------
module "ecr" {
  source = "./modules/ecr"

  repository_names = local.ecr_repository_names

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Banco de dados
#
# Instância única compartilhada por auth, flag e targeting. Os schemas em
# */db/init.sql não referenciam owners, então um master user atende os três.
# ---------------------------------------------------------------------------
module "database" {
  source = "./modules/database"

  identifier = "${local.name_prefix}-postgres"
  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  # Somente os nodes do EKS alcançam a porta 5432.
  allowed_security_group_ids = [module.eks.cluster_security_group_id]

  engine_version        = var.db_engine_version
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  initial_database_name = local.auth_database_name
  master_username       = var.db_master_username

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Cache
# ---------------------------------------------------------------------------
module "cache" {
  source = "./modules/cache"
  count  = var.enable_cache ? 1 : 0

  name       = "${local.name_prefix}-redis"
  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  allowed_security_group_ids = [module.eks.cluster_security_group_id]
  node_type                  = var.cache_node_type

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Mensageria e persistência de eventos
# ---------------------------------------------------------------------------
module "messaging" {
  source = "./modules/messaging"

  queue_name                 = var.sqs_queue_name
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  table_name                 = var.dynamodb_table_name

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Segredos
# ---------------------------------------------------------------------------
module "secrets" {
  source = "./modules/secrets"

  managed_secret_names  = local.managed_secret_names
  managed_secret_values = local.managed_secret_values
  external_secret_names = local.external_secret_names

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Add-ons do cluster
#
# Depende dos providers helm/kubernetes, que por sua vez dependem do endpoint
# do cluster. Por isso o primeiro apply precisa ser feito em duas fases (ver
# providers.tf e o README).
# ---------------------------------------------------------------------------
module "addons" {
  source = "./modules/addons"
  count  = var.enable_addons ? 1 : 0

  cluster_name = module.eks.cluster_name
  aws_region   = var.aws_region
  vpc_id       = module.network.vpc_id

  enable_aws_load_balancer_controller = var.enable_aws_load_balancer_controller
  enable_keda                         = var.enable_keda
  enable_secrets_store_csi_driver     = var.enable_secrets_store_csi_driver
}

# ---------------------------------------------------------------------------
# ArgoCD: GitOps contínuo
# ---------------------------------------------------------------------------
module "argocd" {
  source = "./modules/argocd"

  enable_argocd = var.enable_argocd
}
