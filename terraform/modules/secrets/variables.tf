variable "managed_secret_names" {
  description = "Nomes dos segredos cujo valor o Terraform controla. Precisa ser uma lista estática (não derivada de valores sensíveis), pois alimenta um for_each."
  type        = list(string)
  default     = []
}

variable "managed_secret_values" {
  description = "Mapa nome do segredo => valor. As chaves precisam cobrir managed_secret_names."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "external_secret_names" {
  description = "Nomes dos segredos criados com placeholder e preenchidos em runtime por outro processo."
  type        = list(string)
  default     = []
}

variable "external_secret_placeholder" {
  description = "Valor inicial dos segredos externos. Escolha algo que falhe de forma óbvia se for usado por engano."
  type        = string
  default     = "PREENCHER_EM_RUNTIME"
}

variable "recovery_window_in_days" {
  description = "Janela de recuperação no destroy: 0 apaga na hora, 7 a 30 mantém o nome reservado. Use 0 em laboratório para poder recriar a stack imediatamente."
  type        = number
  default     = 0

  validation {
    condition     = var.recovery_window_in_days == 0 || (var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30)
    error_message = "recovery_window_in_days precisa ser 0 ou um valor entre 7 e 30."
  }
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos do módulo."
  type        = map(string)
  default     = {}
}
