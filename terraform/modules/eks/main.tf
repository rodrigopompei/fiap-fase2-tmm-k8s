# ---------------------------------------------------------------------------
# Cluster EKS
#
# Este módulo NÃO cria IAM roles: ele as recebe prontas via variável. Isso é o
# que o torna utilizável no AWS Academy Learner Lab, onde iam:CreateRole é
# negado e a única role disponível é a pré-provisionada LabRole.
# ---------------------------------------------------------------------------
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = var.cluster_role_arn

  vpc_config {
    subnet_ids = var.subnet_ids

    # O endpoint público é necessário para rodar kubectl/helm da sua máquina.
    # O privado mantém o tráfego node -> control plane dentro da VPC.
    endpoint_public_access  = var.endpoint_public_access
    endpoint_private_access = var.endpoint_private_access
    public_access_cidrs     = var.public_access_cidrs
  }

  access_config {
    authentication_mode = var.authentication_mode

    # Concede admin ao principal que executa o apply (no Learner Lab, a role
    # "voclabs"). Sem isso você cria o cluster e não consegue usar kubectl.
    bootstrap_cluster_creator_admin_permissions = true
  }

  # Logs do control plane vão para o CloudWatch e são cobrados por GB ingerido.
  # Vazio por padrão para não consumir o orçamento do laboratório.
  enabled_cluster_log_types = var.enabled_cluster_log_types

  tags = merge(var.tags, {
    Name = var.cluster_name
  })
}

# ---------------------------------------------------------------------------
# Add-ons gerenciados pela AWS
#
# O vpc-cni entra antes do node group porque é ele que atribui IPs aos pods.
# O coredns entra depois, pois seus pods precisam de nodes para serem agendados.
# ---------------------------------------------------------------------------
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  depends_on = [aws_eks_node_group.this]
}

# ---------------------------------------------------------------------------
# Managed node group
#
# Em modo de autenticação por API, o EKS cria automaticamente o access entry
# (tipo EC2_LINUX) para a role dos nodes. Por isso não declaramos um
# aws_eks_access_entry aqui: um principal só pode ter UM access entry, e criar
# outro para a mesma role causaria conflito no apply.
# ---------------------------------------------------------------------------
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-ng"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids

  instance_types = var.instance_types
  capacity_type  = var.capacity_type
  disk_size      = var.disk_size

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-ng"
  })

  lifecycle {
    # desired_size pode ser alterado por autoscaler ou pela CLI; não queremos
    # que o Terraform reverta essa mudança no próximo apply.
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_eks_addon.vpc_cni]
}

# ---------------------------------------------------------------------------
# OIDC provider (IRSA)
#
# Desligado por padrão: no Learner Lab iam:CreateOpenIDConnectProvider é
# negado. Mantido aqui para que o mesmo módulo sirva numa conta sem guardrails.
# ---------------------------------------------------------------------------
data "tls_certificate" "oidc" {
  count = var.enable_irsa ? 1 : 0

  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  count = var.enable_irsa ? 1 : 0

  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc[0].certificates[0].sha1_fingerprint]

  tags = var.tags
}
