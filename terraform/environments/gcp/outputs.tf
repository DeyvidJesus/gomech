output "backend_url" {
  value = module.gcp_infrastructure.backend_url
}

output "ai_service_url" {
  value = module.gcp_infrastructure.ai_service_url
}

output "frontend_url" {
  value = module.gcp_infrastructure.frontend_url
}

output "artifact_registry_repository" {
  value = module.gcp_infrastructure.artifact_registry_repository
}

output "db_connection_name" {
  value = module.gcp_infrastructure.db_connection_name
}

output "db_public_ip" {
  value = module.gcp_infrastructure.db_public_ip
}
