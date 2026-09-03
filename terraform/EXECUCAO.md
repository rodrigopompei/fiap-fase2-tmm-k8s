# Log de execução — provisionamento do ToggleMaster com Terraform

Registro dos comandos efetivamente executados, na ordem, com o resultado real
de cada um. Serve como evidência de entrega e como roteiro para reproduzir o
ambiente do zero.

- **Data:** 2026-09-02
- **Conta AWS:** `056007986659` (AWS Academy Learner Lab)
- **Identidade:** `arn:aws:sts::056007986659:assumed-role/voclabs/user4914923=rodrigo.pompei@gmail.com`
- **Região:** `us-east-1`
- **Diretório de trabalho:** `terraform/`
- **Resultado final:** 66 recursos criados, cluster validado, 66 recursos destruídos

Todos os comandos assumem estas variáveis exportadas:

```bash
export AWS_PROFILE=fiapaws
export AWS_DEFAULT_REGION=us-east-1
export AWS_REGION=us-east-1
```

> **Duas pegadinhas do ambiente, ambas descobertas na prática:**
>
> 1. `AWS_PROFILE` é obrigatório — esta máquina não tem perfil `[default]`, e
>    sem ele o CLI responde `Unable to locate credentials`.
> 2. O AWS CLI aqui é a **v1**, que lê `AWS_DEFAULT_REGION` e **ignora**
>    `AWS_REGION` (essa só vale na v2 e nos SDKs). Exportar apenas `AWS_REGION`
>    produz `You must specify a region`. O Terraform não é afetado, pois recebe
>    a região por variável.

---

## Índice

- [Etapa 0 — Inventário do ambiente](#etapa-0--inventário-do-ambiente)
- [Etapa 1 — Credenciais](#etapa-1--credenciais)
- [Etapa 2 — Verificação dos guardrails do lab](#etapa-2--verificação-dos-guardrails-do-lab)
- [Etapa 3 — Validação estática](#etapa-3--validação-estática)
- [Etapa 4 — Plan contra a AWS real, sem criar nada](#etapa-4--plan-contra-a-aws-real-sem-criar-nada)
- [Etapa 5 — Bootstrap do backend remoto](#etapa-5--bootstrap-do-backend-remoto)
- [Etapa 6 — Init da stack principal](#etapa-6--init-da-stack-principal)
- [Etapa 7 — Apply](#etapa-7--apply)
- [Etapa 8 — Validação do ambiente provisionado](#etapa-8--validação-do-ambiente-provisionado)
- [Etapa 9 — Pós-apply](#etapa-9--pós-apply)
- [Etapa 10 — Destroy](#etapa-10--destroy)
- [Problemas encontrados e correções](#problemas-encontrados-e-correções)
- [Resumo de evidências](#resumo-de-evidências)

---

## Etapa 0 — Inventário do ambiente

```bash
which -a terraform aws kubectl helm
aws --version
snap list aws-cli
```

**Resultado:**

| Ferramenta | Versão |
|---|---|
| terraform | `/snap/bin/terraform` |
| aws | `aws-cli/1.45.46` Python/3.12.3 botocore/1.43.46 |
| kubectl | `/usr/bin/kubectl` |
| helm | `/usr/sbin/helm` |

**Achado:** o AWS CLI é a **v1**. A flag `--no-cli-pager`, usada em todos os
comandos do [README da raiz](../README.md), é exclusiva da v2 e falha com
`Unknown options: --no-cli-pager`.

---

## Etapa 1 — Credenciais

```bash
ls -la ~/.aws/

# Lista apenas os NOMES dos perfis, sem expor segredos
grep -hoP '^\[\K[^\]]+' ~/.aws/credentials ~/.aws/config | sort -u

# Valida o perfil do laboratório
AWS_PROFILE=fiapaws aws sts get-caller-identity
```

**Resultado:** perfil `fiapaws` válido, ARN contendo
`assumed-role/voclabs/...` — confirma Learner Lab.

```bash
# Correção de segurança: o arquivo estava 644 (legível por qualquer usuário)
chmod 600 ~/.aws/credentials
```

---

## Etapa 2 — Verificação dos guardrails do lab

```bash
./scripts/check-lab-capabilities.sh
```

**Resultado: 15 OK, 0 falhas.**

| Verificação | Resultado |
|---|---|
| `LabRole` existe e é legível | `arn:aws:iam::056007986659:role/LabRole` |
| `iam:CreateRole` | **negado** (`AccessDenied`) → IRSA inviável |
| `iam:ListOpenIDConnectProviders` | permitido (somente leitura) |
| eks, ec2, ecr, rds, elasticache, sqs, dynamodb, secretsmanager, s3 | todos acessíveis |
| Versões EKS em us-east-1 | `1.36 1.35 1.34 1.33 1.32 1.31` |

Essa etapa transforma a decisão `enable_irsa = false` de suposição em
evidência.

---

## Etapa 3 — Validação estática

```bash
terraform fmt -recursive
terraform fmt -check -recursive

terraform init -backend=false -input=false
terraform validate -json

terraform graph > /dev/null          # detecção de ciclos

cd bootstrap && terraform init -backend=false && terraform validate -json && cd ..

for f in scripts/*.sh; do bash -n "$f"; done
```

**Resultado:** `"valid": true, "error_count": 0, "warning_count": 0` nas duas
stacks; grafo sem ciclos; scripts sem erro de sintaxe.

---

## Etapa 4 — Plan contra a AWS real, sem criar nada

Para validar contra a AWS real **antes** de criar qualquer recurso, rodei numa
cópia temporária com state local (sem o backend S3):

```bash
cp -r terraform /tmp/tfplan
rm -f /tmp/tfplan/backend.tf
rm -rf /tmp/tfplan/bootstrap /tmp/tfplan/.terraform
cd /tmp/tfplan
terraform init -input=false
terraform plan -input=false -var 'enable_addons=false'
```

**Primeiro resultado: 2 erros** (ver [Problema 1](#1-invalid-for_each-argument)).
Após corrigir:

```bash
terraform plan -input=false -var 'enable_addons=false'   # 62 recursos
terraform plan -input=false                             # 66 recursos
rm -rf /tmp/tfplan
```

---

## Etapa 5 — Bootstrap do backend remoto

Primeira etapa que **cria recursos de verdade** (custo desprezível).

```bash
cd bootstrap
terraform init -input=false
terraform apply -auto-approve -input=false
cd ..
```

**Resultado:** `Apply complete! Resources: 7 added.`

| Output | Valor |
|---|---|
| `state_bucket_name` | `toggle-master-tfstate-056007986659` |
| `lock_table_name` | `toggle-master-tflock` |

---

## Etapa 6 — Init da stack principal

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init -reconfigure -backend-config=backend.hcl -input=false
```

`-reconfigure` é necessário porque a Etapa 3 inicializou o diretório com
`-backend=false`.

---

## Etapa 7 — Apply

```bash
terraform apply -auto-approve -input=false
```

**O que aconteceu de verdade:** a primeira execução foi feita em background e
criou **62 dos 66** recursos, terminando com exit 1 e **log vazio** (ver
[Problema 6](#6-saída-do-terraform-engolida-em-background)). Diagnóstico:

```bash
terraform state list | wc -l        # 67 entradas
terraform plan -detailed-exitcode   # Plan: 4 to add  → exit 2
```

Reexecutando em primeiro plano, os 4 recursos restantes revelaram **2 erros
reais** ([Problema 4](#4-acento-na-descrição-de-regra-de-security-group) e
[Problema 5](#5-colisão-de-serviceaccount-entre-os-charts-do-csi)). Após as
correções:

```bash
terraform fmt -recursive
terraform apply -auto-approve -input=false
terraform plan -detailed-exitcode
```

**Resultado final:** `No changes. Your infrastructure matches the
configuration.` (exit 0) — state convergido, zero drift.

### Outputs obtidos

| Output | Valor |
|---|---|
| `vpc_id` | `vpc-016f167a75691ae65` |
| `cluster_name` | `eks-tc3-lab-001` |
| `ecr_registry` | `056007986659.dkr.ecr.us-east-1.amazonaws.com` |
| `sqs_queue_url` | `https://sqs.us-east-1.amazonaws.com/056007986659/ToggleMasterQueue` |
| `sqs_dlq_url` | `https://sqs.us-east-1.amazonaws.com/056007986659/ToggleMasterQueue-dlq` |
| `dynamodb_table_name` | `ToggleMasterAnalytics` |
| `redis_address` | `toggle-master-lab-redis.bwpjre.0001.use1.cache.amazonaws.com` |
| `db_address` | `toggle-master-lab-postgres.cahtqxb1boe6.us-east-1.rds.amazonaws.com` |

> **`iam:PassRole` funcionou.** Era a única permissão do desenho que não podia
> ser testada sem gastar: o Learner Lab permitiu passar a `LabRole` ao EKS
> tanto como role do control plane quanto como role dos nodes.

---

## Etapa 8 — Validação do ambiente provisionado

```bash
aws eks update-kubeconfig --region us-east-1 --name eks-tc3-lab-001
kubectl get nodes -o wide
helm list -A
kubectl get pods -n kube-system
kubectl get pods -n keda
aws rds describe-db-instances --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceStatus,EngineVersion,DBInstanceClass]' --output table
aws secretsmanager list-secrets --query 'SecretList[].Name' --output text
aws ecr describe-repositories --query 'repositories[].repositoryName' --output text
```

### Nodes

```
NAME                           STATUS   VERSION
ip-10-0-132-226.ec2.internal   Ready    v1.33.13-eks-cb19647
ip-10-0-145-43.ec2.internal    Ready    v1.33.13-eks-cb19647
```

### Helm releases

| Release | Namespace | Chart | Status |
|---|---|---|---|
| `aws-load-balancer-controller` | kube-system | `aws-load-balancer-controller-3.5.0` | deployed |
| `csi-secrets-store` | kube-system | `secrets-store-csi-driver-1.6.0` | deployed |
| `secrets-provider-aws` | kube-system | `secrets-store-csi-driver-provider-aws-3.1.3` | deployed |
| `keda` | keda | `keda-2.20.2` | deployed |

Todos os pods `Running`: 2 réplicas do ALB Controller, o DaemonSet do CSI
driver (3/3 por node), o DaemonSet do provider AWS (1/1 por node) e os 3 pods
do KEDA.

### Camada de dados

| Recurso | Estado |
|---|---|
| RDS `toggle-master-lab-postgres` | `available`, PostgreSQL **16.13**, `db.t3.micro` |
| Segredos criados | 6 (`auth-service/DATABASE_URL`, `auth-service/MASTER_KEY`, `flag-service/DATABASE_URL`, `targeting-service/DATABASE_URL`, `evaluation-service/REDIS_URL`, `evaluation-service/SERVICE_API_KEY`) |
| Repositórios ECR | 5 (`fiap-fase2/*`) |

---

## Etapa 9 — Pós-apply

Passos que o Terraform deliberadamente não faz, e o motivo de cada um.

### 9.1 Bancos e schemas

O RDS cria apenas um banco no provisionamento, e a instância fica em subnet
privada, inalcançável da máquina local. O script roda o `psql` num pod efêmero
dentro do cluster:

```bash
./scripts/init-databases.sh
```

> **Status: não concluído nesta execução.** A primeira tentativa falhou com
> `--rm should only be used for attached containers`
> ([Problema 7](#7-kubectl-run---rm-exige---attach)). A correção foi aplicada ao
> script, mas o ambiente foi destruído antes de reexecutá-lo — **a correção
> permanece sem validação em execução real.**

### 9.2 Build e push das imagens

```bash
eval "$(terraform output -raw docker_login_command)"
REGISTRY=$(terraform output -raw ecr_registry_url)
TAG=1.0.0

for svc in auth-service flag-service targeting-service evaluation-service analytics-service; do
  (cd "../$svc" && \
   docker build -t "$REGISTRY/fiap-fase2/$svc:$TAG" . && \
   docker push "$REGISTRY/fiap-fase2/$svc:$TAG")
done
```

As tags são IMMUTABLE: incremente a versão a cada rebuild. **Não executado
nesta sessão.**

### 9.3 Ajustar os manifests

```bash
terraform output manifest_values
```

Três mudanças obrigatórias, detalhadas na
[seção 7 do README](README.md#7-ajustes-obrigatórios-nos-manifests):

1. Remover `eks.amazonaws.com/role-arn` de todos os `serviceaccount.yaml`
2. `identityOwner: keda` → `operator` no `keda-trigger-auth.yaml`
3. Atualizar região, conta, `queueURL` e imagens ECR

**Não executado nesta sessão.**

### 9.4 Deploy e SERVICE_API_KEY

```bash
kubectl apply -f ../K8s/auth-service/

ALB_DNS=$(kubectl get ingress auth-service -n auth-service \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

./scripts/create-service-api-key.sh "$ALB_DNS"
```

**Não executado nesta sessão.**

---

## Etapa 10 — Destroy

```bash
# O lock file dos providers divergiu entre execuções; reinicializar antes
terraform init -reconfigure -backend-config=backend.hcl -input=false

terraform destroy -auto-approve -input=false
```

**Resultado:** `Destroy complete! Resources: 66 destroyed.`

O cluster EKS levou 3m22s para ser removido; o total ficou em ~9 min.

### Verificação de que nada ficou faturando

```bash
terraform state list | wc -l                                     # 0
aws eks list-clusters --output text                              # vazio
aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier' --output text   # vazio
aws elasticache describe-cache-clusters --query 'CacheClusters[].CacheClusterId' --output text  # vazio
aws ec2 describe-nat-gateways --filter "Name=state,Values=available,pending" \
  --query 'NatGateways[].NatGatewayId' --output text             # vazio
aws ec2 describe-addresses --query 'Addresses[].PublicIp' --output text  # vazio
aws rds describe-db-snapshots --snapshot-type manual \
  --query 'DBSnapshots[].DBSnapshotIdentifier' --output text     # vazio
```

Todas as sete verificações retornaram vazio. Os únicos recursos remanescentes
são os da stack `bootstrap/` (bucket de state e tabela de lock), preservados de
propósito por `prevent_destroy` e com custo praticamente nulo.

O destroy limpo em uma passada é consequência de três escolhas feitas no
desenho: `force_delete` nos repositórios ECR, `skip_final_snapshot` no RDS e
`recovery_window_in_days = 0` nos segredos — sem o último, o nome do segredo
ficaria reservado por 7 dias e o apply seguinte falharia com
`InvalidRequestException`.

---

## Problemas encontrados e correções

Dez achados: cinco de código, três de ambiente e dois de premissa
documentada. Os de código estão corrigidos no repositório.

### 1. `Invalid for_each argument`

```
Error: Invalid for_each argument
  on modules/cache/main.tf line 37, in resource "aws_vpc_security_group_ingress_rule" "redis"
  on modules/database/main.tf line 37, in resource "aws_vpc_security_group_ingress_rule" "postgres"
```

**Causa:** as regras de ingress iteravam com `for_each` sobre IDs de security
group vindos do cluster EKS — desconhecidos no momento do plan. O `for_each`
exige as chaves do conjunto já no plan.

**Correção:** troca por `count`, que só precisa do *tamanho* da lista:

```hcl
count                        = length(var.allowed_security_group_ids)
referenced_security_group_id = var.allowed_security_group_ids[count.index]
```

**Lição:** `terraform validate` não detecta essa classe de erro. Só um `plan`
real detecta.

### 2. Sonda de IAM dando falso negativo

A primeira execução do `check-lab-capabilities.sh` reportou
`iam:ListOpenIDConnectProviders negado` e `iam:CreateRole inconclusivo` — ambos
bug do próprio script, que usava `--no-cli-pager`, inexistente no CLI v1. Os
comandos falhavam por sintaxe, não por permissão.

**Correção:** remoção da flag, classificação explícita do erro (distinguindo
`AccessDenied` de `MalformedPolicyDocument`) e uso de uma trust policy válida na
sonda — antes era `"Statement": []`, que a IAM rejeita como malformado,
produzindo um "negado" enganoso.

### 3. `cluster_version` desatualizada

O default era `1.32`. A consulta ao lab mostrou `1.31` a `1.36` disponíveis, com
`1.31` próxima do fim de suporte. Ajustado para **`1.33`** — o cluster subiu com
`v1.33.13-eks-cb19647`.

### 4. Acento na descrição de regra de security group

```
api error InvalidParameterValue: Invalid rule description. Valid descriptions
are strings less than 256 characters from the following set:
a-zA-Z0-9. _-:/()#,@[]+=&;{}!$*
```

**Causa:** `description = "Saída liberada"` nas regras de egress do RDS e do
Redis. O `í` está fora do conjunto aceito pela EC2.

**Correção:** `"Saida liberada"`. Vale para qualquer campo `description` de
regra de SG — as descrições do próprio security group não têm essa restrição.

### 5. Colisão de ServiceAccount entre os charts do CSI

```
Error: Unable to continue with install: ServiceAccount "secrets-store-csi-driver"
in namespace "kube-system" exists and cannot be imported into the current
release: invalid ownership metadata; annotation validation error: key
"meta.helm.sh/release-name" must equal "secrets-provider-aws": current value is
"csi-secrets-store"
```

**Causa:** o chart `secrets-store-csi-driver-provider-aws` **embute** o
`secrets-store-csi-driver` como subchart:

```yaml
dependencies:
- condition: secrets-store-csi-driver.install    # default: true
  name: secrets-store-csi-driver
```

Como o README original instala o driver separadamente, os dois releases
disputam o mesmo ServiceAccount.

**Correção:** desligar o subchart no release do provider, preservando os dois
releases explícitos:

```hcl
set {
  name  = "secrets-store-csi-driver.install"
  value = "false"
}
```

A alternativa seria instalar **apenas** o chart do provider e deixá-lo trazer o
driver — um release em vez de dois.

### 6. Saída do Terraform engolida em background

O primeiro apply, executado em background, gerou um log de **7 bytes**
(`EXIT=1`) apesar de ter criado 62 recursos. Um teste isolado confirmou:
`terraform version` em background imprime nada e retorna 0.

**Causa:** confinamento do snap quando o processo é desacoplado do terminal.
Não é bug do Terraform nem da stack.

**Contorno:** rodar `terraform apply`/`destroy` em primeiro plano. Ambos são
resumíveis — reexecutar continua de onde parou, e foi assim que o apply
convergiu. Para diagnosticar um apply cujo log se perdeu:

```bash
terraform state list | wc -l
terraform plan -detailed-exitcode     # 0 = convergido, 2 = há mudanças
```

### 7. `kubectl run --rm` exige `--attach`

```
error: --rm should only be used for attached containers
```

**Causa:** o `init-databases.sh` usava `kubectl run --rm --restart=Never` sem
anexar o container. O kubectl atual rejeita essa combinação.

**Correção:** adicionar `--attach`. **Não revalidado em execução real** — o
ambiente foi destruído antes.

### 8. `AWS_REGION` ignorado pelo AWS CLI v1

```
You must specify a region. You can also configure your region by running "aws configure".
```

**Causa:** o CLI v1 lê `AWS_DEFAULT_REGION`; `AWS_REGION` só vale na v2 e nos
SDKs. Não afeta o Terraform, que recebe a região por variável, nem os scripts
deste diretório, que passam `--region` explicitamente.

### 9. Apply em duas fases: premissa corrigida

A documentação inicial afirmava que o primeiro apply **exigia** duas fases, por
causa dos providers `helm`/`kubernetes` configurados a partir do endpoint do
cluster.

Na prática o plan passou em **uma única passada** (66 recursos) e o apply criou
tudo, inclusive os 4 charts Helm, sem `-target`. O Terraform não precisa
contatar o cluster para *planejar* um `helm_release`. A abordagem em duas fases
passou a ser documentada como **fallback**.

### 10. Valores sensíveis em `for_each`

O Terraform proíbe valores sensíveis (ou derivados deles) como chave de
`for_each`. Como as DATABASE_URLs derivam de `random_password`, iterar sobre o
mapa de valores falharia no plan. O módulo `secrets` recebe, por isso, **duas
entradas separadas**: uma lista estática de nomes (que alimenta o `for_each`) e
um mapa sensível de valores (usado apenas como atributo). Padrão validado em
teste isolado antes de ser adotado.

---

## Resumo de evidências

| Item | Resultado |
|---|---|
| Módulos Terraform | 8 (`network`, `eks`, `ecr`, `database`, `cache`, `messaging`, `secrets`, `addons`) |
| Arquivos `.tf` | 43 |
| `terraform fmt -check -recursive` | limpo |
| `terraform validate` (ambas as stacks) | `valid: true`, 0 erros, 0 avisos |
| `terraform graph` | sem ciclos |
| Guardrails verificados | 15 OK, 0 falhas |
| Bootstrap aplicado | 7 recursos |
| **Apply da stack principal** | **66 recursos criados** |
| `terraform plan` após o apply | `No changes` (exit 0), zero drift |
| Cluster EKS | `v1.33.13`, 2 nodes `Ready` |
| Add-ons Helm | 4 releases `deployed`, todos os pods `Running` |
| RDS | `available`, PostgreSQL 16.13 |
| Segredos / ECR | 6 segredos, 5 repositórios |
| **Destroy** | **66 recursos destruídos** |
| Recursos faturáveis remanescentes | nenhum (7 verificações vazias) |
| Bugs encontrados e corrigidos | 10 |

### O que ficou comprovado sobre o Learner Lab

- `iam:CreateRole` é **negado** → IRSA realmente inviável, `enable_irsa = false`
  é o único caminho.
- `iam:PassRole` da `LabRole` para o EKS é **permitido** → o cluster pode ser
  criado por Terraform passando a role pronta, e é isso que torna a abordagem
  viável onde o `eksctl` falha.
- A `LabRole` como role dos nodes é suficiente para os add-ons: ALB Controller,
  KEDA e o provider do Secrets Manager subiram e ficaram `Running` sem nenhuma
  anotação de IRSA.
- `t3.medium` e `db.t3.micro` são aceitos pelos guardrails.

### O que permanece sem validação

O caminho de aplicação — criação dos bancos adicionais, build/push das imagens,
ajuste dos manifests e deploy dos 5 microserviços — não foi executado. A
infraestrutura foi comprovada; a aplicação sobre ela, não.
