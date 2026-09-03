# ---------------------------------------------------------------------------
# Add-ons do cluster instalados via Helm
#
# IMPORTANTE (AWS Academy Learner Lab): nenhum dos ServiceAccounts abaixo
# recebe a anotação eks.amazonaws.com/role-arn. Isso é intencional.
#
# Sem IRSA, os pods obtêm credenciais AWS pelo IMDS do node, ou seja, herdam a
# role de instância (LabRole). Se anotássemos o ServiceAccount, o AWS SDK
# passaria a preferir o token de web identity, tentaria um
# AssumeRoleWithWebIdentity contra uma role que não existe e falharia — sem
# fazer fallback para a role do node. Anotação errada é pior que anotação
# nenhuma.
# ---------------------------------------------------------------------------

# Monta secrets do Secrets Manager como volume nos pods. Sem ele, todo pod que
# referencia um SecretProviderClass fica preso em ContainerCreating.
resource "helm_release" "secrets_store_csi_driver" {
  count = var.enable_secrets_store_csi_driver ? 1 : 0

  name       = "csi-secrets-store"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  version    = var.secrets_store_csi_driver_version
  namespace  = "kube-system"

  atomic          = true
  cleanup_on_fail = true
  timeout         = var.helm_timeout

  # syncSecret permite espelhar o conteúdo montado em um Secret nativo do
  # Kubernetes, que é o que os blocos secretObjects dos SecretProviderClass
  # deste projeto usam.
  set {
    name  = "syncSecret.enabled"
    value = "true"
  }

  set {
    name  = "enableSecretRotation"
    value = "true"
  }
}

# Plugin que traduz as chamadas do CSI Driver para a API do Secrets Manager.
resource "helm_release" "secrets_store_csi_driver_provider_aws" {
  count = var.enable_secrets_store_csi_driver ? 1 : 0

  name       = "secrets-provider-aws"
  repository = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart      = "secrets-store-csi-driver-provider-aws"
  version    = var.secrets_store_csi_provider_aws_version
  namespace  = "kube-system"

  atomic          = true
  cleanup_on_fail = true
  timeout         = var.helm_timeout

  # O chart do provider EMBUTE o secrets-store-csi-driver como subchart
  # (dependencia com condition secrets-store-csi-driver.install, default true).
  # Como o driver ja e instalado pelo release acima, deixar o subchart ligado
  # faz os dois disputarem o ServiceAccount "secrets-store-csi-driver" e o
  # apply falha com "invalid ownership metadata".
  set {
    name  = "secrets-store-csi-driver.install"
    value = "false"
  }

  depends_on = [helm_release.secrets_store_csi_driver]
}

# Observa recursos Ingress e provisiona o ALB de verdade na AWS. Os Ingress
# deste projeto compartilham um único ALB via
# alb.ingress.kubernetes.io/group.name.
resource "helm_release" "aws_load_balancer_controller" {
  count = var.enable_aws_load_balancer_controller ? 1 : 0

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.aws_load_balancer_controller_version
  namespace  = "kube-system"

  atomic          = true
  cleanup_on_fail = true
  timeout         = var.helm_timeout

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  # O chart cria o ServiceAccount sem anotação de role: as permissões de ELB
  # vêm da role de instância dos nodes. Não aplique
  # K8s/base/alb-controller/serviceaccount.yaml, que anota uma role IRSA
  # inexistente no Learner Lab.
  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
}

# Autoscaling do analytics-service por profundidade da fila SQS.
resource "helm_release" "keda" {
  count = var.enable_keda ? 1 : 0

  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = var.keda_version
  namespace        = var.keda_namespace
  create_namespace = true

  atomic          = true
  cleanup_on_fail = true
  timeout         = var.helm_timeout
}
