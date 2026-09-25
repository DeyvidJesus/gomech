terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Remote state for shared use. Create the bucket once, then uncomment:
  # backend "gcs" {
  #   bucket = "gomech-tfstate"
  #   prefix = "gcp/production"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "gcp_infrastructure" {
  source = "../../modules/gcp"

  project_id             = var.project_id
  region                 = var.region
  environment            = var.environment
  app_name               = var.app_name
  db_tier                = var.db_tier
  db_authorized_networks = var.db_authorized_networks
  db_password            = var.db_password
  jwt_secret             = var.jwt_secret
  service_auth_secret    = var.service_auth_secret
  gemini_api_key         = var.gemini_api_key
  google_client_id       = var.google_client_id
  google_client_secret   = var.google_client_secret
  backend_image          = var.backend_image
  ai_service_image       = var.ai_service_image
  frontend_image         = var.frontend_image
}
