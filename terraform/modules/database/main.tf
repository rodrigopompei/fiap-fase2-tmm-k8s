# ---------------------------------------------------------------------------
# RDS PostgreSQL compartilhado
#
# Uma única instância hospeda os bancos de auth, flag e targeting. Os schemas
# em */db/init.sql não referenciam owners nem roles, então um master user único
# atende os três sem alteração de código: cada serviço continua lendo apenas a
# sua própria DATABASE_URL.
#
# Em produção o isolamento por instância (ou ao menos por role) é preferível;
# aqui a consolidação existe para caber no orçamento do Learner Lab.
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "this" {
  name        = "${var.identifier}-subnet-group"
  description = "Subnet group para ${var.identifier}"
  subnet_ids  = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.identifier}-subnet-group"
  })
}

resource "aws_security_group" "this" {
  name        = "${var.identifier}-sg"
  description = "Permite PostgreSQL apenas a partir dos nodes do EKS"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.identifier}-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# count, e não for_each: os IDs de security group vêm do cluster EKS e só são
# conhecidos durante o apply. O for_each precisa das chaves no momento do plan
# e falharia com "Invalid for_each argument"; o count só precisa do tamanho da
# lista, que é estático.
resource "aws_vpc_security_group_ingress_rule" "postgres" {
  count = length(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "PostgreSQL a partir dos nodes do EKS"
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

# A senha entra numa URL postgres://user:senha@host:5432/db, então o conjunto
# de caracteres especiais fica restrito a "-" e "_": ambos são unreserved no
# RFC 3986 e passam sem escape. Caracteres como / @ : # % ou " quebrariam o
# parsing da connection string (ou pior, a truncariam silenciosamente).
resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "-_"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 1
}

resource "aws_db_instance" "this" {
  identifier = var.identifier

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = var.storage_encrypted

  db_name  = var.initial_database_name
  username = var.master_username
  password = random_password.master.result
  port     = var.port

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period = var.backup_retention_period
  skip_final_snapshot     = var.skip_final_snapshot
  deletion_protection     = var.deletion_protection

  # Aplica upgrades de versão menor automaticamente, o que permite fixar
  # engine_version apenas na major (ex: "16").
  auto_minor_version_upgrade = true
  apply_immediately          = var.apply_immediately

  # Performance Insights tem custo além do free tier; desligado por padrão.
  performance_insights_enabled = var.performance_insights_enabled

  tags = merge(var.tags, {
    Name = var.identifier
  })
}
