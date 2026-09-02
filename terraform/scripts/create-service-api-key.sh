#!/usr/bin/env bash
#
# Preenche o segredo evaluation-service/SERVICE_API_KEY.
#
# Esse valor não pode vir do Terraform: a chave é emitida pelo próprio
# auth-service em POST /auth/admin/keys, ou seja, só existe depois que o
# serviço está no ar. O Terraform cria o segredo vazio (com ignore_changes no
# secret_string, para não sobrescrever o valor real depois) e este script
# coloca o valor de verdade.
#
# Pré-requisitos: auth-service deployado, ALB respondendo.
#
#   ./scripts/create-service-api-key.sh <alb-dns>
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ALB_DNS="${1:-}"
if [ -z "$ALB_DNS" ]; then
  echo "uso: $0 <alb-dns>" >&2
  echo >&2
  echo "Descubra o DNS do ALB com:" >&2
  echo "  kubectl get ingress auth-service -n auth-service \\" >&2
  echo "    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'" >&2
  exit 1
fi

REGION=$(terraform -chdir="$TF_DIR" output -raw aws_region)
SECRET_NAME="evaluation-service/SERVICE_API_KEY"

echo "Lendo a MASTER_KEY do Secrets Manager"
MASTER_KEY=$(aws secretsmanager get-secret-value \
  --region "$REGION" \
  --secret-id "auth-service/MASTER_KEY" \
  --query SecretString --output text)

echo "Solicitando uma API key ao auth-service em ${ALB_DNS}"
RESPONSE=$(curl -sS -X POST "http://${ALB_DNS}/auth/admin/keys" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${MASTER_KEY}" \
  -d '{"name":"evaluation-service-key"}')

# A chave aparece apenas nesta resposta: o auth-service armazena só o hash
# SHA-256 dela. Se perder, é preciso emitir outra.
SERVICE_API_KEY=$(printf '%s' "$RESPONSE" | python3 -c 'import sys, json; print(json.load(sys.stdin)["key"])')

if [ -z "$SERVICE_API_KEY" ]; then
  echo "Não foi possível extrair a chave da resposta:" >&2
  echo "$RESPONSE" >&2
  exit 1
fi

echo "Gravando em ${SECRET_NAME}"
aws secretsmanager put-secret-value \
  --region "$REGION" \
  --secret-id "$SECRET_NAME" \
  --secret-string "$SERVICE_API_KEY" \
  >/dev/null

echo
echo "Pronto. Reinicie o evaluation-service para que o CSI Driver remonte o segredo:"
echo "  kubectl rollout restart deployment/evaluation-service -n evaluation-service"
