output "cluster_name" {
  description = "Nome do cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Endpoint HTTPS da API do Kubernetes."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Certificate authority do cluster, em base64."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_version" {
  description = "Versão do Kubernetes em execução."
  value       = aws_eks_cluster.this.version
}

output "cluster_security_group_id" {
  description = "Security group primário criado pelo EKS. É o SG efetivo dos nodes de um managed node group sem launch template, portanto é a origem correta nas regras de ingress do RDS e do ElastiCache."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_issuer_url" {
  description = "URL do OIDC issuer do cluster."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN do OIDC provider IAM. Nulo quando enable_irsa = false."
  value       = var.enable_irsa ? aws_iam_openid_connect_provider.this[0].arn : null
}

output "node_group_name" {
  description = "Nome do managed node group."
  value       = aws_eks_node_group.this.node_group_name
}
