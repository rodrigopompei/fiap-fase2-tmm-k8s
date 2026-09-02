output "address" {
  description = "Hostname do node Redis."
  value       = aws_elasticache_cluster.this.cache_nodes[0].address
}

output "port" {
  description = "Porta do Redis."
  value       = aws_elasticache_cluster.this.cache_nodes[0].port
}

output "redis_url" {
  description = "Connection string no formato esperado pelo evaluation-service. Sem credencial, pois o cluster não usa AUTH token."
  value       = "redis://${aws_elasticache_cluster.this.cache_nodes[0].address}:${aws_elasticache_cluster.this.cache_nodes[0].port}"
}

output "security_group_id" {
  description = "Security group do cluster."
  value       = aws_security_group.this.id
}
