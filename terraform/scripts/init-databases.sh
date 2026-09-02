#!/usr/bin/env bash
#
# Cria os bancos adicionais e aplica os schemas na instância RDS.
#
# Por que um script e não Terraform: o RDS cria apenas um banco no
# provisionamento, e a instância fica em subnet privada, inalcançável da sua
# máquina. O provider postgresql do Terraform precisaria de rota até lá.
#
# A solução é rodar o psql de dentro do cluster, num pod efêmero que já está
# na VPC e cujo tráfego é aceito pelo security group do RDS.
#
# Pré-requisitos: terraform apply concluído e kubectl apontando para o cluster.
#
#   ./scripts/init-databases.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${TF_DIR}/.." && pwd)"

PG_IMAGE="${PG_IMAGE:-postgres:16-alpine}"

echo "Lendo outputs do Terraform em ${TF_DIR}"
DB_HOST=$(terraform -chdir="$TF_DIR" output -raw db_address)
DB_PORT=$(terraform -chdir="$TF_DIR" output -raw db_port)
DB_USER=$(terraform -chdir="$TF_DIR" output -raw db_master_username)
DB_PASS=$(terraform -chdir="$TF_DIR" output -raw db_master_password)
DB_INITIAL=$(terraform -chdir="$TF_DIR" output -raw db_initial_database)

echo "  host:  ${DB_HOST}:${DB_PORT}"
echo "  user:  ${DB_USER}"
echo "  banco: ${DB_INITIAL} (criado pelo Terraform)"
echo

# Executa psql num pod efêmero dentro do cluster.
# stdout do comando é preservado; o ruído do kubectl vai para stderr.
psql_in_cluster() {
  local database="$1"
  shift
  kubectl run "pg-init-$$-${RANDOM}" \
    --rm --restart=Never --quiet --image="$PG_IMAGE" \
    --env="PGPASSWORD=${DB_PASS}" \
    --command -- \
    psql --host="$DB_HOST" --port="$DB_PORT" --username="$DB_USER" \
         --dbname="$database" --no-password "$@"
}

# Variante que recebe SQL pela entrada padrão (para os arquivos init.sql).
psql_stdin() {
  local database="$1"
  kubectl run "pg-init-$$-${RANDOM}" \
    --rm --restart=Never --quiet -i --image="$PG_IMAGE" \
    --env="PGPASSWORD=${DB_PASS}" \
    --command -- \
    psql --host="$DB_HOST" --port="$DB_PORT" --username="$DB_USER" \
         --dbname="$database" --no-password --file=- -v ON_ERROR_STOP=1
}

database_exists() {
  local database="$1"
  psql_in_cluster "$DB_INITIAL" --tuples-only --no-align \
    --command="SELECT 1 FROM pg_database WHERE datname='${database}'" 2>/dev/null |
    tr -d '[:space:]' | grep -q '^1$'
}

# O PostgreSQL não tem CREATE DATABASE IF NOT EXISTS, então verificamos antes.
create_database() {
  local database="$1"
  if database_exists "$database"; then
    echo "  banco ${database} já existe, mantendo"
  else
    echo "  criando banco ${database}"
    psql_in_cluster "$DB_INITIAL" --command="CREATE DATABASE \"${database}\""
  fi
}

apply_schema() {
  local database="$1"
  local sql_file="$2"

  if [ ! -f "$sql_file" ]; then
    echo "  AVISO: ${sql_file} não encontrado, pulando schema de ${database}"
    return
  fi

  echo "  aplicando $(basename "$(dirname "$(dirname "$sql_file")")")/db/init.sql em ${database}"
  psql_stdin "$database" < "$sql_file"
}

echo "Etapa 1/2 - criando os bancos adicionais"
for database in $(terraform -chdir="$TF_DIR" output -json db_additional_databases | tr -d '[]" ' | tr ',' ' '); do
  create_database "$database"
done
echo

# Os schemas em */db/init.sql usam CREATE TABLE IF NOT EXISTS e
# CREATE OR REPLACE FUNCTION, então reaplicar é seguro.
echo "Etapa 2/2 - aplicando os schemas"
apply_schema "$DB_INITIAL"           "${REPO_ROOT}/auth-service/db/init.sql"
apply_schema "flag_service_db"       "${REPO_ROOT}/flag-service/db/init.sql"
apply_schema "targeting_service_db"  "${REPO_ROOT}/targeting-service/db/init.sql"
echo

echo "Bancos prontos."
