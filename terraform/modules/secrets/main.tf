# ---------------------------------------------------------------------------
# AWS Secrets Manager
#
# Dois tipos de segredo, e a diferença importa:
#
#   managed  - o Terraform é a fonte da verdade (DATABASE_URL, REDIS_URL,
#              MASTER_KEY). Derivam de recursos do próprio state, então o
#              Terraform pode e deve reconciliar o valor a cada apply.
#
#   external - criados vazios e preenchidos em runtime por quem tem a
#              informação (SERVICE_API_KEY só existe depois que o auth-service
#              está no ar e emite a chave). Levam ignore_changes no
#              secret_string para que um apply seguinte não sobrescreva o
#              valor real com o placeholder.
#
# Nota sobre o for_each: os nomes vêm em uma lista separada dos valores porque
# o Terraform proíbe usar valores sensíveis (ou derivados deles) como chave de
# for_each. Iterar sobre o mapa de valores falharia no plan.
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "managed" {
  for_each = toset(var.managed_secret_names)

  name        = each.value
  description = "Gerenciado pelo Terraform - ${each.value}"

  # 0 remove imediatamente no destroy. Com o padrão de 7 dias, o nome fica
  # reservado e um apply seguinte falha com InvalidRequestException.
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, {
    Name = each.value
  })
}

resource "aws_secretsmanager_secret_version" "managed" {
  for_each = toset(var.managed_secret_names)

  secret_id     = aws_secretsmanager_secret.managed[each.value].id
  secret_string = var.managed_secret_values[each.value]
}

resource "aws_secretsmanager_secret" "external" {
  for_each = toset(var.external_secret_names)

  name        = each.value
  description = "Criado pelo Terraform, valor definido em runtime - ${each.value}"

  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, {
    Name = each.value
  })
}

resource "aws_secretsmanager_secret_version" "external" {
  for_each = toset(var.external_secret_names)

  secret_id     = aws_secretsmanager_secret.external[each.value].id
  secret_string = var.external_secret_placeholder

  lifecycle {
    ignore_changes = [secret_string]
  }
}
