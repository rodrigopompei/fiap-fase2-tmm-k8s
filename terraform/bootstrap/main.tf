# ---------------------------------------------------------------------------
# Bootstrap do backend remoto
#
# Stack separada, com state LOCAL, porque ela cria a própria infraestrutura de
# state da stack principal. Rode uma única vez, antes de tudo.
#
# O bucket carrega o ID da conta no nome porque o namespace do S3 é global.
# ---------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

locals {
  bucket_name = coalesce(
    var.state_bucket_name,
    "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}",
  )

  common_tags = {
    Project   = var.project
    Purpose   = "terraform-state"
    ManagedBy = "terraform"
  }
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  # Protege o state contra terraform destroy acidental nesta stack.
  # Para remover de verdade: comente o bloco, aplique, e então destrua.
  lifecycle {
    prevent_destroy = true
  }

  tags = local.common_tags
}

# Versionamento é o que permite recuperar um state corrompido ou sobrescrito.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# O state contém senha do RDS e MASTER_KEY em texto claro. Criptografia em
# repouso aqui não é opcional.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Expira versões antigas do state para o bucket não crescer indefinidamente.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

# Lock distribuído: impede dois apply simultâneos de corromperem o state.
# A partition key precisa se chamar exatamente LockID.
resource "aws_dynamodb_table" "lock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = local.common_tags
}

# Gera o backend.hcl consumido pela stack principal, evitando copiar os nomes
# à mão: terraform init -backend-config=backend.hcl
resource "local_file" "backend_config" {
  filename        = "${path.module}/../backend.hcl"
  file_permission = "0644"

  content = <<-EOT
    # Gerado por terraform/bootstrap. Não edite à mão.
    bucket         = "${aws_s3_bucket.state.id}"
    key            = "${var.state_key}"
    region         = "${var.aws_region}"
    dynamodb_table = "${aws_dynamodb_table.lock.name}"
    encrypt        = true
  EOT
}
