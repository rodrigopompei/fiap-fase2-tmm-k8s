# ---------------------------------------------------------------------------
# Conta e região
# ---------------------------------------------------------------------------
output "aws_account_id" {
  description = "ID da conta AWS onde a infraestrutura foi criada."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "Região AWS."
  value       = var.aws_region
}

output "lab_role_arn" {
  description = "ARN da role usada pelo control plane, pelos nodes e pelos pods."
  value       = local.lab_role_arn
}

# ---------------------------------------------------------------------------
# Rede
# ---------------------------------------------------------------------------
output "vpc_id" {
  description = "ID da VPC."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Subnets públicas (ALB internet-facing)."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Subnets privadas (nodes, RDS, ElastiCache)."
  value       = module.network.private_subnet_ids
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------
output "cluster_name" {
  description = "Nome do cluster EKS."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint da API do Kubernetes."
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group dos nodes, referenciado pelas regras de ingress do RDS e do Redis."
  value       = module.eks.cluster_security_group_id
}

output "update_kubeconfig_command" {
  description = "Comando para apontar o kubectl para este cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------
output "ecr_registry_url" {
  description = "Host do registry, usado no docker login."
  value       = module.ecr.registry_url
}

output "ecr_repository_urls" {
  description = "Mapa repositório => URL, pronto para o campo image dos Deployments."
  value       = module.ecr.repository_urls
}

output "docker_login_command" {
  description = "Comando de autenticação do Docker no ECR."
  value       = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${module.ecr.registry_url}"
}

# ---------------------------------------------------------------------------
# Banco de dados
# ---------------------------------------------------------------------------
output "db_address" {
  description = "Hostname da instância RDS."
  value       = module.database.address
}

output "db_port" {
  description = "Porta do PostgreSQL."
  value       = module.database.port
}

output "db_master_username" {
  description = "Usuário master do PostgreSQL."
  value       = module.database.master_username
}

output "db_master_password" {
  description = "Senha master do PostgreSQL. Leia com: terraform output -raw db_master_password."
  value       = module.database.master_password
  sensitive   = true
}

output "db_initial_database" {
  description = "Banco criado junto com a instância."
  value       = module.database.initial_database_name
}

output "db_additional_databases" {
  description = "Bancos que ainda precisam ser criados via SQL, pois o RDS só cria um no provisionamento. Use scripts/init-databases.sh."
  value       = local.additional_database_names
}

# ---------------------------------------------------------------------------
# Cache
# ---------------------------------------------------------------------------
output "redis_address" {
  description = "Hostname do Redis. Nulo quando enable_cache = false."
  value       = var.enable_cache ? module.cache[0].address : null
}

# ---------------------------------------------------------------------------
# Mensageria
# ---------------------------------------------------------------------------
output "sqs_queue_url" {
  description = "URL da fila SQS. Vai no env AWS_SQS_URL e no queueURL do ScaledObject do KEDA."
  value       = module.messaging.queue_url
}

output "sqs_dlq_url" {
  description = "URL da dead-letter queue."
  value       = module.messaging.dlq_url
}

output "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB. Vai no env AWS_DYNAMODB_TABLE."
  value       = module.messaging.table_name
}

# ---------------------------------------------------------------------------
# Segredos
# ---------------------------------------------------------------------------
output "managed_secret_names" {
  description = "Segredos cujo valor o Terraform controla."
  value       = local.managed_secret_names
}

output "external_secret_names" {
  description = "Segredos criados vazios, preenchidos em runtime."
  value       = local.external_secret_names
}

# ---------------------------------------------------------------------------
# Valores para os manifests do Kubernetes
#
# Os manifests em K8s/ foram escritos com valores da Fase 2 (região us-east-2,
# outra conta, ARNs de roles IRSA). Este output reúne o que precisa ser
# substituído antes do kubectl apply.
# ---------------------------------------------------------------------------
output "manifest_values" {
  description = "Valores a substituir nos manifests de K8s/ antes do apply."
  value = {
    aws_region                 = var.aws_region
    aws_account_id             = data.aws_caller_identity.current.account_id
    cluster_name               = module.eks.cluster_name
    ecr_registry               = module.ecr.registry_url
    aws_sqs_url                = module.messaging.queue_url
    aws_dynamodb_table         = module.messaging.table_name
    secretproviderclass_region = var.aws_region

    # Sem IRSA: remova as anotações eks.amazonaws.com/role-arn de todos os
    # ServiceAccounts. Uma anotação apontando para role inexistente faz o AWS
    # SDK falhar no AssumeRoleWithWebIdentity, sem fallback para a role do node.
    service_account_role_annotation = "REMOVER"

    # O TriggerAuthentication do KEDA precisa de identityOwner: operator, para
    # que o KEDA use as credenciais do próprio operator (role do node) em vez
    # de esperar uma role IRSA no ServiceAccount do workload.
    keda_identity_owner = "operator"
  }
}
