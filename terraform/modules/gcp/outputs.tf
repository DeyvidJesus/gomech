output "backend_url" {
  description = "Public URL of the backend Cloud Run service"
  value       = google_cloud_run_v2_service.backend.uri
}

output "ai_service_url" {
  description = "URL of the AI service (invokable only by the backend service account)"
  value       = google_cloud_run_v2_service.ai_service.uri
}

output "frontend_url" {
  description = "Public URL of the frontend Cloud Run service"
  value       = google_cloud_run_v2_service.frontend.uri
}

output "artifact_registry_repository" {
  description = "Docker repository path to push images to"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker_repo.repository_id}"
}

output "db_connection_name" {
  description = "Cloud SQL instance connection name"
  value       = google_sql_database_instance.postgres.connection_name
}

output "db_public_ip" {
  description = "Public IP of the Cloud SQL instance"
  value       = google_sql_database_instance.postgres.public_ip_address
}
