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


# Create a random string for unique naming
resource "random_string" "app_name_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Create a resource group for the App Service
resource "azurerm_resource_group" "app_service" {
  name     = "${var.project_prefix}-app-service-rg"
  location = var.location
}

# Create an App Service Plan
resource "azurerm_service_plan" "app_service" {
  name                = "${var.project_prefix}-asp"
  location            = azurerm_resource_group.app_service.location
  resource_group_name = azurerm_resource_group.app_service.name
  os_type             = "Linux"
  sku_name            = "F1"
}

# Create the run.sh file from the template
# This allows us to interpolate the IDENTITY_ENDPOINT and IDENTITY_HEADER environment variables on startup
resource "local_file" "run_sh" {
  content = templatefile("${path.module}/templates/run.sh.tftpl", {
    pool_name      = google_iam_workload_identity_pool.azure.name
    provider_id    = google_iam_workload_identity_pool_provider.azure.workload_identity_pool_provider_id
    application_id = azuread_application.gcp_wif.client_id
  })
  filename        = "${path.module}/gemini-streamlit-app/run.sh"
  file_permission = "0755"
}

# Package the app directory
data "archive_file" "app" {
  type        = "zip"
  source_dir  = "${path.module}/gemini-streamlit-app"
  output_path = "${path.module}/gemini-streamlit-app.zip"
  excludes = [
    ".venv/**",
    "**/.git/**",
    "**/__pycache__/**",
    "**/.DS_Store",
  ]
  depends_on = [local_file.run_sh]
}

# Create a Linux Web App
resource "azurerm_linux_web_app" "app_service" {
  name                = "${var.app_name}-${random_string.app_name_suffix.result}"
  location            = azurerm_resource_group.app_service.location
  resource_group_name = azurerm_resource_group.app_service.name
  service_plan_id     = azurerm_service_plan.app_service.id
  https_only          = true

  site_config {
    always_on = false
    application_stack {
      python_version = "3.11"
    }
    app_command_line = "run.sh"
  }

  app_settings = {
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
    "GOOGLE_APPLICATION_CREDENTIALS"      = "./gcp-cred-config.json"
    "GOOGLE_GENAI_USE_VERTEXAI"           = "true"
    "GOOGLE_CLOUD_PROJECT"                = module.gemini_project.project_id
    "GOOGLE_CLOUD_LOCATION"               = "global"
  }

  zip_deploy_file = data.archive_file.app.output_path

  identity {
    type = "SystemAssigned"
  }

  auth_settings_v2 {
    active_directory_v2 {
      client_id            = azuread_application.gcp_wif.client_id
      tenant_auth_endpoint = "https://login.microsoftonline.com/${var.tenant_id}"
    }
    default_provider = "AzureActiveDirectory"
    login {
      token_store_enabled = true
    }
  }

  depends_on = [
    data.archive_file.app,
    azurerm_service_plan.app_service
  ]
}

# Google Cloud IAM permission for managed identity of the App Service to call Gemini via Vertex AI
resource "google_project_iam_member" "app_service_principal" {
  for_each = toset([
    "roles/aiplatform.user"
  ])
  project = module.gemini_project.project_id
  role    = each.key
  member  = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.azure.name}/subject/${azurerm_linux_web_app.app_service.identity[0].principal_id}"
}
