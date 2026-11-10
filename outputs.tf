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
  value       = length(azurerm_linux_web_app.app_service) > 0 ? "https://${azurerm_linux_web_app.app_service[0].name}.azurewebsites.net" : null
}

output "api_management_gateway_url" {
  description = "The URL of the API Management gateway"
  value       = var.deploy_api_management ? azurerm_api_management.api_management[0].gateway_url : null
}

output "api_management_subscription_key" {
  description = "The primary subscription key for the Vertex AI API in Azure API Management"
  sensitive   = true
  value       = var.deploy_api_management ? azurerm_api_management_subscription.vertex_ai[0].primary_key : null
}

output "antigravity_admin_settings_json" {
  description = "Rendered Antigravity admin_settings.json configured from Terraform variables and deployed Azure API Management resources"
  sensitive   = true
  value = jsonencode({
    gateway = {
      enabled      = true
      url          = var.deploy_api_management ? "${azurerm_api_management.api_management[0].gateway_url}/vertex-ai" : "https://${var.project_prefix}-apim.azure-api.net/vertex-ai"
      apiKey       = var.deploy_api_management ? azurerm_api_management_subscription.vertex_ai[0].primary_key : "<YOUR_APIM_SUBSCRIPTION_KEY>"
      wireProtocol = "genai"
      customHeaders = {
        "Ocp-Apim-Subscription-Key" = var.deploy_api_management ? azurerm_api_management_subscription.vertex_ai[0].primary_key : "<YOUR_APIM_SUBSCRIPTION_KEY>"
        "X-Cost-Center"             = "Platform-Engineering"
      }
    }
    models = {
      defaultModelId = length(var.allowed_models) > 0 ? var.allowed_models[0] : "gemini-3.8-flash"
      list = [
        for model_id in(length(var.allowed_models) > 0 ? var.allowed_models : ["gemini-4-argon", "gemini-3.8-flash", "gemini-3.5-flash-lite"]) : {
          modelId = model_id
        }
      ]
    }
  })
}