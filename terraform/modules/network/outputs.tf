output "vpc_id" {
  description = "ID da VPC criada."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR da VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs das subnets públicas (onde o ALB internet-facing é criado)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas (nodes do EKS, RDS e ElastiCache)."
  value       = aws_subnet.private[*].id
}

output "availability_zones" {
  description = "AZs efetivamente utilizadas."
  value       = local.azs
}

output "nat_gateway_public_ips" {
  description = "IPs públicos dos NAT Gateways. Útil para liberar acesso em firewalls externos."
  value       = aws_eip.nat[*].public_ip
}
