locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(var.extra_tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })

  ecr_repository_names = [for service in var.services : "${var.ecr_repository_prefix}/${service}"]

  # Uma instância RDS, três bancos. auth_service_db é criado junto com a
  # instância; os outros dois vêm do scripts/init-databases.sh.
  auth_database_name      = "auth_service_db"
  flag_database_name      = "flag_service_db"
  targeting_database_name = "targeting_service_db"

  additional_database_names = [
    local.flag_database_name,
    local.targeting_database_name,
  ]

  db_credentials = "${module.database.master_username}:${module.database.master_password}"
  db_host_port   = "${module.database.address}:${module.database.port}"

  # ------------------------------------------------------------------------
  # Segredos
  #
  # Os nomes precisam bater exatamente com os objectName dos
  # SecretProviderClass em K8s/*/secretproviderclass.yaml — é assim que o CSI
  # Driver localiza cada segredo.
  #
  # A lista é estática de propósito: o Terraform proíbe valores sensíveis (ou
  # derivados deles) como chave de for_each, então derivar os nomes do mapa de
  # valores faria o plan falhar.
  # ------------------------------------------------------------------------
  managed_secret_names = concat(
    [
      "auth-service/DATABASE_URL",
      "auth-service/MASTER_KEY",
      "flag-service/DATABASE_URL",
      "targeting-service/DATABASE_URL",
    ],
    var.enable_cache ? ["evaluation-service/REDIS_URL"] : [],
  )

  managed_secret_values = merge(
    {
      "auth-service/DATABASE_URL"      = "postgres://${local.db_credentials}@${local.db_host_port}/${local.auth_database_name}"
      "auth-service/MASTER_KEY"        = random_password.auth_master_key.result
      "flag-service/DATABASE_URL"      = "postgres://${local.db_credentials}@${local.db_host_port}/${local.flag_database_name}"
      "targeting-service/DATABASE_URL" = "postgres://${local.db_credentials}@${local.db_host_port}/${local.targeting_database_name}"
    },
    var.enable_cache ? { "evaluation-service/REDIS_URL" = module.cache[0].redis_url } : {},
  )

  # A SERVICE_API_KEY só existe depois que o auth-service está no ar: ela é
  # emitida por POST /auth/admin/keys. O Terraform cria o segredo vazio e a
  # preenche em runtime (ver scripts/create-service-api-key.sh).
  external_secret_names = [
    "evaluation-service/SERVICE_API_KEY",
  ]
}
