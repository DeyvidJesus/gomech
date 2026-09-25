terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

locals {
  # Spring profiles are named prod/staging/dev (backend/src/main/resources/application-*.yml),
  # while resource names use the long environment name.
  spring_profile = lookup({ production = "prod", staging = "staging", dev = "dev" }, var.environment, var.environment)

  required_apis = [
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "sqladmin.googleapis.com",
  ]

  # Secret names are a plain list so they can drive for_each; the values are sensitive and are
  # looked up by key.
  secret_names = ["db-password", "jwt-secret", "service-auth-secret", "gemini-api-key", "google-client-secret"]
  secret_values = {
    "db-password"          = var.db_password
    "jwt-secret"           = var.jwt_secret
    "service-auth-secret"  = var.service_auth_secret
    "gemini-api-key"       = var.gemini_api_key != "" ? var.gemini_api_key : "disabled"
    "google-client-secret" = var.google_client_secret != "" ? var.google_client_secret : "disabled"
  }

  # Each runtime identity can read only the secrets it needs.
  secret_access = {
    backend = ["db-password", "jwt-secret", "service-auth-secret", "google-client-secret"]
    ai      = ["service-auth-secret", "gemini-api-key"]
  }
  secret_bindings = merge([
    for identity, names in local.secret_access : {
      for name in names : "${identity}-${name}" => { identity = identity, secret = name }
    }
  ]...)
}

# 1. PROJECT APIS
resource "google_project_service" "apis" {
  for_each           = toset(local.required_apis)
  service            = each.value
  disable_on_destroy = false
}

# 2. ARTIFACT REGISTRY
resource "google_artifact_registry_repository" "docker_repo" {
  location      = var.region
  repository_id = "${var.app_name}-repo"
  description   = "Docker container repository for ${var.app_name}"
  format        = "DOCKER"

  depends_on = [google_project_service.apis]
}

# 3. RUNTIME IDENTITIES
resource "google_service_account" "backend" {
  account_id   = "${var.app_name}-backend-sa"
  display_name = "${var.app_name} backend (Cloud Run)"
}

resource "google_service_account" "ai_service" {
  account_id   = "${var.app_name}-ai-sa"
  display_name = "${var.app_name} AI service (Cloud Run)"
}

locals {
  identity_emails = {
    backend = google_service_account.backend.email
    ai      = google_service_account.ai_service.email
  }
}

# 4. SECRET MANAGER
resource "google_secret_manager_secret" "app" {
  for_each  = toset(local.secret_names)
  secret_id = "${var.app_name}-${each.key}-${var.environment}"

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "app" {
  for_each    = toset(local.secret_names)
  secret      = google_secret_manager_secret.app[each.key].id
  secret_data = local.secret_values[each.key]
}

resource "google_secret_manager_secret_iam_member" "access" {
  for_each  = local.secret_bindings
  secret_id = google_secret_manager_secret.app[each.value.secret].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.identity_emails[each.value.identity]}"
}

# 5. CLOUD SQL (PostgreSQL 16)
resource "google_sql_database_instance" "postgres" {
  name             = "${var.app_name}-db-${var.environment}"
  database_version = "POSTGRES_16"
  region           = var.region

  settings {
    tier              = var.db_tier
    availability_type = var.environment == "production" ? "REGIONAL" : "ZONAL"
    disk_size         = 20
    disk_type         = "PD_SSD"

    backup_configuration {
      enabled    = true
      start_time = "03:00"
    }

    ip_configuration {
      ipv4_enabled = true
      ssl_mode     = "ENCRYPTED_ONLY"

      dynamic "authorized_networks" {
        for_each = var.db_authorized_networks
        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.cidr
        }
      }
    }
  }

  deletion_protection = var.environment == "production"

  depends_on = [google_project_service.apis]
}

resource "google_sql_database" "database" {
  name     = "${var.app_name}_${var.environment}"
  instance = google_sql_database_instance.postgres.name
}

resource "google_sql_user" "db_user" {
  name     = "gomech_admin"
  instance = google_sql_database_instance.postgres.name
  password = var.db_password
}

# 6. CLOUD RUN: AI SERVICE (FastAPI)
resource "google_cloud_run_v2_service" "ai_service" {
  name     = "${var.app_name}-ai-service"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.ai_service.email

    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }

    containers {
      image = var.ai_service_image

      ports {
        container_port = 8000
      }

      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
      }

      env {
        name  = "DEFAULT_PROVIDER"
        value = var.gemini_api_key != "" ? "gemini" : "mock"
      }
      env {
        name = "GEMINI_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.app["gemini-api-key"].secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "SERVICE_AUTH_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.app["service-auth-secret"].secret_id
            version = "latest"
          }
        }
      }

      startup_probe {
        http_get {
          path = "/health"
        }
      }
    }
  }

  depends_on = [google_secret_manager_secret_iam_member.access, google_secret_manager_secret_version.app]
}

# The AI service is not public: only the backend identity may invoke it (ADR-019). The shared
# secret header is checked on top of that, as a second layer.
resource "google_cloud_run_v2_service_iam_member" "ai_invoker_backend" {
  location = google_cloud_run_v2_service.ai_service.location
  name     = google_cloud_run_v2_service.ai_service.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.backend.email}"
}

# 7. CLOUD RUN: FRONTEND (React SPA served by nginx)
# VITE_API_URL is baked into the bundle at build time (docker build --build-arg VITE_API_URL=...),
# so the container needs no runtime configuration.
resource "google_cloud_run_v2_service" "frontend" {
  name     = "${var.app_name}-frontend"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    scaling {
      min_instance_count = 1
      max_instance_count = 10
    }

    containers {
      image = var.frontend_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1000m"
          memory = "256Mi"
        }
      }
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_cloud_run_v2_service_iam_member" "frontend_public" {
  location = google_cloud_run_v2_service.frontend.location
  name     = google_cloud_run_v2_service.frontend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# 8. CLOUD RUN: BACKEND (Spring Boot 3)
resource "google_cloud_run_v2_service" "backend" {
  name     = "${var.app_name}-backend"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.backend.email

    scaling {
      # One warm instance avoids JVM cold starts on the first request.
      min_instance_count = 1
      max_instance_count = 20
    }

    containers {
      image = var.backend_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "2000m"
          memory = "2048Mi"
        }
      }

      env {
        name  = "SPRING_PROFILES_ACTIVE"
        value = local.spring_profile
      }

      # Database: consumed by application-prod.yml through standard JDBC over SSL.
      env {
        name  = "DB_HOST"
        value = google_sql_database_instance.postgres.public_ip_address
      }
      env {
        name  = "DB_NAME"
        value = google_sql_database.database.name
      }
      env {
        name  = "DB_USER"
        value = google_sql_user.db_user.name
      }
      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.app["db-password"].secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "JWT_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.app["jwt-secret"].secret_id
            version = "latest"
          }
        }
      }

      # Google OAuth 2.0 / OIDC (ADR-016)
      env {
        name  = "GOOGLE_CLIENT_ID"
        value = var.google_client_id
      }
      env {
        name = "GOOGLE_CLIENT_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.app["google-client-secret"].secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "GOOGLE_REDIRECT_URI"
        value = "${google_cloud_run_v2_service.frontend.uri}/auth/callback/google"
      }

      # AI Gateway -> AI service (ADR-018)
      env {
        name  = "GOMECH_AI_BASE_URL"
        value = google_cloud_run_v2_service.ai_service.uri
      }
      env {
        name = "GOMECH_AI_SERVICE_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.app["service-auth-secret"].secret_id
            version = "latest"
          }
        }
      }

      startup_probe {
        http_get {
          path = "/actuator/health"
        }
        initial_delay_seconds = 10
        period_seconds        = 10
        failure_threshold     = 18
      }

      liveness_probe {
        http_get {
          path = "/actuator/health"
        }
      }
    }
  }

  depends_on = [google_secret_manager_secret_iam_member.access, google_secret_manager_secret_version.app]
}

resource "google_cloud_run_v2_service_iam_member" "backend_public" {
  location = google_cloud_run_v2_service.backend.location
  name     = google_cloud_run_v2_service.backend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
