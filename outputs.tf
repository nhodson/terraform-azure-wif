# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

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