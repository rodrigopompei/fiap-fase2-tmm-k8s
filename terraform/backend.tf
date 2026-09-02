# Backend S3 com lock em DynamoDB.
#
# A configuração é parcial: um bloco backend não aceita variáveis nem
# interpolação, e o nome do bucket depende do ID da conta. Os valores vêm de
# backend.hcl, gerado pela stack em bootstrap/:
#
#   terraform init -backend-config=backend.hcl
#
terraform {
  backend "s3" {}
}
