# GitOps Setup Checklist

Este documento descreve todos os componentes criados para o setup de GitOps com ArgoCD e o passo-a-passo para ativar o Continuous Deployment.

## 📁 O que foi criado

### 1. Estrutura GitOps

```
gitops/
├── README.md                          # Documentação completa do GitOps
├── update-image-tag.sh               # Script para atualizar tags (CI→Git)
├── apps/
│   ├── kustomization.yaml            # Root kustomization
│   ├── auth-service/kustomization.yaml
│   ├── flag-service/kustomization.yaml
│   ├── evaluation-service/kustomization.yaml
│   ├── targeting-service/kustomization.yaml
│   └── analytics-service/kustomization.yaml
└── argocd/
    ├── applications.yaml             # 5 ArgoCD Applications
    └── kustomization.yaml
```

### 2. Terraform: Módulo ArgoCD

```
terraform/modules/argocd/
├── main.tf                           # Helm release do ArgoCD
└── variables.tf                      # Variable enable_argocd
```

Integrado em `terraform/main.tf` e `terraform/variables.tf`.

### 3. Documentação

- **gitops/README.md** — Guia completo de uso (como instalar, usar, troubleshoot)
- **.github/CD.md** — Integração com CI pipelines
- **GITOPS_SETUP.md** — Este arquivo (checklist de setup)

---

## ✅ Passo-a-Passo: Ativar GitOps

### **Fase 1: Instalar ArgoCD no cluster** (5 min)

```bash
cd terraform

# 1. Ativar no Terraform
echo "enable_argocd = true" >> terraform.tfvars

# 2. Aplicar
terraform apply -auto-approve -input=false

# 3. Verificar instalação
kubectl get pods -n argocd
kubectl get svc -n argocd

# Esperado:
# NAME                            READY   STATUS    RESTARTS   AGE
# argocd-server-...              1/1     Running   0          2m
# argocd-repo-server-...         1/1     Running   0          2m
# argocd-application-controller-1/1     Running   0          2m
```

**Tempo estimado:** 3-5 minutos para ArgoCD estar pronto.

---

### **Fase 2: Acessar ArgoCD UI** (2 min)

```bash
# 1. Port-forward
kubectl port-forward -n argocd svc/argocd-server 8080:443 &

# 2. Obter senha
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo "Password: $ARGOCD_PASS"

# 3. Acessar
# https://localhost:8080
# Username: admin
# Password: <copiar acima>
```

Verifique que você consegue ver a UI.

---

### **Fase 3: Registrar as 5 Aplicações** (1 min)

```bash
# Aplicar as ArgoCD Applications
kubectl apply -f gitops/argocd/applications.yaml

# Verificar
kubectl get applications -n argocd

# Esperado:
# NAME                  SYNC STATUS
# auth-service          Unknown
# flag-service          Unknown
# evaluation-service    Unknown
# targeting-service     Unknown
# analytics-service     Unknown
```

Acesse a UI e veja as 5 aplicações aparecerem na página inicial.

---

### **Fase 4: Integrar CD nos Workflows de CI** (10 min)

Para cada workflow em `.github/workflows/<service>.yml`, adicione os steps de CD após `🚀 Tag e push para o ECR`:

**Exemplo para flag-service:**

Edite `.github/workflows/flag-service.yml` e adicione no job `docker` após o step de push:

```yaml
      - name: 🔄 Atualizar tag GitOps
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        run: |
          SHA="${{ github.sha }}"
          SHORT_SHA="${SHA:0:7}"
          IMAGE_TAG="v${SERVICE_VERSION}-${SHORT_SHA}"
          ./gitops/update-image-tag.sh ${{ env.SERVICE_NAME }} "$IMAGE_TAG"

      - name: 📝 Commit e push GitOps
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        run: |
          git config user.name "GitHub Actions"
          git config user.email "actions@github.com"
          
          if [ -n "$(git status --porcelain)" ]; then
            git add gitops/apps/${{ env.SERVICE_NAME }}/kustomization.yaml
            SHA="${{ github.sha }}"
            git commit -m "chore: bump ${{ env.SERVICE_NAME }} to v${SERVICE_VERSION}-${SHA:0:7}"
            git push origin main
          fi
```

**Repita para todos os 5 workflows:**
- `.github/workflows/auth-service.yml`
- `.github/workflows/flag-service.yml`
- `.github/workflows/evaluation-service.yml`
- `.github/workflows/targeting-service.yml`
- `.github/workflows/analytics-service.yml`

---

### **Fase 5: Testar o Fluxo Completo** (15 min)

```bash
# 1. Fazer uma mudança no código
# Exemplo: editar flag-service/app.py

# 2. Commit e push para main
git add .
git commit -m "test: verify GitOps workflow"
git push origin main

# 3. Acompanhar a CI pipeline
# GitHub Actions > Actions > flag-service workflow
# Veja até o step "📝 Commit e push GitOps"

# 4. Verificar se a tag foi atualizada no Git
git log --oneline -3
# Deve ter um commit "chore: bump flag-service to v1.0.1-<sha7>"

# 5. Acompanhar a sincronização do ArgoCD
# ArgoCD UI > Applications > flag-service
# Veja o status mudar de "OutOfSync" para "Synced"

# 6. Verificar o rollout no cluster
kubectl rollout status deployment/flag-service -n flag-service
```

Se tudo correu bem, você verá:
```
deployment "flag-service" successfully rolled out
```

---

## 🎯 Resultado Final

Após completar todas as fases, você tem:

✅ **ArgoCD instalado** no cluster EKS
✅ **5 Aplicações registradas** no ArgoCD
✅ **CI/CD integrado** — cada push para main dispara:
  1. Build & Test
  2. Security Scan
  3. Docker build & push
  4. **Atualizar tag no Git** (novo!)
  5. **ArgoCD sincroniza automaticamente** (novo!)

---

## 📊 Monitorar as Aplicações

### Via ArgoCD UI

```
https://localhost:8080/applications
```

Veja o status de cada uma das 5 aplicações em tempo real:
- Sync Status (Synced / OutOfSync)
- Health (Healthy / Degraded)
- Pod readiness
- Last sync time

### Via CLI

```bash
# Ver status de todas as aplicações
kubectl get applications -n argocd -o wide

# Ver detalhes de uma aplicação
kubectl describe application flag-service -n argocd

# Ver logs do controller
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

---

## 🛠️ Troubleshooting Rápido

| Problema | Solução |
|----------|---------|
| Aplicação fica "OutOfSync" por muito tempo | ArgoCD faz polling a cada 3 min. Aguarde ou clique "Refresh" na UI |
| Imagem não atualiza no pod | Verifique se a tag foi atualizada em `gitops/apps/<service>/kustomization.yaml` |
| CI falha no step "Commit e push GitOps" | GitHub token pode ter permissões insuficientes; use `GITHUB_TOKEN` padrão ou crie um PAT |
| ArgoCD não consegue clonar o repositório | Verifique URL em `gitops/argocd/applications.yaml`; use HTTPS (não SSH) |

Ver **gitops/README.md** para troubleshooting detalhado.

---

## 📚 Referências

- **gitops/README.md** — Guia completo
- **.github/CD.md** — Integração CI/CD
- **gitops/argocd/applications.yaml** — Definição das aplicações
- **gitops/apps/<service>/kustomization.yaml** — Customização por serviço

---

## 🎓 Conceitos-chave

### GitOps

> "A versão atual do sistema é a versão no Git. Se o cluster divergir do Git, sincronize."

Benefícios:
- **Versionamento** — histórico de todas as mudanças
- **Auditoria** — quem mudou o quê e quando
- **Rollback** — reverter com `git revert`
- **Documentação** — manifests descrevem o estado desejado

### ArgoCD

- **Monitora** o repositório Git a cada 3 minutos (ou webhook em tempo real)
- **Detecta** divergências entre Git e cluster
- **Sincroniza** automaticamente (com `automated: true`)
- **UI** para visualizar status, logs, triggerar syncs manualmente

### Kustomize

- **Overlay** de configuração sem necessidade de templates
- **image patches** para atualizar tags sem editar YAML manualmente
- Compatível com ArgoCD "out of the box"

---

## 🚀 Próximas Melhorias Futuras

- [ ] Configurar webhook no GitHub para sync em tempo real (vs polling a cada 3 min)
- [ ] Implementar policy pull requests (mudar imagens apenas via PR, não direto)
- [ ] Adicionar notifications (Slack/Teams) quando sync falha
- [ ] Implementar GitOps secrets (sealed-secrets ou external-secrets para dados sensíveis)
- [ ] Multi-cluster ArgoCD (adicionar mais clusters além do lab)
