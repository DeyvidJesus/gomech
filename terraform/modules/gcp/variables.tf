variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "Google Cloud region for every regional resource"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Deployment environment (production, staging, dev)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "dev"], var.environment)
    error_message = "environment must be one of: production, staging, dev."
  }
}

variable "app_name" {
  description = "Base name used to prefix every resource"
  type        = string
  default     = "gomech"
}

variable "db_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-custom-2-7680"
}

variable "db_authorized_networks" {
  description = "CIDR ranges allowed to reach the Cloud SQL public IP (connections are SSL-only)"
  type = list(object({
    name = string
    cidr = string
  }))
  default = []
}

variable "db_password" {
  description = "Password for the PostgreSQL application user"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "HMAC-SHA256 key used to sign JWT access tokens"
  type        = string
  sensitive   = true
}

variable "service_auth_secret" {
  description = "Shared secret the backend AI Gateway presents to the AI service"
  type        = string
  sensitive   = true
}

variable "gemini_api_key" {
  description = "Google Gemini API key; when empty the AI service runs with the mock provider"
  type        = string
  sensitive   = true
  default     = ""
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

variable "backend_image" {
  description = "Container image for the Spring Boot backend"
  type        = string
}

variable "ai_service_image" {
  description = "Container image for the FastAPI AI service"
  type        = string
}

variable "frontend_image" {
  description = "Container image for the React SPA (nginx)"
  type        = string
}
