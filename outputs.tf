output "gemini_project_id" {
  description = "The ID of the Gemini project"
  value       = module.gemini_project.project_id
}

output "wip_project_number" {
  description = "The number of the Workload Identity Pool project"
  value       = module.wip_project.project_number
}

output "pool_id" {
  description = "The ID of the Workload Identity Pool"
  value       = google_iam_workload_identity_pool.azure.workload_identity_pool_id
}

output "provider_id" {
  description = "The ID of the Workload Identity Pool Provider"
  value       = google_iam_workload_identity_pool_provider.azure.workload_identity_pool_provider_id
}

output "application_id_uri" {
  description = "The Application ID URI of the Azure AD Application"
  value       = azuread_application.gcp_wif.client_id
}

output "service_app_url" {
  description = "The URL of the Streamlit Gemini Service App"
  value       = "https://${azurerm_linux_web_app.app_service.name}.azurewebsites.net"
}