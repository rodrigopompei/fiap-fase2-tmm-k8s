#!/usr/bin/env bash
#
# Verifica, com chamadas somente leitura, se a sessão atual do AWS Academy
# Learner Lab suporta o que esta stack Terraform assume.
#
# Rode com o laboratório iniciado e as credenciais exportadas, ANTES do
# primeiro terraform apply. Os guardrails do Learner Lab mudam entre versões do
# curso, então confirmar vale mais que confiar na documentação.
#
#   ./scripts/check-lab-capabilities.sh
#
set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
LAB_ROLE="${LAB_ROLE_NAME:-LabRole}"

pass=0
fail=0
warn=0

ok()   { printf '  \033[0;32mOK\033[0m      %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  \033[0;31mFALHA\033[0m   %s\n' "$1"; fail=$((fail + 1)); }
note() { printf '  \033[0;33mATENCAO\033[0m %s\n' "$1"; warn=$((warn + 1)); }

echo
echo "Verificando capacidades da conta na regiao ${REGION}"
echo

# --------------------------------------------------------------------------
echo "Identidade"
if identity=$(aws sts get-caller-identity --output json 2>&1); then
  account=$(echo "$identity" | grep -o '"Account": *"[^"]*"' | cut -d'"' -f4)
  arn=$(echo "$identity" | grep -o '"Arn": *"[^"]*"' | cut -d'"' -f4)
  ok "autenticado na conta ${account}"
  echo "          ${arn}"
  case "$arn" in
    *voclabs*|*LabRole*)
      ok "identidade compativel com AWS Academy Learner Lab" ;;
    *)
      note "identidade nao parece ser do Learner Lab; os guardrails podem ser outros" ;;
  esac
else
  bad "sts:GetCallerIdentity falhou - inicie o laboratorio e exporte as credenciais"
  echo "$identity" | sed 's/^/          /'
  exit 1
fi
echo

# --------------------------------------------------------------------------
echo "IAM (esperado: LabRole legivel, criacao de roles negada)"
if role_arn=$(aws iam get-role --role-name "$LAB_ROLE" --query 'Role.Arn' --output text 2>/dev/null); then
  ok "${LAB_ROLE} encontrada: ${role_arn}"
else
  bad "nao foi possivel ler ${LAB_ROLE} (iam:GetRole bloqueado ou role ausente)"
  echo "          Contorne informando lab_role_arn no terraform.tfvars"
fi

# Sonda de escrita: tenta criar uma role descartavel e a remove em seguida.
# A trust policy precisa ser VALIDA, senao a IAM responde MalformedPolicyDocument
# e nao da para distinguir "sem permissao" de "documento invalido".
PROBE_ROLE="tf-capability-probe"
PROBE_POLICY='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

if probe_out=$(aws iam create-role --role-name "$PROBE_ROLE" \
     --assume-role-policy-document "$PROBE_POLICY" \
     2>&1); then
  note "iam:CreateRole PERMITIDO - voce pode habilitar IRSA (enable_irsa = true)"
  if aws iam delete-role --role-name "$PROBE_ROLE" >/dev/null 2>&1; then
    ok "role de teste ${PROBE_ROLE} removida"
  else
    bad "remova manualmente a role ${PROBE_ROLE}: aws iam delete-role --role-name ${PROBE_ROLE}"
  fi
else
  case "$probe_out" in
    *AccessDenied*|*not\ authorized*|*explicit\ deny*|*AuthorizationError*)
      ok "iam:CreateRole negado, como esperado - a stack usa ${LAB_ROLE} e nao cria roles" ;;
    *EntityAlreadyExists*)
      note "a role ${PROBE_ROLE} sobrou de uma execucao anterior; remova-a e rode de novo" ;;
    *)
      note "iam:CreateRole falhou por outro motivo - resultado inconclusivo:"
      echo "$probe_out" | head -2 | sed 's/^/          /' ;;
  esac
fi

if aws iam list-open-id-connect-providers >/dev/null 2>&1; then
  ok "iam:ListOpenIDConnectProviders permitido (leitura)"
else
  note "iam:ListOpenIDConnectProviders negado - IRSA indisponivel, mantenha enable_irsa = false"
fi
echo

# --------------------------------------------------------------------------
echo "Servicos usados pela stack"
probe() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    ok "$label"
  else
    bad "$label"
  fi
}

probe "eks:ListClusters"           aws eks list-clusters --region "$REGION"
probe "ec2:DescribeVpcs"           aws ec2 describe-vpcs --region "$REGION" --max-items 1
probe "ec2:DescribeAvailabilityZones" aws ec2 describe-availability-zones --region "$REGION"
probe "ecr:DescribeRepositories"   aws ecr describe-repositories --region "$REGION" --max-items 1
probe "rds:DescribeDBInstances"    aws rds describe-db-instances --region "$REGION" --max-items 1
probe "elasticache:DescribeCacheClusters" aws elasticache describe-cache-clusters --region "$REGION"
probe "sqs:ListQueues"             aws sqs list-queues --region "$REGION"
probe "dynamodb:ListTables"        aws dynamodb list-tables --region "$REGION"
probe "secretsmanager:ListSecrets" aws secretsmanager list-secrets --region "$REGION" --max-results 1
probe "s3:ListBuckets"             aws s3api list-buckets
echo

# --------------------------------------------------------------------------
echo "Tipos de instancia (o Learner Lab restringe as familias permitidas)"
for instance_type in t3.medium t3.small; do
  if aws ec2 describe-instance-type-offerings --region "$REGION" \
       --filters "Name=instance-type,Values=${instance_type}" \
       --query 'InstanceTypeOfferings[0].InstanceType' --output text 2>/dev/null | grep -q "$instance_type"; then
    ok "${instance_type} disponivel na regiao"
  else
    bad "${instance_type} indisponivel na regiao"
  fi
done
note "A disponibilidade na regiao nao garante permissao: o guardrail do laboratorio"
note "so recusa o tipo no momento de criar o node group."
echo

# --------------------------------------------------------------------------
echo "Versoes do Kubernetes suportadas pelo EKS nesta regiao"
if versions=$(aws eks describe-addon-versions --region "$REGION" --addon-name vpc-cni \
                --query 'addons[0].addonVersions[0].compatibilities[].clusterVersion' \
                --output text 2>/dev/null); then
  echo "          ${versions}"
  note "Ajuste cluster_version no terraform.tfvars para uma das versoes acima"
else
  note "nao foi possivel listar versoes suportadas"
fi
echo

# --------------------------------------------------------------------------
printf 'Resultado: %d ok, %d falhas, %d avisos\n\n' "$pass" "$fail" "$warn"
if [ "$fail" -gt 0 ]; then
  echo "Ha falhas acima. Resolva-as antes do terraform apply: a stack depende"
  echo "desses servicos e um apply parcial deixa recursos orfaos gerando custo."
  exit 1
fi
echo "Ambiente compativel com a stack."
