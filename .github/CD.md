# Continuous Deployment (CD) com GitOps & ArgoCD

## Visão Geral

O CD é baseado em **GitOps**: a fonte única de verdade é um repositório Git. Quando a imagem muda no ECR, a CI pipeline atualiza o arquivo `kustomization.yaml` no Git, e o ArgoCD automaticamente sincroniza as mudanças para o cluster.

**Fluxo:**

```
Developer push → CI builds image + pushes ECR → CI updates Git tag
                                                     ↓
                                              ArgoCD detects change
                                                     ↓
                                           Cluster syncs automatically
```

## Setup: Pré-requisitos

1. **Terraform com ArgoCD habilitado:**
   ```bash
   cd terraform
   echo 'enable_argocd = true' >> terraform.tfvars
   terraform apply -auto-approve -input=false
   ```

2. **ArgoCD Applications registradas:**
   ```bash
   kubectl apply -f gitops/argocd/applications.yaml
   ```

3. **ArgoCD UI acessível:**
   ```bash
   kubectl port-forward -n argocd svc/argocd-server 8080:443
   # Acesse: https://localhost:8080
   ```

## CI Pipeline Integration

Cada workflow de CI (`.github/workflows/<service>.yml`) precisa ser atualizado para chamar o script `gitops/update-image-tag.sh` após fazer push da imagem para ECR.

### Exemplo: Adicionar CD ao workflow do flag-service

No job `docker`, após o step `🚀 Tag e push para o ECR`, adicione:

```yaml
      - name: 🔄 Atualizar tag GitOps
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        run: |
          # Calcular a tag (mesmo formato do Docker)
          SHA="${{ github.sha }}"
          SHORT_SHA="${SHA:0:7}"
          IMAGE_TAG="v${SERVICE_VERSION}-${SHORT_SHA}"
          
          # Atualizar o arquivo kustomization.yaml
          ./gitops/update-image-tag.sh ${{ env.SERVICE_NAME }} "$IMAGE_TAG"

      - name: 📝 Commit e push das mudanças GitOps
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        run: |
          git config user.name "GitHub Actions"
          git config user.email "actions@github.com"
          
          if [ -n "$(git status --porcelain)" ]; then
            git add gitops/apps/${{ env.SERVICE_NAME }}/kustomization.yaml
            git commit -m "chore: bump ${{ env.SERVICE_NAME }} to ${{ env.SERVICE_VERSION }}-${SHA:0:7}"
            git push origin main
          else
            echo "Sem mudanças na tag de imagem"
          fi
```

### Full Example: flag-service workflow com CD

Ver em `.github/workflows/flag-service.yml` (jobs `docker`), adicione após `🚀 Tag e push para o ECR`:

```yaml
  docker:
    name: 🐳 Docker Build, Scan & Push
    runs-on: ubuntu-latest
    needs: [build-test, lint, security-scan]
    steps:
      # ... steps anteriores ...
      
      - name: 🚀 Tag e push para o ECR
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        env:
          REGISTRY: ${{ steps.ecr.outputs.registry }}
          TAG: ${{ steps.meta.outputs.tag }}
        run: |
          # ... comandos de push ...
          docker push "$REGISTRY/$ECR_REPOSITORY:$TAG"
          docker push "$REGISTRY/$ECR_REPOSITORY:latest"

      # 🆕 CD: Atualizar GitOps
      - name: 🔄 Atualizar tag GitOps
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        run: |
          SHA="${{ github.sha }}"
          SHORT_SHA="${SHA:0:7}"
          IMAGE_TAG="v${SERVICE_VERSION}-${SHORT_SHA}"
          
          # Chamar o script de atualização
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

## Monitoramento: ArgoCD UI

### 1. Acessar o Dashboard

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
# https://localhost:8080 (ignore SSL warning)
```

Login:
- **Username:** admin
- **Password:** 
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d
  ```

### 2. Ver as 5 Aplicações

Na página principal (Applications), veja:

```
auth-service              ✅ Synced    (Healthy)
flag-service              ✅ Synced    (Healthy)
evaluation-service        🟡 OutOfSync (Healthy)  ← mudança detectada
targeting-service         ✅ Synced    (Healthy)
analytics-service         ✅ Synced    (Healthy)
```

Clique em qualquer uma para ver:
- **Sync Status:** Synced / OutOfSync / Unknown
- **Health:** Healthy / Degraded / Unknown
- **Repository:** https://github.com/rodrigopompei/fiap-fase2-tmm-k8s
- **Revision:** main
- **Path:** gitops/apps/<service>
- **Recursos:** Deployment, Service, Ingress, etc.

### 3. Sincronizar Manualmente (se necessário)

Na tela da aplicação, clique **Sync** → **Synchronize**

Ou via CLI:
```bash
# Requer argocd CLI
argocd app sync flag-service
```

## Troubleshooting

### Aplicação fica "OutOfSync"

**Causa comum:** A CI pipeline atualizou a tag no Git, mas ArgoCD ainda não detectou.

**Solução:**

```bash
# Forçar busca do repositório
argocd app get flag-service --refresh

# Ou via UI: Aplicação > ⚙️ > Refresh
```

### Sync falha com erro de imagem

```bash
kubectl describe pod -n flag-service
# Procure por "ImagePullBackOff"
```

**Causas:**
1. Imagem não existe no ECR — aguarde a CI terminar
2. Permissão de ECR — verificar security group / IAM
3. Credenciais expiradas no Learner Lab — atualizar secrets

### Webhook de GitHub não funciona

Se argocd/applications.yaml tem `ref: main`, ArgoCD faz polling a cada 3 minutos.

Para um push a `webhook.argocd.io` em tempo real, é necessário:

```bash
# 1. Exposer ArgoCD externamente
kubectl port-forward -n argocd svc/argocd-server 8080:443

# 2. Configurar webhook no GitHub:
# Repo → Settings → Webhooks → Add webhook
# Payload URL: https://<argocd-external-url>/api/webhook
# Content type: application/json
# Events: Push events
```

## Dicas

- **Auto-sync habilitado** — ArgoCD sincroniza automaticamente quando detecta mudanças
- **Prune habilitado** — remove recursos no cluster que não estão mais no Git (cuidado!)
- **Self-heal habilitado** — reaplica manifests se o cluster divergir

Ver em `gitops/argocd/applications.yaml`:

```yaml
syncPolicy:
  automated:
    prune: true      # Remove recursos deletados
    selfHeal: true   # Reaplica se cluster divergir
```

## Próximos Passos

1. ✅ Instalar ArgoCD no cluster
2. ✅ Registrar as 5 aplicações
3. ⏳ Integrar CD nos workflows de CI (adicionar steps acima)
4. ⏳ Testar: fazer push de uma mudança e ver a sincronização
5. ⏳ Documentar runbook de troubleshooting para a equipe
