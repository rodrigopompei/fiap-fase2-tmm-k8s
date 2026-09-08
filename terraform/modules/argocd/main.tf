# ─────────────────────────────────────────────────────────────────────────────
# ArgoCD: GitOps contínuo para Kubernetes
#
# Instala ArgoCD no cluster EKS via Helm. Após a instalação, adicione as
# aplicações (ArgoCD Applications) no repositório Git:
#
#   kubectl apply -f gitops/argocd/applications.yaml
#
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

# Namespace para ArgoCD
resource "kubernetes_namespace" "argocd" {
  count = var.enable_argocd ? 1 : 0

  metadata {
    name = "argocd"
    labels = {
      "app.kubernetes.io/name"       = "argocd"
      "app.kubernetes.io/part-of"    = "argocd"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# Helm Release: ArgoCD
resource "helm_release" "argocd" {
  count = var.enable_argocd ? 1 : 0

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = kubernetes_namespace.argocd[0].metadata[0].name
  create_namespace = false
  version          = "6.0.0"  # Pinned version for reproducibility

  # Values para ArgoCD
  values = [
    yamlencode({
      # Desabilita RBAC por padrão no Learner Lab (ajustar conforme necessário)
      global = {
        logging = {
          level = "info"
        }
      }

      # Servidor ArgoCD (API + UI)
      server = {
        service = {
          type = "LoadBalancer"  # Expõe via ALB para acessar a UI
        }

        # Ingress (opcional, pode ser usando LoadBalancer acima)
        ingress = {
          enabled = false
        }

        # Desabilita autenticação para lab (IMPORTANTE: use com cuidado)
        rbac = {
          enabled = false
        }

        # Configurações do servidor
        config = {
          # URL base para callbacks de webhook
          "url" = "http://localhost"
        }
      }

      # Controlador de repositórios
      repoServer = {
        replicas = 1
      }

      # Controlador de aplicações
      controller = {
        replicas = 1
      }

      # Desabilita notificador por padrão
      notifications = {
        enabled = false
      }

      # Resource limits (ajuste para lab)
      resources = {
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.argocd]
}

# Saída: Endereço do ArgoCD (via LoadBalancer)
output "argocd_server_url" {
  description = "URL do servidor ArgoCD"
  value = var.enable_argocd ? try(
    "http://${helm_release.argocd[0].status[0].notes}",
    "kubectl port-forward -n argocd svc/argocd-server 8080:443"
  ) : null
}

output "argocd_namespace" {
  description = "Namespace do ArgoCD"
  value       = var.enable_argocd ? kubernetes_namespace.argocd[0].metadata[0].name : null
}
