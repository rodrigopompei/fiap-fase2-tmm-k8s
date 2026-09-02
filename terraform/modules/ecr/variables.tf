variable "repository_names" {
  description = "Nomes dos repositórios ECR a criar (ex: fiap-fase2/auth-service)."
  type        = list(string)
}

variable "image_tag_mutability" {
  description = "MUTABLE ou IMMUTABLE. IMMUTABLE impede sobrescrever uma tag já publicada, forçando o versionamento das imagens."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability precisa ser MUTABLE ou IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Executa scan de vulnerabilidades a cada push."
  type        = bool
  default     = true
}

variable "force_delete" {
  description = "Permite destruir repositórios que ainda contêm imagens."
  type        = bool
  default     = true
}

variable "keep_last_n_images" {
  description = "Quantidade de imagens mais recentes preservadas pela lifecycle policy."
  type        = number
  default     = 10
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos do módulo."
  type        = map(string)
  default     = {}
}
