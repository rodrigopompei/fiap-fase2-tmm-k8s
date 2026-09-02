terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # Fixado na série 5.x de propósito: a 6.x renomeia atributos usados aqui
    # (entre eles data.aws_region.name).
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    # A série 3.x do provider helm troca os blocos "set" por atributos de
    # lista, o que quebraria o módulo addons.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
