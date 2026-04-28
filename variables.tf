###############################################################################
# Variables - n8n Workspace Corporativo
# Postgres en contenedor local (no RDS)
###############################################################################

# ============================================
# AWS / Proyecto
# ============================================
variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS profile to use for authentication."
  type        = string
  default     = "pflondon"
}

variable "stack_name" {
  description = "Name prefix used for resources."
  type        = string
  default     = "n8n"
}

variable "environment_name" {
  description = "Environment tag (dev, staging, prod)."
  type        = string
  default     = "dev"
}

# ============================================
# Networking
# ============================================
variable "vpc_cidr" {
  description = "CIDR block for the new VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string
  default     = "10.20.1.0/24"
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs permitidos para SSH (también para túnel a Postgres). RECOMENDADO: solo tu IP en producción."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ============================================
# DNS
# ============================================
variable "root_domain" {
  description = "Base domain (e.g. example.com). Debe existir como zona en Route53."
  type        = string
}

variable "subdomain" {
  description = "Subdomain para n8n."
  type        = string
  default     = "n8n"
}

# ============================================
# EC2
# ============================================
variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "Root volume size (GiB)."
  type        = number
  default     = 30
}

variable "data_volume_size" {
  description = "Data volume size (GiB) montado en /opt/n8n. Aquí vive Postgres."
  type        = number
  default     = 20
}

variable "docker_compose_version" {
  description = "Docker Compose CLI plugin version."
  type        = string
  default     = "v2.29.7"
}

variable "default_timezone" {
  description = "Timezone."
  type        = string
  default     = "America/Puerto_Rico"
}

# ============================================
# Postgres (contenedor local)
# ============================================
variable "postgres_password" {
  description = "Password de Postgres. Mínimo 16 chars. Genera con: openssl rand -base64 24 | tr -d '/+='"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.postgres_password) >= 12
    error_message = "El password debe tener al menos 12 caracteres."
  }
}

variable "postgres_bind" {
  description = <<-EOT
    Cómo se expone el puerto Postgres:
    - "127.0.0.1" (default): solo accesible vía túnel SSH (recomendado, más seguro)
    - "0.0.0.0": accesible desde internet en el puerto 5432 (requiere postgres_allowed_cidrs)
  EOT
  type        = string
  default     = "127.0.0.1"

  validation {
    condition     = contains(["127.0.0.1", "0.0.0.0"], var.postgres_bind)
    error_message = "Solo acepta '127.0.0.1' o '0.0.0.0'."
  }
}

variable "postgres_allowed_cidrs" {
  description = "CIDRs permitidos al puerto Postgres público. Solo aplica si postgres_bind=0.0.0.0. Saca tu IP con: curl ifconfig.me"
  type        = list(string)
  default     = []
}

# ============================================
# SMTP (para invitar usuarios al workspace)
# ============================================
variable "smtp_host" {
  description = "SMTP host (ej: smtp.gmail.com, email-smtp.us-east-1.amazonaws.com)."
  type        = string
}

variable "smtp_port" {
  description = "SMTP port. 465 SSL, 587 STARTTLS."
  type        = number
  default     = 465
}

variable "smtp_user" {
  description = "Usuario SMTP."
  type        = string
  sensitive   = true
}

variable "smtp_password" {
  description = "Password SMTP (App Password si es Gmail)."
  type        = string
  sensitive   = true
}

variable "smtp_sender" {
  description = "Email remitente. Ej: 'n8n <noreply@empresa.com>'."
  type        = string
}

# ============================================
# Let's Encrypt
# ============================================
variable "letsencrypt_email" {
  description = "Email para Let's Encrypt. Vacío para omitir."
  type        = string
  default     = ""
}

# ============================================
# Schedules (para ahorrar costos)
# ============================================
variable "stop_schedule_cron" {
  description = "Cron para apagar la EC2 (UTC). Ej: '0 7 * * ? *' = 2am Puerto Rico."
  type        = string
  default     = "cron(0 7 * * ? *)"
}

variable "start_schedule_cron" {
  description = "Cron para encender la EC2 (UTC). Ej: '0 11 * * ? *' = 6am Puerto Rico."
  type        = string
  default     = "cron(0 11 * * ? *)"
}
