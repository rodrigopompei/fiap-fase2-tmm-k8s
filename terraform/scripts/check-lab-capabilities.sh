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
# Um "output" invalido no profile faz TODO comando sem --output falhar na
# formatacao, apos a chamada ter tido sucesso. O sintoma engana: parece falta de
# permissao em massa. Verificamos isso explicitamente para dar o diagnostico certo.
echo "Configuracao do AWS CLI"
cli_version=$(aws --version 2>&1 | head -1)
echo "          ${cli_version}"
configured_output=$(aws configure get output 2>/dev/null || true)

if out_probe=$(aws sts get-caller-identity 2>&1); then
  ok "formato de saida padrao utilizavel${configured_output:+ (output = ${configured_output})}"
else
  case "$out_probe" in
    *"Unknown output type"*)
      bad "o profile define 'output = ${configured_output}', invalido nesta versao do AWS CLI"
      echo "          Corrija com: aws configure set output json"
      ;;
    *)
      bad "sts:GetCallerIdentity sem --output falhou:"
      echo "$out_probe" | head -2 | sed 's/^/          /'
      ;;
  esac
fi

case "$cli_version" in
  aws-cli/1.*)
    note "AWS CLI v1: use AWS_DEFAULT_REGION (a v1 ignora AWS_REGION) e nao use --no-cli-pager" ;;
esac
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

# Sonda de iam:CreateOpenIDConnectProvider, a permissao que IRSA exige.
# Enviamos uma URL invalida de proposito: a IAM autoriza ANTES de validar a
# entrada, entao um "AccessDenied" prova a falta de permissao sem criar nada, e
# um erro de validacao provaria que a permissao existe.
if oidc_create=$(aws iam create-open-id-connect-provider \
     --url "http://invalid-not-https.example.com" \
     --client-id-list sts.amazonaws.com \
     --thumbprint-list 0000000000000000000000000000000000000000 2>&1); then
  note "iam:CreateOpenIDConnectProvider PERMITIDO - IRSA viavel (enable_irsa = true)"
  note "ATENCAO: um provider OIDC pode ter sido criado; verifique e remova"
else
  case "$oidc_create" in
    *AccessDenied*|*not\ authorized*|*explicit\ deny*)
      ok "iam:CreateOpenIDConnectProvider negado - mantenha enable_irsa = false" ;;
    *)
      note "iam:CreateOpenIDConnectProvider: permissao existe (falhou na validacao da entrada)"
      note "IRSA pode ser viavel; avalie enable_irsa = true" ;;
  esac
fi

if oidc_out=$(aws iam list-open-id-connect-providers --output json 2>&1); then
  ok "iam:ListOpenIDConnectProviders permitido (leitura)"
else
  case "$oidc_out" in
    *AccessDenied*|*not\ authorized*|*explicit\ deny*|*AuthorizationError*)
      note "iam:ListOpenIDConnectProviders negado - IRSA indisponivel, mantenha enable_irsa = false" ;;
    *)
      note "iam:ListOpenIDConnectProviders falhou por outro motivo - inconclusivo:"
      echo "$oidc_out" | head -2 | sed 's/^/          /' ;;
  esac
fi
echo

# --------------------------------------------------------------------------
echo "Servicos usados pela stack"

# O --output json e explicito de proposito. Se o profile tiver um "output"
# invalido para esta versao do CLI (ex: "output = none", que existe na v2 mas
# nao na v1), todo comando sem --output falha na FORMATACAO, depois de a chamada
# ter tido sucesso. Sem isso, a sonda acusaria falta de permissao inexistente.
probe() {
  local label="$1"; shift
  if "$@" --output json >/dev/null 2>&1; then
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
