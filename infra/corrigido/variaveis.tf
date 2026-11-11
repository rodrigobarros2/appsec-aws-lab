variable "regiao" {
  description = "Região AWS"
  type        = string
  default     = "sa-east-1"
}

variable "ambiente" {
  description = "Nome curto do ambiente (entra no nome dos recursos)"
  type        = string
  default     = "lab"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,12}$", var.ambiente))
    error_message = "Use de 2 a 12 caracteres: letras minúsculas, números e hífen."
  }
}

variable "limite_requisicoes_por_ip" {
  description = "Requisições por IP a cada 5 minutos antes do bloqueio no WAF"
  type        = number
  default     = 1000
}
