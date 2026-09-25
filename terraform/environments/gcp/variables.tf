variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "Google Cloud region"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Deployment environment (production, staging, dev)"
  type        = string
  default     = "production"
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
  description = "CIDR ranges allowed to reach the Cloud SQL public IP"
  type = list(object({
    name = string
    cidr = string
  }))
  default = []
}

variable "db_password" {
  description = "PostgreSQL application user password"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "JWT signing key"
  type        = string
  sensitive   = true
}

variable "service_auth_secret" {
  description = "Shared secret between the backend AI Gateway and the AI service"
  type        = string
  sensitive   = true
}

variable "gemini_api_key" {
  description = "Google Gemini API key (empty = mock provider)"
  type        = string
  sensitive   = true
  default     = ""
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

variable "backend_image" {
  description = "Backend image, e.g. us-central1-docker.pkg.dev/<project>/gomech-repo/backend:<tag>"
  type        = string
}

variable "ai_service_image" {
  description = "AI service image, e.g. us-central1-docker.pkg.dev/<project>/gomech-repo/ai-service:<tag>"
  type        = string
}

variable "frontend_image" {
  description = "Frontend image, e.g. us-central1-docker.pkg.dev/<project>/gomech-repo/frontend:<tag>"
  type        = string
}
