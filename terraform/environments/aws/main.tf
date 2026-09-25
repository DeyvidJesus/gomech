terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state for shared use. Create the bucket once, then uncomment:
  # backend "s3" {
  #   bucket = "gomech-tfstate"
  #   key    = "aws/production/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region = var.aws_region
}

module "aws_infrastructure" {
  source = "../../modules/aws"

  aws_region           = var.aws_region
  environment          = var.environment
  app_name             = var.app_name
  db_password          = var.db_password
  jwt_secret           = var.jwt_secret
  gemini_api_key       = var.gemini_api_key
  service_auth_secret  = var.service_auth_secret
  google_client_id     = var.google_client_id
  google_client_secret = var.google_client_secret
  backend_image        = var.backend_image
  ai_service_image     = var.ai_service_image
}
