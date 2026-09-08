# GitOps — Continuous Deployment com ArgoCD

Estrutura GitOps para gerenciar o deployment dos 5 microserviços no EKS usando ArgoCD.

## Arquitetura

```
┌─────────────────────────────────────────────────────────────────┐
│                     GitHub Repository                           │
│  ┌──────────────────┐  ┌────────────────────────────────────┐  │
│  │  CI Pipelines    │  │  GitOps Repository (este dir)     │  │
│  │  (.github/...)   │  │  - gitops/apps/                   │  │
│  │                  │  │  - gitops/argocd/                 │  │
│  │  - Build image   │  │  - kustomization.yaml             │  │
│  │  - Push to ECR   │  │  - ArgoCD Applications            │  │
│  │  - Update tags   │  │                                    │  │
│  └────────┬─────────┘  └────────────────────────────────────┘  │
│           │                                                      │
│           └──────────────────┬─────────────────────────────────┘
│                              │
│                              │ 1. Update image tag
│                              │ 2. Commit & push
└──────────────────────────────┼──────────────────────────────────┘
                               │
                          watches
                               │
                    ┌──────────▼──────────┐
                    │   EKS Cluster       │
                    │                     │
                    │  ┌─────────────────┐│
                    │  │ ArgoCD          ││
                    │  │                 ││
                    │  │ (5 Applications)││ Syncs automatically
                    │  │                 ││ when Git changes
                    │  └────────┬────────┘│
                    │           │         │
                    │     ┌─────▼──────┐  │
                    │     │ Kubernetes │  │
                    │     │ Deployments│  │
                    │     │            │  │
                    │     │ - auth     │  │
                    │     │ - flag     │  │
                    │     │ - eval     │  │
                    │     │ - targeting│  │
                    │     │ - analytics│  │
                    │     └────────────┘  │
                    └─────────────────────┘
```

## Estrutura de Diretórios

```
gitops/
├── apps/                           # Manifests de cada serviço
│   ├── kustomization.yaml          # Kustomize root
│   ├── auth-service/
│   │   ├── kustomization.yaml      # Customização + image patches
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml
│   │   ├── serviceaccount.yaml
│   │   ├── namespace.yaml
│   │   └── secretproviderclass.yaml
│   ├── flag-service/
│   ├── evaluation-service/
│   ├── targeting-service/
│   └── analytics-service/
│
├── argocd/
│   ├── applications.yaml           # ArgoCD Application definitions
│   └── kustomization.yaml          # Kustomize para argocd/
│
└── update-image-tag.sh             # Script para atualizar tags (chamado pela CI)
```

## Setup: Instalar ArgoCD

### 1. Ativar ArgoCD no Terraform

```bash
cd terraform

# Edite terraform.tfvars:
cat >> terraform.tfvars << 'EOF'

# ---------------------------------------------------------------------------
# GitOps & ArgoCD
# ---------------------------------------------------------------------------
enable_argocd = true
EOF

# Aplique as mudanças
terraform apply -auto-approve -input=false
```

ArgoCD será instalado no namespace `argocd`.

### 2. Acessar o ArgoCD UI

```bash
# Port-forward para acessar o UI localmente
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Abra no navegador:
# https://localhost:8080

# Username: admin
# Password: obter com:
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### 3. Registrar as Aplicações no ArgoCD

Uma vez que o ArgoCD esteja rodando, registre as 5 aplicações:

```bash
kubectl apply -f gitops/argocd/applications.yaml
```

Isto criará 5 Application resources no ArgoCD, um para cada microserviço.

## Workflow: CI/CD com GitOps

### 1. Developer faz push para main

```bash
git add .
git commit -m "Feat: nova feature no flag-service"
git push origin main
```

### 2. CI Pipeline executa

GitHub Actions roda automaticamente:

1. **Build & Test** — compila, testa, faz lint
2. **Security Scan** — SCA + SAST
3. **Docker Build & Scan** — monta a imagem, escaneia com Trivy
4. **Push to ECR** — pusha `v<VERSION>-<sha7>` + `latest`
5. **Update GitOps** (🆕) — atualiza a tag em `gitops/apps/<service>/kustomization.yaml`

### 3. Exemplo: atualizar flag-service

O workflow de CI do flag-service agora faz:

```bash
# Após push da imagem para ECR:
./gitops/update-image-tag.sh flag-service v1.0.1-a1b2c3d

# Isso edita: gitops/apps/flag-service/kustomization.yaml
# newTag: 1.0.1  →  newTag: v1.0.1-a1b2c3d

# Commit e push das mudanças:
git add gitops/apps/flag-service/kustomization.yaml
git commit -m "chore: bump flag-service image to v1.0.1-a1b2c3d"
git push origin main
```

### 4. ArgoCD sincroniza automaticamente

ArgoCD monitora o repositório main. Quando a tag muda:

1. **Detecta mudança** — polling a cada 3 minutos (ou webhook em tempo real)
2. **Calcula diff** — compara Git vs cluster
3. **Sincroniza** — faz um `kubectl apply` dos manifests atualizados
4. **Rollout** — Kubernetes faz rolling update do deployment

Resultado: novo pod com a imagem atualizada.

## Customização: Adicionar um novo serviço

Se adicionar um 6º serviço:

1. **Criar estrutura GitOps:**
   ```bash
   mkdir gitops/apps/novo-service
   cp K8s/novo-service/*.yaml gitops/apps/novo-service/
   ```

2. **Criar kustomization:**
   ```bash
   cat > gitops/apps/novo-service/kustomization.yaml << 'EOF'
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   
   namespace: novo-service
   resources:
     - deployment.yaml
     - service.yaml
     # ... outros recursos
   
   images:
     - name: novo-service
       newName: 056007986659.dkr.ecr.us-east-1.amazonaws.com/fiap-fase2/novo-service
       newTag: 1.0.0
   EOF
   ```

3. **Adicionar ao root kustomization:** Edite `gitops/apps/kustomization.yaml`

4. **Criar Application no ArgoCD:** Edite `gitops/argocd/applications.yaml`

5. **Adicionar workflow de CI:** Copie um dos workflows e customize

6. **Registrar no ArgoCD:**
   ```bash
   kubectl apply -f gitops/argocd/applications.yaml
   ```

## Troubleshooting

### ArgoCD não sincroniza

```bash
# Verificar status da aplicação
kubectl get application -n argocd
kubectl describe application -n argocd flag-service

# Verificar logs do ArgoCD
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=100

# Forçar sincronização
argocd app sync flag-service  # requer argocd CLI
# ou via UI: Applications > flag-service > Sync > Synchronize
```

### Imagem não atualiza no pod

```bash
# Verificar se o kustomization.yaml foi atualizado
cat gitops/apps/flag-service/kustomization.yaml | grep newTag

# Verificar o diff no ArgoCD
kubectl diff -f gitops/apps/flag-service/

# Forçar um sync com recreação de pods
argocd app sync flag-service --prune
```

### Erro: "Resource could not be created"

Pode ser que o namespace não exista. Verifique:

```bash
kubectl get namespace flag-service

# Se não existir, ArgoCD pode criar automaticamente (CreateNamespace=true)
# Ou crie manualmente:
kubectl create namespace flag-service
```

## Monitoramento

### Visualizar todas as aplicações no ArgoCD UI

1. Acesse `https://localhost:8080`
2. Clique em "Applications"
3. Veja as 5 aplicações:
   - auth-service (sync status, health)
   - flag-service
   - evaluation-service
   - targeting-service
   - analytics-service

### Logs em tempo real

```bash
# Monitorar sync de uma aplicação
kubectl logs -n argocd -f deployment/argocd-application-controller

# Monitorar repo server
kubectl logs -n argocd -f deployment/argocd-repo-server
```

## Referências

- [ArgoCD Documentation](https://argoproj.github.io/argo-cd/)
- [Kustomize Guide](https://kustomize.io/)
- [GitOps Best Practices](https://www.weave.works/technologies/gitops/)
