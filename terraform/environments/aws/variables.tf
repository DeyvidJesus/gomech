variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "app_name" {
  description = "App base name"
  type        = string
  default     = "gomech"
}

variable "db_password" {
  description = "PostgreSQL DB password"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "JWT Secret"
  type        = string
  sensitive   = true
}

variable "gemini_api_key" {
  description = "Google Gemini API Key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "service_auth_secret" {
  description = "Internal HMAC shared secret for AI service"
  type        = string
  sensitive   = true
}

variable "backend_image" {
  type    = string
  default = "public.ecr.aws/gomech/backend:latest"
}

variable "ai_service_image" {
  type    = string
  default = "public.ecr.aws/gomech/ai-service:latest"
}

variable "google_client_id" {
  description = "Google OAuth 2.0 client ID"
  type        = string
  default     = ""
}

variable "google_client_secret" {
  description = "Google OAuth 2.0 client secret"
  type        = string
  sensitive   = true
  default     = ""
}
