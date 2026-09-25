terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  # Spring profiles are named prod/staging/dev (backend/src/main/resources/application-*.yml).
  spring_profile = lookup({ production = "prod", staging = "staging", dev = "dev" }, var.environment, var.environment)

  tags = {
    Environment = var.environment
    Application = var.app_name
  }
}

# 1. SECRETS MANAGER
resource "aws_secretsmanager_secret" "app_secrets" {
  name = "${var.app_name}-secrets-${var.environment}"
  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "app_secrets_val" {
  secret_id = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode({
    DB_PASSWORD          = var.db_password
    JWT_SECRET           = var.jwt_secret
    GEMINI_API_KEY       = var.gemini_api_key
    SERVICE_AUTH_SECRET  = var.service_auth_secret
    GOOGLE_CLIENT_SECRET = var.google_client_secret
  })
}

# 2. APP RUNNER INSTANCE ROLE (reads the secrets above at startup)
data "aws_iam_policy_document" "apprunner_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["tasks.apprunner.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apprunner_instance" {
  name               = "${var.app_name}-apprunner-instance-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.apprunner_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "read_app_secrets" {
  name = "read-app-secrets"
  role = aws_iam_role.apprunner_instance.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.app_secrets.arn
    }]
  })
}

# 3. AMAZON RDS (PostgreSQL 16)
# publicly_accessible keeps the study setup simple (App Runner reaches RDS over the internet,
# SSL-only on the application side). A production setup would place RDS in private subnets and
# attach an App Runner VPC connector.
resource "aws_db_instance" "postgres" {
  identifier            = "${var.app_name}-db-${var.environment}"
  engine                = "postgres"
  engine_version        = "16"
  instance_class        = "db.t4g.medium"
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  db_name               = "${var.app_name}_${var.environment}"
  username              = "gomech_admin"
  password              = var.db_password
  multi_az              = var.environment == "production"
  publicly_accessible   = true
  skip_final_snapshot   = var.environment != "production"
  storage_encrypted     = true
  deletion_protection   = var.environment == "production"

  tags = local.tags
}

# 4. AWS APP RUNNER: AI SERVICE (FastAPI)
resource "aws_apprunner_service" "ai_service" {
  service_name = "${var.app_name}-ai-service-${var.environment}"

  source_configuration {
    auto_deployments_enabled = false

    image_repository {
      image_identifier      = var.ai_service_image
      image_repository_type = "ECR_PUBLIC"

      image_configuration {
        port = "8000"
        runtime_environment_variables = {
          DEFAULT_PROVIDER = var.gemini_api_key != "" ? "gemini" : "mock"
        }
        runtime_environment_secrets = {
          GEMINI_API_KEY      = "${aws_secretsmanager_secret.app_secrets.arn}:GEMINI_API_KEY::"
          SERVICE_AUTH_SECRET = "${aws_secretsmanager_secret.app_secrets.arn}:SERVICE_AUTH_SECRET::"
        }
      }
    }
  }

  instance_configuration {
    cpu               = "1 vCPU"
    memory            = "2 GB"
    instance_role_arn = aws_iam_role.apprunner_instance.arn
  }

  health_check_configuration {
    protocol = "HTTP"
    path     = "/health"
  }

  tags = local.tags
}

# 5. AWS APP RUNNER: BACKEND (Spring Boot 3)
resource "aws_apprunner_service" "backend" {
  service_name = "${var.app_name}-backend-${var.environment}"

  source_configuration {
    auto_deployments_enabled = false

    image_repository {
      image_identifier      = var.backend_image
      image_repository_type = "ECR_PUBLIC"

      image_configuration {
        port = "8080"
        runtime_environment_variables = {
          SPRING_PROFILES_ACTIVE = local.spring_profile
          DB_HOST                = aws_db_instance.postgres.address
          DB_PORT                = tostring(aws_db_instance.postgres.port)
          DB_NAME                = aws_db_instance.postgres.db_name
          DB_USER                = aws_db_instance.postgres.username
          GOOGLE_CLIENT_ID       = var.google_client_id
          GOOGLE_REDIRECT_URI    = "https://${aws_cloudfront_distribution.frontend_cdn.domain_name}/auth/callback/google"
          GOMECH_AI_BASE_URL     = "https://${aws_apprunner_service.ai_service.service_url}"
        }
        runtime_environment_secrets = {
          DB_PASSWORD              = "${aws_secretsmanager_secret.app_secrets.arn}:DB_PASSWORD::"
          JWT_SECRET               = "${aws_secretsmanager_secret.app_secrets.arn}:JWT_SECRET::"
          GOOGLE_CLIENT_SECRET     = "${aws_secretsmanager_secret.app_secrets.arn}:GOOGLE_CLIENT_SECRET::"
          GOMECH_AI_SERVICE_SECRET = "${aws_secretsmanager_secret.app_secrets.arn}:SERVICE_AUTH_SECRET::"
        }
      }
    }
  }

  instance_configuration {
    cpu               = "2 vCPU"
    memory            = "4 GB"
    instance_role_arn = aws_iam_role.apprunner_instance.arn
  }

  health_check_configuration {
    protocol = "HTTP"
    path     = "/actuator/health"
  }

  tags = local.tags
}

# 6. AMAZON S3 + CLOUDFRONT (Frontend SPA)
# The bucket stays private; CloudFront reads it through an Origin Access Identity.
resource "aws_s3_bucket" "frontend_bucket" {
  bucket = "${var.app_name}-frontend-${var.environment}-${var.aws_region}"
  tags   = local.tags
}

resource "aws_s3_bucket_public_access_block" "frontend_bucket" {
  bucket                  = aws_s3_bucket.frontend_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for ${var.app_name} frontend"
}

resource "aws_s3_bucket_policy" "frontend_policy" {
  bucket = aws_s3_bucket.frontend_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAI"
        Effect = "Allow"
        Principal = {
          AWS = aws_cloudfront_origin_access_identity.oai.iam_arn
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend_bucket.arn}/*"
      }
    ]
  })
}

resource "aws_cloudfront_distribution" "frontend_cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.frontend_bucket.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.frontend_bucket.id}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.frontend_bucket.id}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  # SPA routing: unknown paths fall back to index.html. A private bucket answers 403 (not 404)
  # for missing keys, so both codes are mapped.
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = local.tags
}
