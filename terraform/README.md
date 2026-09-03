# Terraform — ToggleMaster (AWS Academy Learner Lab)

Infraestrutura como código para o projeto ToggleMaster, substituindo o
provisionamento manual via `eksctl` + AWS CLI descrito no
[README](../README.md) da raiz.

Esta stack é escrita **para o AWS Academy Learner Lab**. As restrições do
laboratório não são detalhe de configuração: elas mudam o desenho da solução,
principalmente na parte de IAM. A seção seguinte explica o que muda e por quê.

> **Provisionamento já validado end-to-end.** Em 2026-09-02 a stack foi
> aplicada na conta `056007986659`: 66 recursos criados, cluster EKS `v1.33.13`
> com 2 nodes `Ready`, os 4 add-ons Helm `deployed`, e em seguida 66 recursos
> destruídos sem deixar nada faturando. O log completo de comandos, resultados e
> os 10 bugs encontrados no caminho está em [EXECUCAO.md](EXECUCAO.md).

---

## Índice

1. [O que muda em relação à Fase 2](#1-o-que-muda-em-relação-à-fase-2)
2. [Arquitetura da stack](#2-arquitetura-da-stack)
3. [Pré-requisitos](#3-pré-requisitos)
4. [Bootstrap do backend remoto](#4-bootstrap-do-backend-remoto)
5. [Primeiro apply](#5-primeiro-apply)
6. [Depois do apply](#6-depois-do-apply)
7. [Ajustes obrigatórios nos manifests](#7-ajustes-obrigatórios-nos-manifests)
8. [Referência dos módulos](#8-referência-dos-módulos)
9. [Custo e ciclo de vida do laboratório](#9-custo-e-ciclo-de-vida-do-laboratório)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. O que muda em relação à Fase 2

### IRSA não existe no Learner Lab

Este é o ponto central. Toda a Fase 2 se apoia em IRSA: cada serviço tem seu
`irsa-trust-policy.json` em [AWS/](../AWS/) e um ServiceAccount anotado com
`eks.amazonaws.com/role-arn`. IRSA depende de duas permissões que os guardrails
do Learner Lab negam:

| Permissão | Para quê | Learner Lab |
|---|---|---|
| `iam:CreateOpenIDConnectProvider` | Registrar o OIDC issuer do cluster | Negada |
| `iam:CreateRole` / `iam:CreatePolicy` | Criar as 7 roles em `AWS/` | Negada |

Confirmado na conta `056007986659` em 2026-09-01: `iam:CreateRole` responde
`AccessDenied`, e a `LabRole` existe e é legível. Ou seja, `enable_irsa = false`
não é precaução — é o único caminho viável nesta conta.

**Como esta stack resolve:** os pods obtêm credenciais AWS pelo IMDS do node,
ou seja, herdam a role de instância. Como a `LabRole` é usada como role dos
nodes e é bastante permissiva, os pods alcançam Secrets Manager, SQS e
DynamoDB sem IRSA.

> **Cuidado que importa:** um ServiceAccount **anotado** com uma role
> inexistente é pior que um sem anotação. Com a anotação, o AWS SDK passa a
> preferir o token de web identity e falha no `AssumeRoleWithWebIdentity` —
> **sem fazer fallback** para a role do node. Por isso é obrigatório remover as
> anotações dos manifests (ver [seção 7](#7-ajustes-obrigatórios-nos-manifests)).

O módulo `eks` mantém o OIDC provider atrás de `enable_irsa`, desligado por
padrão, para que a mesma stack sirva numa conta sem guardrails.

### Demais diferenças

| Item | Fase 2 | Aqui | Motivo |
|---|---|---|---|
| Região | `us-east-2` | `us-east-1` | Learner Lab só permite us-east-1 |
| Instância dos nodes | `c7i-flex.large` | `t3.medium` | Famílias restritas pelo guardrail |
| Provisionamento | `eksctl` | Terraform | `eksctl` cria IAM roles via CloudFormation e falha |
| RDS | 3 instâncias | 1 instância, 3 bancos | Orçamento; os `init.sql` não referenciam owners |
| Redis | Com senha | Sem AUTH | `aws_elasticache_cluster` de nó único não suporta AUTH token |
| Segredos | Criados à mão | Gerados pelo Terraform | Senha e MASTER_KEY nunca passam por texto digitado |

---

## 2. Arquitetura da stack

```
terraform/
├── bootstrap/            state remoto (state LOCAL — roda uma vez, antes de tudo)
├── modules/
│   ├── network/          VPC, subnets públicas/privadas, IGW, NAT, tags do ALB
│   ├── eks/              cluster, managed node group, add-ons AWS, OIDC opcional
│   ├── ecr/              5 repositórios com tags IMMUTABLE e lifecycle policy
│   ├── database/         RDS PostgreSQL, subnet group, security group, senha
│   ├── cache/            ElastiCache Redis de nó único
│   ├── messaging/        SQS (+ DLQ) e tabela DynamoDB
│   ├── secrets/          Secrets Manager (gerenciados e preenchidos em runtime)
│   └── addons/           Helm: ALB Controller, KEDA, Secrets Store CSI + provider AWS
├── scripts/
│   ├── check-lab-capabilities.sh   valida os guardrails da sua sessão
│   ├── init-databases.sh           cria os bancos extras e aplica os schemas
│   └── create-service-api-key.sh   preenche o SERVICE_API_KEY
└── *.tf                  stack raiz que compõe os módulos
```

Nenhum módulo cria IAM role. A identidade entra como **variável**
(`cluster_role_arn`, `node_role_arn`), o que é justamente o que torna os
módulos reutilizáveis fora do laboratório.

---

## 3. Pré-requisitos

| Ferramenta | Versão | Nesta máquina |
|---|---|---|
| `terraform` | ≥ 1.5 | sim |
| `aws` CLI | v1 ou v2 | **v1** (`1.45.46`, via snap) |
| `kubectl` | — | sim |
| `helm` | — | sim (o Terraform chama o provider, não o binário) |
| `docker` | — | para build das imagens |

> **AWS CLI v1:** a flag `--no-cli-pager`, presente em todos os comandos do
> [README da raiz](../README.md), **não existe na v1** e faz o comando falhar
> com `Unknown options`. Remova-a ao reaproveitar aqueles comandos. A stack em
> si não é afetada: o `aws eks get-token` usado pelos providers `helm` e
> `kubernetes` funciona nas duas versões.

As credenciais do laboratório já estão no perfil **`fiapaws`** desta máquina.
Como não existe perfil `[default]`, selecione-o explicitamente:

```bash
export AWS_PROFILE=fiapaws
export AWS_REGION=us-east-1

aws sts get-caller-identity
# Arn deve conter assumed-role/voclabs/...
```

As credenciais expiram ao fim da sessão (~4 horas). Para renovar, copie o bloco
da aba **AWS Details > AWS CLI** no AWS Academy para `~/.aws/credentials`, sob o
cabeçalho `[fiapaws]` — mantendo o `aws_session_token`, que é obrigatório.

> Mantenha `~/.aws/credentials` com permissão `600`. O arquivo desta máquina
> estava `644` (legível por qualquer usuário do sistema) e foi corrigido.

Antes do primeiro apply, confirme que a sua sessão suporta o que a stack
assume. Os guardrails variam entre versões do curso, então essa verificação
vale mais que confiar na documentação:

```bash
cd terraform
./scripts/check-lab-capabilities.sh
```

O script faz apenas chamadas de leitura (mais um `create-role` que ele espera
falhar) e resume o que está permitido, quais versões de Kubernetes a região
oferece e se a `LabRole` é legível.

---

## 4. Bootstrap do backend remoto

Stack separada, com state **local**, porque é ela que cria a infraestrutura de
state da stack principal. Rode uma única vez por conta:

```bash
cd terraform/bootstrap
terraform init
terraform apply
```

Cria:

- bucket S3 versionado, criptografado (AES256) e com acesso público bloqueado
- tabela DynamoDB `toggle-master-tflock` para lock distribuído
- `../backend.hcl` com a configuração parcial do backend

O nome do bucket inclui o ID da conta, pois o namespace do S3 é global.

> O state guarda a senha do RDS e a MASTER_KEY em texto claro. É por isso que o
> bucket tem criptografia em repouso e bloqueio de acesso público, e que
> `*.tfstate` está no `.gitignore`.

---

## 5. Primeiro apply

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # revise os valores
terraform init -backend-config=backend.hcl
```

Um apply só:

```bash
terraform apply
```

Verificado em 2026-09-01 contra a conta `056007986659`: o `plan` completo passa
em uma única passada, com 66 recursos a criar e nenhum erro — mesmo com os
providers `helm` e `kubernetes` configurados a partir do endpoint do cluster,
que ainda não existe. O Terraform não precisa contatar o cluster para *planejar*
a criação de um `helm_release`, e no apply a ordem de dependência garante que o
cluster exista antes do primeiro uso do provider.

**Se o apply falhar na configuração dos providers** (mensagem do tipo
`Provider configuration cannot be unknown` ou erro de conexão ao configurar
`helm`/`kubernetes`), quebre em duas fases — o cluster passa a estar no state e
o plan seguinte resolve normalmente:

```bash
# Fase 1 — rede e cluster (~15 min, o control plane do EKS é lento)
terraform apply -target=module.network -target=module.eks

# Fase 2 — todo o resto
terraform apply
```

Alternativa equivalente: `terraform apply -var 'enable_addons=false'` primeiro
e depois `terraform apply`.

Aponte o `kubectl` para o cluster:

```bash
$(terraform output -raw update_kubeconfig_command)
kubectl get nodes
```

---

## 6. Depois do apply

### 6.1 Criar os bancos e aplicar os schemas

O RDS cria apenas um banco no provisionamento, e a instância fica em subnet
privada — inalcançável da sua máquina. O script roda o `psql` num pod efêmero
dentro do cluster, que já está na VPC e é aceito pelo security group do RDS:

```bash
./scripts/init-databases.sh
```

Cria `flag_service_db` e `targeting_service_db` e aplica os três `init.sql`. É
idempotente: os schemas usam `CREATE TABLE IF NOT EXISTS` e
`CREATE OR REPLACE FUNCTION`.

### 6.2 Build e push das imagens

```bash
eval "$(terraform output -raw docker_login_command)"
terraform output -json ecr_repository_urls
```

Para cada serviço (as tags são IMMUTABLE, então incremente a versão a cada
build):

```bash
REGISTRY=$(terraform output -raw ecr_registry_url)
TAG=1.0.0

cd ../auth-service
docker build -t "$REGISTRY/fiap-fase2/auth-service:$TAG" .
docker push "$REGISTRY/fiap-fase2/auth-service:$TAG"
```

### 6.3 Ajustar e aplicar os manifests

Ver [seção 7](#7-ajustes-obrigatórios-nos-manifests) — há mudanças
**obrigatórias** antes do `kubectl apply`.

### 6.4 Preencher o SERVICE_API_KEY

Esse valor não pode vir do Terraform: a chave é emitida pelo próprio
auth-service e só existe depois que ele está no ar. O Terraform cria o segredo
vazio (com `ignore_changes` no `secret_string`, para não sobrescrever depois) e
o script coloca o valor real:

```bash
ALB_DNS=$(kubectl get ingress auth-service -n auth-service \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

./scripts/create-service-api-key.sh "$ALB_DNS"
```

---

## 7. Ajustes obrigatórios nos manifests

Os manifests em [K8s/](../K8s/) carregam valores da Fase 2 (conta
`570814275471`, região `us-east-2`, ARNs de roles IRSA). O Terraform reúne os
valores novos em um output:

```bash
terraform output manifest_values
```

Três mudanças são obrigatórias para o ambiente funcionar:

**1. Remover as anotações de IRSA** de todos os `serviceaccount.yaml`
(`K8s/*/serviceaccount.yaml` e `K8s/base/alb-controller/serviceaccount.yaml`):

```yaml
# REMOVER estas duas linhas:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::570814275471:role/auth-service-secrets-role
```

Sem IRSA, a anotação faz o SDK falhar em vez de usar a role do node.

**2. Trocar o `identityOwner` do KEDA** em
[K8s/analytics-service/keda-trigger-auth.yaml](../K8s/analytics-service/keda-trigger-auth.yaml):

```yaml
spec:
  podIdentity:
    provider: aws
    identityOwner: operator   # era: keda
```

`operator` faz o KEDA usar as credenciais do próprio operator (a role do node),
em vez de esperar uma role IRSA no ServiceAccount do workload.

**3. Atualizar região, conta e URLs** — região `us-east-2` → `us-east-1` nos
`secretproviderclass.yaml` e no `scaledobject.yaml`; a `queueURL` do
`scaledobject.yaml` e as imagens ECR dos `deployment.yaml`, todas com os
valores de `terraform output manifest_values`.

Não aplique
[K8s/base/alb-controller/serviceaccount.yaml](../K8s/base/alb-controller/serviceaccount.yaml):
o chart Helm já cria esse ServiceAccount, sem anotação, pelo módulo `addons`.

Também note que o `auth-service/app` (secret JSON único) mencionado no README
da raiz não é usado: os `SecretProviderClass` leem
`auth-service/DATABASE_URL` e `auth-service/MASTER_KEY` separadamente, e é isso
que o Terraform cria.

---

## 8. Referência dos módulos

| Módulo | Cria | Variáveis que valem revisar |
|---|---|---|
| `network` | VPC, 3+3 subnets, IGW, NAT, route tables, tags do ALB | `single_nat_gateway`, `enable_nat_gateway`, `az_count` |
| `eks` | Cluster, node group, vpc-cni/coredns/kube-proxy | `cluster_version`, `instance_types`, `capacity_type`, `enable_irsa` |
| `ecr` | 5 repositórios | `image_tag_mutability`, `keep_last_n_images` |
| `database` | RDS PostgreSQL, SG, subnet group, senha aleatória | `instance_class`, `engine_version` |
| `cache` | ElastiCache Redis de nó único, SG | `node_type` |
| `messaging` | SQS + DLQ, tabela DynamoDB | `enable_dlq`, `visibility_timeout_seconds` |
| `secrets` | Segredos gerenciados e com placeholder | `recovery_window_in_days` |
| `addons` | ALB Controller, KEDA, CSI Driver + provider AWS | `*_version` (fixe antes de entregar) |

As versões dos charts Helm são `null` por padrão, o que resolve para a mais
recente. **Fixe-as antes de entregar o trabalho**: é o que garante que o apply
de amanhã instale exatamente o que você validou hoje.

---

## 9. Custo e ciclo de vida do laboratório

O crédito do Learner Lab é limitado e **a cobrança não para quando a sessão de
4 horas encerra**: ao fim da sessão as instâncias EC2 são paradas, mas o
control plane do EKS, o RDS, o NAT Gateway e o ElastiCache continuam ativos.

Estimativa com os padrões desta stack:

| Recurso | Aproximado |
|---|---|
| Control plane EKS | US$ 0,10/h (~US$ 2,40/dia) |
| 2× `t3.medium` | ~US$ 2,00/dia |
| NAT Gateway (1) | ~US$ 1,10/dia + tráfego |
| RDS `db.t3.micro` | ~US$ 0,45/dia |
| ElastiCache `cache.t3.micro` | ~US$ 0,40/dia |
| **Total** | **~US$ 6 a 7/dia** |

Contra um crédito de US$ 50, isso dá cerca de uma semana com a stack de pé.
Recomendações:

- **Destrua ao fim de cada dia de trabalho.** A stack recria em ~20 minutos.
- `node_capacity_type = "SPOT"` reduz o custo dos nodes em ~70%.
- `enable_cache = false` remove o ElastiCache; o evaluation-service tem
  fallback documentado para flag-service e targeting-service.
- `node_desired_size = 1` durante desenvolvimento.

```bash
terraform destroy
```

O destroy foi pensado para funcionar em laboratório: `force_delete` nos
repositórios ECR, `skip_final_snapshot` no RDS e
`recovery_window_in_days = 0` nos segredos — sem esse último, o nome do segredo
fica reservado por 7 dias e o apply seguinte falha com
`InvalidRequestException`.

O bucket de state tem `prevent_destroy`, então `bootstrap/` sobrevive ao
destroy da stack principal — que é o comportamento desejado.

---

## 10. Troubleshooting

**`InvalidClientTokenId` ou `ExpiredToken`**
A sessão do laboratório expirou. Reinicie o lab e exporte as credenciais novas
(incluindo `AWS_SESSION_TOKEN`).

**`Provider configuration cannot be unknown` / erro nos providers helm ou kubernetes**
O apply em passada única normalmente funciona (ver [seção 5](#5-primeiro-apply)),
mas se isso aparecer, quebre em duas fases:
`terraform apply -target=module.network -target=module.eks` e depois
`terraform apply`.

**`Unknown options: --no-cli-pager`**
Você está no AWS CLI v1 (é o caso desta máquina: `1.45.46`). Essa flag é
exclusiva da v2 e aparece em todos os comandos do [README da raiz](../README.md),
escrito para v2 em PowerShell. Basta removê-la; nada mais muda.

**`You must specify a region` mesmo com `AWS_REGION` exportado**
O AWS CLI v1 lê `AWS_DEFAULT_REGION` e ignora `AWS_REGION` (essa só vale na v2 e
nos SDKs). Exporte `AWS_DEFAULT_REGION=us-east-1`. O Terraform não é afetado.

**`terraform apply` termina com exit 1 e log vazio**
Acontece ao rodar o Terraform desacoplado do terminal (background): o
confinamento do snap engola stdout/stderr. Rode em primeiro plano. O apply é
resumível — para descobrir onde parou:

```bash
terraform state list | wc -l
terraform plan -detailed-exitcode    # 0 = convergido, 2 = há mudanças
```

**`Required plugins are not installed` / checksum do lock file**
Ocorre ao alternar entre `init -backend=false` e o backend S3. Rode
`terraform init -reconfigure -backend-config=backend.hcl`.

**`AccessDeniedException` em `iam:GetRole`**
Informe `lab_role_arn` no `terraform.tfvars`; o data source deixa de ser
avaliado.

**`InvalidParameterException: unsupported Kubernetes version`**
Rode `./scripts/check-lab-capabilities.sh` e ajuste `cluster_version`.

**Pods em `ContainerCreating` para sempre**
O Secrets Store CSI Driver não está pronto, ou o segredo não existe:

```bash
kubectl describe pod -n auth-service -l app=auth-service
kubectl get pods -n kube-system -l app=csi-secrets-store-provider-aws
```

**Pods com `AccessDenied` na AWS**
Provavelmente é a anotação de IRSA que sobrou no ServiceAccount
([seção 7](#7-ajustes-obrigatórios-nos-manifests)). Confirme de onde vêm as
credenciais:

```bash
kubectl get sa -n auth-service auth-service -o yaml   # não deve ter role-arn
kubectl exec -n auth-service deploy/auth-service -- env | grep AWS_
```

**Ingress criado mas sem ALB**
Tags de subnet ou permissão do controller. O módulo `network` já aplica as
tags; verifique os logs:

```bash
kubectl logs -n kube-system deploy/aws-load-balancer-controller
```

**`UnsupportedAvailabilityZoneException` no node group**
Alguma AZ da região não suporta o tipo de instância. Reduza `az_count` para 2
ou troque `node_instance_types`.
