# ---------------------------------------------------------------------------
# ElastiCache Redis (single node)
#
# Usamos aws_elasticache_cluster em vez de replication_group: é o caminho mais
# barato para um único node. A contrapartida é que AUTH token e encryption in
# transit exigem um replication group, então aqui o Redis fica sem senha,
# protegido apenas pelo security group.
#
# É por isso que a REDIS_URL gerada não tem credencial. Se precisar de AUTH,
# troque para aws_elasticache_replication_group com transit_encryption_enabled.
# ---------------------------------------------------------------------------
resource "aws_elasticache_subnet_group" "this" {
  name        = "${var.name}-subnet-group"
  description = "Subnet group para ${var.name}"
  subnet_ids  = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.name}-subnet-group"
  })
}

resource "aws_security_group" "this" {
  name        = "${var.name}-sg"
  description = "Permite Redis apenas a partir dos nodes do EKS"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# count, e não for_each: os IDs de security group vêm do cluster EKS e só são
# conhecidos durante o apply. O for_each precisa das chaves no momento do plan
# e falharia com "Invalid for_each argument"; o count só precisa do tamanho da
# lista, que é estático.
resource "aws_vpc_security_group_ingress_rule" "redis" {
  count = length(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "Redis a partir dos nodes do EKS"
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
}

# A descricao NAO pode ter acentos: a EC2 aceita apenas
# a-zA-Z0-9. _-:/()#,@[]+=&;{}!$* e rejeita o resto com InvalidParameterValue.
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "Saida liberada"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_elasticache_cluster" "this" {
  cluster_id = var.name

  engine          = "redis"
  engine_version  = var.engine_version
  node_type       = var.node_type
  num_cache_nodes = 1
  port            = var.port

  parameter_group_name = var.parameter_group_name
  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = [aws_security_group.this.id]

  apply_immediately = var.apply_immediately

  tags = merge(var.tags, {
    Name = var.name
  })
}
