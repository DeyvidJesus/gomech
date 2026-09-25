variable "aws_region" {
  description = "AWS Region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (production, staging, dev)"
  type        = string
  default     = "production"
}

variable "app_name" {
  description = "Application base name"
  type        = string
  default     = "gomech"
}

variable "db_password" {
  description = "Password for PostgreSQL database user"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "JWT Secret key for HMAC-SHA256 authentication"
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
  description = "Shared secret the backend AI Gateway presents to the AI service"
  type        = string
  sensitive   = true
}

variable "backend_image" {
  description = "ECR Image URI for Spring Boot Backend"
  type        = string
  default     = "public.ecr.aws/gomech/backend:latest"
}

variable "ai_service_image" {
  description = "ECR Image URI for FastAPI AI Service"
  type        = string
  default     = "public.ecr.aws/gomech/ai-service:latest"
}

variable "google_client_id" {
  description = "Google OAuth 2.0 client ID (optional)"
  type        = string
  default     = ""
}

variable "google_client_secret" {
  description = "Google OAuth 2.0 client secret (optional)"
  type        = string
  sensitive   = true
  default     = ""
}
