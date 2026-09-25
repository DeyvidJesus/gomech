output "backend_url" {
  description = "Public URL of the GoMech Backend App Runner service"
  value       = "https://${aws_apprunner_service.backend.service_url}"
}

output "ai_service_url" {
  description = "Public URL of the GoMech AI Service App Runner service"
  value       = "https://${aws_apprunner_service.ai_service.service_url}"
}

output "frontend_url" {
  description = "CloudFront distribution domain name for Frontend SPA"
  value       = "https://${aws_cloudfront_distribution.frontend_cdn.domain_name}"
}

output "db_endpoint" {
  description = "Amazon RDS PostgreSQL endpoint"
  value       = aws_db_instance.postgres.endpoint
}
