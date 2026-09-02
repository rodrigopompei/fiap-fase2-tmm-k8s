provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# ---------------------------------------------------------------------------
# Providers do Kubernetes
#
# Ambos apontam para o cluster criado nesta mesma stack, o que cria uma ordem
# de dependência que o Terraform não resolve sozinho: a configuração de um
# provider precisa ser conhecida no momento do plan, e no primeiro apply o
# endpoint do cluster ainda não existe.
#
# Daí o apply em duas fases descrito no README:
#
#   1) terraform apply -target=module.network -target=module.eks
#   2) terraform apply
#
# Depois da fase 1 os valores estão no state e o plan da fase 2 resolve normalmente.
#
# O token vem do exec plugin em vez de data.aws_eks_cluster_auth porque
# credenciais do Learner Lab expiram a cada sessão: o plugin busca um token
# novo em cada invocação, sem deixar credencial no state.
# ---------------------------------------------------------------------------
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks", "get-token",
      "--cluster-name", var.cluster_name,
      "--region", var.aws_region,
    ]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks", "get-token",
        "--cluster-name", var.cluster_name,
        "--region", var.aws_region,
      ]
    }
  }
}
