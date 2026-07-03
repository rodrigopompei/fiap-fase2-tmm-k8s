# ToggleMaster — Guia de Deploy

Projeto de feature flags distribuído, composto por cinco microserviços rodando em EKS. Este documento descreve **em ordem** tudo o que precisa ser provisionado e por quê.

Observação: Esse passo a passo foi construido com base no meu ambiente criado de VPC e subnets publicas e privadas na AWS, caso pretenda usar esse documento como referencia atentar-se para trocar as informações que refere-se ao seu ambiente

Projeto da fase dois do curso de DevOps e Arquitetura cloud da FIAP

---

## Índice

1. [Arquitetura e Dependências](#1-arquitetura-e-dependências)
2. [Pré-requisitos](#2-pré-requisitos)
3. [Infraestrutura Base AWS](#3-infraestrutura-base-aws)
4. [Add-ons do Cluster EKS](#4-add-ons-do-cluster-eks)
   - 4.1 [OIDC Provider (IRSA)](#41-oidc-provider-irsa)
   - 4.2 [Secrets Store CSI Driver](#42-secrets-store-csi-driver)
   - 4.3 [AWS Load Balancer Controller](#43-aws-load-balancer-controller)
   - 4.4 [KEDA](#44-keda)
5. [auth-service](#5-auth-service)
6. [flag-service](#6-flag-service)
7. [targeting-service](#7-targeting-service)
8. [evaluation-service](#8-evaluation-service)
9. [analytics-service](#9-analytics-service)
10. [Verificação End-to-End](#10-verificação-end-to-end)

---

## 1. Arquitetura e Dependências

```
                        ┌──────────────┐
                        │  auth-service│  (Go, porta 8001, PostgreSQL)
                        └──────┬───────┘
               valida chave    │    valida chave
          ┌────────────────────┼────────────────────┐
          ▼                    ▼                    ▼
  ┌──────────────┐    ┌──────────────────┐  ┌──────────────────┐
  │  flag-service│    │targeting-service │  │evaluation-service│
  │(Python, 8002)│    │  (Python, 8003)  │  │   (Go, 8004)     │
  │  PostgreSQL  │    │   PostgreSQL     │  │  Redis + SQS     │
  └──────────────┘    └──────────────────┘  └────────┬─────────┘
                                                      │ publica evento
                                                      ▼
                                             ┌──────────────────┐
                                             │ analytics-service│
                                             │ (Python, 8005)   │
                                             │ SQS + DynamoDB   │
                                             └──────────────────┘
```

**Regra de dependência:** um microserviço só pode ser deployado depois que todos os serviços à sua esquerda/acima já estiverem saudáveis.

| Serviço            | Linguagem | Porta | Banco        | AWS extras         | Público |
|--------------------|-----------|-------|--------------|--------------------|---------|
| auth-service       | Go        | 8001  | PostgreSQL   | Secrets Manager    | Sim     |
| flag-service       | Python    | 8002  | PostgreSQL   | Secrets Manager    | Sim     |
| targeting-service  | Python    | 8003  | PostgreSQL   | Secrets Manager    | Sim     |
| evaluation-service | Go        | 8004  | —            | Secrets Manager, SQS | Sim  |
| analytics-service  | Python    | 8005  | —            | SQS, DynamoDB      | Não     |

---

## 2. Pré-requisitos

Antes de começar, garanta que as ferramentas abaixo estão instaladas e configuradas:

| Ferramenta    | Por quê é necessária |
|---------------|----------------------|
| `aws cli` v2  | Criar/gerenciar recursos AWS (ECR, RDS, IAM, SQS, DynamoDB...) |
| `eksctl`      | Criar e gerenciar o cluster EKS de forma declarativa |
| `kubectl`     | Aplicar manifests e inspecionar o cluster |
| `helm`        | Instalar add-ons no cluster (ALB Controller, KEDA) |
| `docker`      | Construir e publicar as imagens dos microserviços |
| `go` ≥ 1.21  | Build local (opcional se usar só Docker) |
| `python` ≥ 3.9| Build local (opcional se usar só Docker) |

Autentique o CLI na conta AWS:

```powershell
aws configure
# ou exporte AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN
aws sts get-caller-identity   # confirme que a conta correta está ativa
```

---

## 3. Infraestrutura Base AWS

### 3.1 Cluster EKS

> **Por quê:** O cluster é o ambiente de execução de todos os microserviços. Ele precisa existir antes de qualquer outra coisa.

O manifesto declarativo está em [K8s/k8s-cluster.yaml](K8s/k8s-cluster.yaml). Ele cria o cluster `eks-tc2-prod-001` na VPC `vpc-056d9d0731f21c5ed` com nodes `c7i-flex.large` nas subnets privadas.

```powershell
eksctl create cluster -f K8s/k8s-cluster.yaml
```

Após a criação, atualize o `kubeconfig`:

```powershell
aws eks update-kubeconfig --region us-east-2 --name eks-tc2-prod-001
kubectl get nodes   # deve listar os nodes em Ready
```

> **Dica:** Se precisar escalar o nodegroup depois:
> ```powershell
> aws eks update-nodegroup-config `
>   --region us-east-2 `
>   --cluster-name eks-tc2-prod-001 `
>   --nodegroup-name nodegroup-eks-tc2-prod-001 `
>   --scaling-config minSize=1,maxSize=2,desiredSize=2 `
>   --no-cli-pager
> ```

### 3.2 Tags obrigatórias nas subnets

> **Por quê:** O AWS Load Balancer Controller descobre automaticamente em quais subnets provisionar o ALB por meio de tags específicas. Sem elas, o ALB nunca é criado.

**Subnets públicas** (onde o ALB `internet-facing` será criado):

```powershell
# Repita para cada uma das três subnets públicas
$PUBLIC_SUBNET_ID="<id-da-subnet-publica>"

aws ec2 create-tags `
  --region us-east-2 `
  --resources $PUBLIC_SUBNET_ID `
  --tags Key=kubernetes.io/role/elb,Value=1 `
         Key=kubernetes.io/cluster/eks-tc2-prod-001,Value=shared `
  --no-cli-pager
```

**Subnets privadas** (onde os nodes estão):

```powershell
foreach ($SUBNET in @("subnet-05df64893137245da","subnet-09d64d4d84e8a736d","subnet-028fed72f5db4f768")) {
  aws ec2 create-tags `
    --region us-east-2 `
    --resources $SUBNET `
    --tags Key=kubernetes.io/role/internal-elb,Value=1 `
           Key=kubernetes.io/cluster/eks-tc2-prod-001,Value=shared `
    --no-cli-pager
}
```

### 3.3 Repositórios ECR

> **Por quê:** O EKS precisa puxar as imagens de um registry privado acessível de dentro da VPC. O ECR é o registry nativo da AWS. Tags são **IMMUTABLE** — sempre incremente a versão ao reconstruir.

Crie um repositório para cada serviço:

```powershell
$AWS_REGION="us-east-2"

foreach ($REPO in @(
  "fiap-fase2/auth-service",
  "fiap-fase2/flag-service",
  "fiap-fase2/targeting-service",
  "fiap-fase2/evaluation-service",
  "fiap-fase2/analytics-service"
)) {
  aws ecr create-repository `
    --repository-name $REPO `
    --image-scanning-configuration scanOnPush=true `
    --image-tag-mutability IMMUTABLE `
    --encryption-configuration encryptionType=AES256 `
    --region $AWS_REGION `
    --no-cli-pager
}
```

### 3.4 Fila SQS

> **Por quê:** O `evaluation-service` publica eventos de avaliação nessa fila de forma assíncrona, e o `analytics-service` os consome. A fila precisa existir antes do deploy de qualquer um dos dois serviços.

```powershell
$AWS_REGION="us-east-2"

aws sqs create-queue `
  --region $AWS_REGION `
  --queue-name ToggleMasterQueue `
  --attributes VisibilityTimeout=30 `
  --no-cli-pager

# Anote a QueueUrl retornada — você vai precisar dela
aws sqs get-queue-url `
  --region $AWS_REGION `
  --queue-name ToggleMasterQueue `
  --no-cli-pager
```

---

## 4. Add-ons do Cluster EKS

Os add-ons abaixo devem ser instalados **antes** de qualquer microserviço, pois eles fornecem capacidades que os pods dependem em tempo de execução.

### 4.1 OIDC Provider (IRSA)

> **Por quê:** IRSA (IAM Roles for Service Accounts) permite que pods assumam IAM Roles sem precisar de credenciais estáticas. Isso é feito associando um IAM Role a um Kubernetes ServiceAccount via OIDC. Todos os microserviços usam IRSA para acessar Secrets Manager, SQS e DynamoDB.

```powershell
eksctl utils associate-iam-oidc-provider `
  --region us-east-2 `
  --cluster eks-tc2-prod-001 `
  --approve
```

Confirme:

```powershell
aws iam list-open-id-connect-providers --no-cli-pager
# Deve retornar o ARN do provider do seu cluster
```

> **Importante:** O OIDC Issuer ID do cluster deve coincidir exatamente com o campo `Condition` nos arquivos `irsa-trust-policy.json` de cada serviço. Verifique:
> ```powershell
> aws eks describe-cluster --name eks-tc2-prod-001 --query "cluster.identity.oidc.issuer" --output text --no-cli-pager
> ```

### 4.2 Secrets Store CSI Driver

> **Por quê:** O CSI Driver monta secrets do AWS Secrets Manager diretamente como volumes nos pods, sem precisar de variáveis de ambiente hard-coded no manifesto. O `SecretProviderClass` de cada serviço instrui o driver sobre quais segredos buscar. Sem ele, os pods que usam `secretproviderclass` ficam em `ContainerCreating` para sempre.

```powershell
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo update

helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver `
  --namespace kube-system `
  --set syncSecret.enabled=true `
  --set enableSecretRotation=true
```

Instale o **AWS Provider** (plugin que traduz o CSI Driver para chamadas ao Secrets Manager):

```powershell
kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml
```

Verifique:

```powershell
kubectl get pods -n kube-system -l app=csi-secrets-store-provider-aws
# Deve haver um pod por node, todos em Running
```

### 4.3 AWS Load Balancer Controller

> **Por quê:** O `Ingress` nativo do Kubernetes não faz nada sozinho. O AWS Load Balancer Controller assiste os recursos `Ingress` e automaticamente cria/atualiza o ALB na AWS. Todos os microserviços públicos compartilham um único ALB via `alb.ingress.kubernetes.io/group.name: fiap-fase2-prod` — o controller é quem gerencia as regras de roteamento entre eles.

#### Passo 1 — IAM Policy

```powershell
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.11.0/docs/install/iam_policy.json" `
  -OutFile "AWS/alb-controller/iam-policy.json"

aws iam create-policy `
  --policy-name AWSLoadBalancerControllerIAMPolicy `
  --policy-document file://AWS/alb-controller/iam-policy.json `
  --no-cli-pager
```

> A policy inclui `elasticloadbalancing:SetRulePriorities`, obrigatória ao adicionar um novo `Ingress` a um grupo ALB existente. Sem ela, o controller lança `AccessDenied` e as regras nunca são aplicadas.

#### Passo 2 — IAM Role (IRSA)

```powershell
aws iam create-role `
  --role-name aws-load-balancer-controller-role `
  --assume-role-policy-document file://AWS/alb-controller/irsa-trust-policy.json `
  --no-cli-pager

aws iam attach-role-policy `
  --role-name aws-load-balancer-controller-role `
  --policy-arn arn:aws:iam::570814275471:policy/AWSLoadBalancerControllerIAMPolicy `
  --no-cli-pager
```

#### Passo 3 — ServiceAccount e Helm install

```powershell
kubectl apply -f K8s/base/alb-controller/serviceaccount.yaml

helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller `
  --namespace kube-system `
  --set clusterName=eks-tc2-prod-001 `
  --set serviceAccount.create=false `
  --set serviceAccount.name=aws-load-balancer-controller `
  --set region=us-east-2 `
  --set vpcId=vpc-056d9d0731f21c5ed
```

Verifique:

```powershell
kubectl get deployment -n kube-system aws-load-balancer-controller
```

### 4.4 KEDA

> **Por quê:** O `analytics-service` usa KEDA (Kubernetes Event-Driven Autoscaling) para escalar automaticamente baseado no número de mensagens na fila SQS. Sem o KEDA, o `ScaledObject` e o `TriggerAuthentication` aplicados posteriormente não serão reconhecidos como CRDs válidos e os pods não escalarão.

#### Passo 1 — IAM Policy para o KEDA ler a fila SQS

```powershell
aws iam create-policy `
  --policy-name keda-sqs-policy `
  --policy-document file://AWS/keda/iam-policy.json `
  --no-cli-pager
```

#### Passo 2 — IAM Role (IRSA) para o KEDA

```powershell
aws iam create-role `
  --role-name keda-operator-role `
  --assume-role-policy-document file://AWS/keda/irsa-trust-policy.json `
  --no-cli-pager

aws iam attach-role-policy `
  --role-name keda-operator-role `
  --policy-arn arn:aws:iam::570814275471:policy/keda-sqs-policy `
  --no-cli-pager
```

#### Passo 3 — Helm install

```powershell
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

helm install keda kedacore/keda --namespace keda --create-namespace
```

Verifique:

```powershell
kubectl get pods -n keda
# keda-operator e keda-operator-metrics-apiserver devem estar em Running
```

---

## 5. auth-service

> **O que é:** Serviço de autenticação em Go. Cria e valida chaves de API do tipo `tm_key_*`. É a **fundação de segurança** do sistema — todos os outros microserviços chamam o `auth-service` para validar cada requisição recebida.

### 5.1 RDS PostgreSQL

> **Por quê:** As chaves de API são persistidas em PostgreSQL. O serviço não faz auto-migrate — o `init.sql` precisa ser executado manualmente antes do primeiro deploy.

```powershell
$AWS_REGION="us-east-2"
$VPC_ID="vpc-056d9d0731f21c5ed"
$APP_SG_ID="sg-0ccddfe7b0c2cfda6"   # SG do nodegroup EKS

# Security group do RDS (permite acesso apenas dos nodes EKS)
aws ec2 create-security-group `
  --region $AWS_REGION `
  --group-name auth-service-rds-sg `
  --description "RDS SG for auth-service" `
  --vpc-id $VPC_ID `
  --no-cli-pager

aws ec2 authorize-security-group-ingress `
  --region $AWS_REGION `
  --group-id sg-0ca17e790641e3605 `
  --protocol tcp --port 5432 `
  --source-group $APP_SG_ID `
  --no-cli-pager

# Subnet group
aws rds create-db-subnet-group `
  --region $AWS_REGION `
  --db-subnet-group-name auth-service-subnet-group `
  --db-subnet-group-description "Subnet group for auth-service RDS" `
  --subnet-ids subnet-05df64893137245da subnet-09d64d4d84e8a736d subnet-028fed72f5db4f768 `
  --no-cli-pager

# Instância RDS
aws rds create-db-instance `
  --region $AWS_REGION `
  --db-instance-identifier auth-service-db `
  --engine postgres --engine-version 18.3 `
  --db-instance-class db.t3.micro `
  --allocated-storage 20 --storage-type gp2 `
  --master-username auth_service_user `
  --master-user-password ************ `
  --db-name auth_service_db `
  --vpc-security-group-ids sg-0ca17e790641e3605 `
  --db-subnet-group-name auth-service-subnet-group `
  --no-publicly-accessible `
  --backup-retention-period 1 `
  --no-deletion-protection `
  --no-cli-pager
```

Aguarde o status `available` (~5 min) e anote o endpoint:

```powershell
aws rds describe-db-instances `
  --region us-east-2 `
  --db-instance-identifier auth-service-db `
  --query "DBInstances[0].Endpoint.Address" `
  --output text --no-cli-pager
```

Execute o schema **antes** do primeiro deploy (via bastion ou port-forward):

```bash
psql -h <endpoint-rds> -U auth_service_user -d auth_service_db -f auth-service/db/init.sql
```

### 5.2 AWS Secrets Manager

> **Por quê:** `DATABASE_URL` e `MASTER_KEY` são segredos sensíveis. Armazená-los no Secrets Manager e injetá-los via CSI Driver evita que apareçam em texto claro nos manifests ou logs do Kubernetes.

O auth-service usa **um único secret JSON** com o nome `auth-service/app`:

```powershell
aws secretsmanager create-secret `
  --region us-east-2 `
  --name auth-service/app `
  --secret-string '{
    "DATABASE_URL": "postgres://auth_service_user:************@<endpoint-rds>:5432/auth_service_db",
    "MASTER_KEY": "<chave-mestra-forte>"
  }' `
  --no-cli-pager
```

Para atualizar:

```powershell
aws secretsmanager put-secret-value `
  --region us-east-2 `
  --secret-id auth-service/app `
  --secret-string '{"DATABASE_URL":"...","MASTER_KEY":"..."}' `
  --no-cli-pager
```

### 5.3 IRSA

> **Por quê:** O pod precisa de permissão para ler o secret do Secrets Manager. O IRSA associa o IAM Role ao ServiceAccount do pod, sem injetar credenciais AWS no container.

```powershell
aws iam create-policy `
  --policy-name auth-service-secrets-policy `
  --policy-document file://AWS/auth-service/iam-policy-secrets-manager.json `
  --no-cli-pager

aws iam create-role `
  --role-name auth-service-secrets-role `
  --assume-role-policy-document file://AWS/auth-service/irsa-trust-policy.json `
  --no-cli-pager

aws iam attach-role-policy `
  --role-name auth-service-secrets-role `
  --policy-arn arn:aws:iam::570814275471:policy/auth-service-secrets-policy `
  --no-cli-pager
```

### 5.4 Build e Push da imagem

> **Por quê:** O Deployment referencia a imagem ECR. Ela precisa existir antes do apply.

```powershell
$AWS_REGION="us-east-2"; $ACCOUNT_ID="570814275471"; $TAG="1.0.3"

aws ecr get-login-password --region $AWS_REGION | `
  docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

cd auth-service
docker build -t fiap-fase2/auth-service:$TAG .
docker tag fiap-fase2/auth-service:$TAG `
  "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fiap-fase2/auth-service:$TAG"
docker push "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fiap-fase2/auth-service:$TAG"
cd ..
```

### 5.5 Deploy no Kubernetes

> **Por quê:** A ordem dos manifests importa: namespace → serviceaccount → secretproviderclass → deployment → service → ingress. O deployment monta o CSI volume e só fica `Ready` após o pod se autenticar no Secrets Manager via IRSA.

```powershell
kubectl apply -f K8s/auth-service/service.yaml
kubectl apply -f K8s/auth-service/serviceaccount.yaml
kubectl apply -f K8s/auth-service/secretproviderclass.yaml
kubectl apply -f K8s/auth-service/deployment.yaml
kubectl apply -f K8s/auth-service/ingress.yaml
```

Verifique:

```powershell
kubectl get pods -n auth-service
kubectl logs -n auth-service -l app=auth-service

# Após o ALB estar pronto (~2 min):
kubectl get ingress auth-service -n auth-service
$ALB_DNS=$(kubectl get ingress auth-service -n auth-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl "http://$ALB_DNS/auth/health"
# Esperado: {"status":"ok"}
```

---

## 6. flag-service

> **O que é:** CRUD de feature flags em Python/Flask. Protegido pelo `auth-service` — toda requisição (exceto `/health`) exige um `Authorization: Bearer <api-key>` válido. É a fonte de verdade das definições de flags.

### 6.1 RDS PostgreSQL

> **Por quê:** As definições de flags (nome, descrição, status) são persistidas em banco separado do auth-service para isolar dados e respeitar o princípio de responsabilidade única.

Siga o mesmo padrão do auth-service para criar security group, subnet group e instância RDS, substituindo:

- `--db-instance-identifier flag-service-db`
- `--db-name flag_service_db`
- `--master-username flag_service_user`

Após criar a instância, execute o schema:

```bash
psql -h <endpoint-rds-flag> -U flag_service_user -d flag_service_db -f flag-service/db/init.sql
```

### 6.2 AWS Secrets Manager

> **Por quê:** A `DATABASE_URL` contém credenciais de banco que não devem aparecer nos manifests. O secret é injetado pelo Secrets Store CSI Driver conforme definido em [K8s/flag-service/secretproviderclass.yaml](K8s/flag-service/secretproviderclass.yaml).

```powershell
aws secretsmanager create-secret `
  --region us-east-2 `
  --name flag-service/DATABASE_URL `
  --secret-string "postgres://flag_service_user:************@<endpoint-rds-flag>:5432/flag_service_db" `
  --no-cli-pager
```

### 6.3 IRSA

```powershell
aws iam create-policy `
  --policy-name flag-service-secrets-policy `
  --policy-document file://AWS/flag-service/iam-policy-secrets-manager.json `
  --no-cli-pager

aws iam create-role `
  --role-name flag-service-secrets-role `
  --assume-role-policy-document file://AWS/flag-service/irsa-trust-policy.json `
  --no-cli-pager

aws iam attach-role-policy `
  --role-name flag-service-secrets-role `
  --policy-arn arn:aws:iam::570814275471:policy/flag-service-secrets-policy `
  --no-cli-pager
```

### 6.4 Build e Push da imagem

```powershell
$AWS_REGION="us-east-2"; $ACCOUNT_ID="570814275471"; $TAG="1.0.1"

cd flag-service
docker build -t fiap-fase2/flag-service:$TAG .
docker tag fiap-fase2/flag-service:$TAG `
  "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fiap-fase2/flag-service:$TAG"
docker push "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fiap-fase2/flag-service:$TAG"
cd ..
```

### 6.5 Deploy no Kubernetes

```powershell
kubectl apply -f K8s/flag-service/namespace.yaml
kubectl apply -f K8s/flag-service/serviceaccount.yaml
kubectl apply -f K8s/flag-service/secretproviderclass.yaml
kubectl apply -f K8s/flag-service/deployment.yaml
kubectl apply -f K8s/flag-service/service.yaml
kubectl apply -f K8s/flag-service/ingress.yaml
```

Verifique:

```powershell
kubectl get pods -n flag-service
$ALB_DNS=$(kubectl get ingress flag-service -n flag-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl "http://$ALB_DNS/flags/health"
```

---

## 7. targeting-service

> **O que é:** Serviço Python que gerencia regras de segmentação (ex: "50% dos usuários", "país = BR") para cada flag. O `evaluation-service` consulta este serviço para decidir se uma flag está ativa para um usuário específico.

### 7.1 RDS PostgreSQL

Siga o mesmo padrão, substituindo:

- `--db-instance-identifier targeting-service-db`
- `--db-name targeting_service_db`
- `--master-username targeting_service_user`

Execute o schema:

```bash
psql -h <endpoint-rds-targeting> -U targeting_service_user -d targeting_service_db -f targeting-service/db/init.sql
```

### 7.2 AWS Secrets Manager

```powershell
aws secretsmanager create-secret `
  --region us-east-2 `
  --name targeting-service/DATABASE_URL `
  --secret-string "postgres://targeting_service_user:************@<endpoint-rds-targeting>:5432/targeting_service_db" `
  --no-cli-pager
```

### 7.3 IRSA

```powershell
aws iam create-policy `
  --policy-name targeting-service-secrets-policy `
  --policy-document file://AWS/targeting-service/iam-policy-secrets-manager.json `
  --no-cli-pager

aws iam create-role `
  --role-name targeting-service-secrets-role `
  --assume-role-policy-document file://AWS/targeting-service/irsa-trust-policy.json `
  --no-cli-pager

aws iam attach-role-policy `
  --role-name targeting-service-secrets-role `
  --policy-arn arn:aws:iam::570814275471:policy/targeting-service-secrets-policy `
  --no-cli-pager
```

### 7.4 Build e Push da imagem

```powershell
$AWS_REGION="us-east-2"; $ACCOUNT_ID="570814275471"; $TAG="1.0.2"

cd targeting-service
docker build -t fiap-fase2/targeting-service:$TAG .
docker tag fiap-fase2/targeting-service:$TAG `
  "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fiap-fase2/targeting-service:$TAG"
docker push "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fiap-fase2/targeting-service:$TAG"
cd ..
```

### 7.5 Deploy no Kubernetes

```powershell
kubectl apply -f K8s/targeting-service/namespace.yaml
kubectl apply -f K8s/targeting-service/serviceaccount.yaml
kubectl apply -f K8s/targeting-service/secretproviderclass.yaml
kubectl apply -f K8s/targeting-service/deployment.yaml
kubectl apply -f K8s/targeting-service/service.yaml
kubectl apply -f K8s/targeting-service/ingress.yaml
```

Verifique:

```powershell
kubectl get pods -n targeting-service
$ALB_DNS=$(kubectl get ingress targeting-service -n targeting-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl "http://$ALB_DNS/targeting/health"
```

---

## 8. evaluation-service

> **O que é:** O "caminho quente" (hot path) em Go. É o único endpoint que os clientes finais chamam. Ele avalia em tempo real se uma flag está ativa para um usuário, usando cache Redis para minimizar latência, e publica eventos assíncronos na fila SQS para o analytics-service processar.

> **Por quê depois dos outros três:** O deployment referencia `flag-service` e `targeting-service` via DNS interno (`*.svc.cluster.local`). Se esses serviços não existirem, as probes falharão e o pod nunca ficará `Ready`.

### 8.1 Amazon ElastiCache (Redis)

> **Por quê:** O Redis é o cache de regras de flags. Sem ele, cada avaliação faria chamadas síncronas ao `flag-service` e `targeting-service`, aumentando a latência. O `evaluation-service` tem fallback para buscar direto nos serviços em caso de cache miss.

Crie um cluster Redis (ou Serverless) na mesma VPC, nas subnets privadas, permitindo acesso do SG do nodegroup na porta 6379. Anote o endpoint.

### 8.2 AWS Secrets Manager

> **Por quê:** `REDIS_URL` contém a senha do Redis e `SERVICE_API_KEY` é a chave de API com que o evaluation-service se autentica no flag-service e targeting-service. Ambas são sensíveis e gerenciadas pelo CSI Driver conforme [K8s/evaluation-service/secretproviderclass.yaml](K8s/evaluation-service/secretproviderclass.yaml).

Crie um secret **separado** para cada variável (o `SecretProviderClass` espera caminhos individuais):

```powershell
$AWS_REGION="us-east-2"

# Crie primeiro uma API key para o evaluation-service no auth-service
$ALB_DNS="<dns-do-alb>"
$MASTER_KEY="<sua-chave-mestra>"

$RESPONSE=$(curl -s -X POST "http://$ALB_DNS/auth/admin/keys" `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer $MASTER_KEY" `
  -d '{"name": "evaluation-service-key"}')

$SERVICE_API_KEY=$(echo $RESPONSE | python -c "import sys,json; print(json.load(sys.stdin)['key'])")

# Salve os secrets
aws secretsmanager create-secret `
  --region $AWS_REGION `
  --name evaluation-service/SERVICE_API_KEY `
  --secret-string $SERVICE_API_KEY `
  --no-cli-pager

aws secretsmanager create-secret `
  --region $AWS_REGION `
  --name evaluation-service/REDIS_URL `
  --secret-string "redis://:************@<endpoint-elasticache>:6379" `
  --no-cli-pager
```

### 8.3 IRSA

> **Por quê:** O pod precisa de permissão para ler os dois secrets do Secrets Manager **e** para publicar mensagens na fila SQS. Tudo isso é concedido pela IAM Policy em [AWS/evaluation-service/iam-policy.json](AWS/evaluation-service/iam-policy.json).

```powershell
aws iam create-policy `
  --policy-name evaluation-service-policy `
  --policy-document file://AWS/evaluation-service/iam-policy.json `
  --no-cli-pager

aws iam create-role `
  --role-name evaluation-service-role `
  --assume-role-policy-document file://AWS/evaluation-service/irsa-trust-policy.json `
  --no-cli-pager

aws iam attach-role-policy `
  --role-name evaluation-service-role `
  --policy-arn arn:aws:iam::570814275471:policy/evaluation-service-policy `
  --no-cli-pager
```

### 8.4 Build e Push da imagem

```powershell
$AWS_REGION="us-east-2"; $ACCOUNT_ID="570814275471"; $TAG="1.0.0"

cd evaluation-service
docker build -t fiap-fase2/evaluation-service:$TAG .
docker tag fiap-fase2/evaluation-service:$TAG `
  "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fiap-fase2/evaluation-service:$TAG"
docker push "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fiap-fase2/evaluation-service:$TAG"
cd ..
```

### 8.5 Deploy no Kubernetes

```powershell
kubectl apply -f K8s/evaluation-service/namespace.yaml
kubectl apply -f K8s/evaluation-service/serviceaccount.yaml
kubectl apply -f K8s/evaluation-service/secretproviderclass.yaml
kubectl apply -f K8s/evaluation-service/deployment.yaml
kubectl apply -f K8s/evaluation-service/service.yaml
kubectl apply -f K8s/evaluation-service/ingress.yaml
```

Verifique:

```powershell
kubectl get pods -n evaluation-service
$ALB_DNS=$(kubectl get ingress evaluation-service -n evaluation-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl "http://$ALB_DNS/evaluation/health"
```

---

## 9. analytics-service

> **O que é:** Worker Python que consome a fila SQS `ToggleMasterQueue` e persiste os eventos de avaliação no DynamoDB. Não expõe API pública além do `/health`. Escala automaticamente com KEDA baseado no volume de mensagens na fila.

> **Por quê por último:** Depende da fila SQS já existir (criada na seção 3.4) e de mensagens sendo publicadas pelo `evaluation-service`. O KEDA também precisa estar instalado antes.

### 9.1 DynamoDB

> **Por quê:** Os eventos de avaliação (qual usuário recebeu qual resultado para qual flag) são imutáveis e chegam em alta frequência — DynamoDB serverless é ideal para esse padrão de escrita intensiva e leitura por `event_id`.

```powershell
aws dynamodb create-table `
  --region us-east-2 `
  --table-name ToggleMasterAnalytics `
  --attribute-definitions AttributeName=event_id,AttributeType=S `
  --key-schema AttributeName=event_id,KeyType=HASH `
  --billing-mode PAY_PER_REQUEST `
  --no-cli-pager

# Aguarde o status ACTIVE (~30 seg)
aws dynamodb describe-table `
  --region us-east-2 `
  --table-name ToggleMasterAnalytics `
  --query "Table.TableStatus" --output text --no-cli-pager
```

### 9.2 IRSA

> **Por quê:** O pod precisa de permissão para consumir mensagens SQS (`ReceiveMessage`, `DeleteMessage`, `GetQueueAttributes`) e para gravar no DynamoDB (`PutItem`). O KEDA também precisa de uma role separada (`keda-operator-role`, criada na seção 4.4) apenas para `GetQueueAttributes` a fim de calcular o número de mensagens para o autoscaling.

```powershell
aws iam create-policy `
  --policy-name analytics-service-policy `
  --policy-document file://AWS/analytics-service/iam-policy.json `
  --no-cli-pager

aws iam create-role `
  --role-name analytics-service-role `
  --assume-role-policy-document file://AWS/analytics-service/irsa-trust-policy.json `
  --no-cli-pager

aws iam attach-role-policy `
  --role-name analytics-service-role `
  --policy-arn arn:aws:iam::570814275471:policy/analytics-service-policy `
  --no-cli-pager
```

### 9.3 Build e Push da imagem

```powershell
$AWS_REGION="us-east-2"; $ACCOUNT_ID="570814275471"; $TAG="1.0.0"

aws ecr get-login-password --region $AWS_REGION | `
  docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

cd analytics-service
docker build -t fiap-fase2/analytics-service:$TAG .
docker tag fiap-fase2/analytics-service:$TAG `
  "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fiap-fase2/analytics-service:$TAG"
docker push "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fiap-fase2/analytics-service:$TAG"
cd ..
```

### 9.4 Deploy no Kubernetes

> **Por quê esta ordem:** O `ScaledObject` precisa que o Deployment já exista para ter um target de scale. O `TriggerAuthentication` precisa que o ServiceAccount com IRSA já esteja criado.

```powershell
kubectl apply -f K8s/analytics-service/namespace.yaml
kubectl apply -f K8s/analytics-service/serviceaccount.yaml
kubectl apply -f K8s/analytics-service/deployment.yaml
kubectl apply -f K8s/analytics-service/service.yaml
kubectl apply -f K8s/analytics-service/keda-trigger-auth.yaml
kubectl apply -f K8s/analytics-service/scaledobject.yaml
```

Verifique:

```powershell
kubectl get pods -n analytics-service
kubectl logs -n analytics-service -l app=analytics-service -f
# Deve aparecer: "Iniciando o worker SQS..."

# Verificar o ScaledObject (minReplicaCount=0, então sem mensagens o pod pode desaparecer)
kubectl get scaledobject -n analytics-service
```

### 9.5 Verificar persistência no DynamoDB

Após o `evaluation-service` publicar eventos:

```powershell
aws dynamodb scan `
  --region us-east-2 `
  --table-name ToggleMasterAnalytics `
  --max-items 5 `
  --no-cli-pager
```

---

## 10. Verificação End-to-End

Com tudo deployado, valide o fluxo completo:

```powershell
$ALB="<dns-do-alb>"
$MASTER_KEY="<sua-master-key>"

# 1. Criar uma API key
$KEY=$(curl -s -X POST "http://$ALB/auth/admin/keys" `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer $MASTER_KEY" `
  -d '{"name":"e2e-test"}' | python -c "import sys,json; print(json.load(sys.stdin)['key'])")

# 2. Criar uma flag
curl -s -X POST "http://$ALB/flags" `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer $KEY" `
  -d '{"name":"e2e-flag","description":"Teste end-to-end","is_enabled":true}'

# 3. Criar uma regra de targeting (50% dos usuários)
curl -s -X POST "http://$ALB/targeting/rules" `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer $KEY" `
  -d '{"flag_name":"e2e-flag","is_enabled":true,"rules":{"type":"PERCENTAGE","value":50}}'

# 4. Avaliar a flag para um usuário
curl -s "http://$ALB/evaluation/evaluate?user_id=user-abc&flag_name=e2e-flag"
# Esperado: {"flag_name":"e2e-flag","user_id":"user-abc","result":true|false}

# 5. Confirmar que o evento chegou no DynamoDB
aws dynamodb scan `
  --region us-east-2 `
  --table-name ToggleMasterAnalytics `
  --max-items 1 `
  --no-cli-pager
```

---

## Referência rápida — portas e caminhos de health check

| Serviço            | Porta | Health check path       | Namespace          |
|--------------------|-------|-------------------------|--------------------|
| auth-service       | 8001  | `/auth/health`          | `auth-service`     |
| flag-service       | 8002  | `/health`               | `flag-service`     |
| targeting-service  | 8003  | `/targeting/health`     | `targeting-service`|
| evaluation-service | 8004  | `/evaluation/health`    | `evaluation-service`|
| analytics-service  | 8005  | `/health`               | `analytics-service`|
