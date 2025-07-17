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

# https://cloud.google.com/iam/docs/workload-identity-federation-with-other-clouds#azure
# Create an application in Azure tenant
data "azuread_client_config" "current" {}

resource "azuread_application" "gcp_wif" {
  display_name = "gcp-wif"
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "gcp_wif" {
  client_id                    = azuread_application.gcp_wif.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
}


# Create a dedicated project to manage workload identity pools and providers
# https://cloud.google.com/iam/docs/best-practices-for-using-workload-identity-federation#dedicated-project
module "wip_project" {
  source  = "terraform-google-modules/project-factory/google"
  version = "~> 18.0"

  name              = "${var.project_prefix}-wip"
  random_project_id = true
  org_id            = var.org_id
  billing_account   = var.billing_account_id

  activate_apis = [
    "aiplatform.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "serviceusage.googleapis.com",
    "sts.googleapis.com",
  ]
}

# Workload Identity Pool for Azure integration
resource "google_iam_workload_identity_pool" "azure" {
  project                   = module.wip_project.project_id
  workload_identity_pool_id = "azure"
  display_name              = "Azure"
}

resource "google_iam_workload_identity_pool_provider" "azure" {
  project                            = module.wip_project.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.azure.workload_identity_pool_id
  workload_identity_pool_provider_id = "azure-oidc"
  description                        = null
  disabled                           = false
  display_name                       = "Azure OIDC"

  attribute_condition = null
  attribute_mapping = {
    "google.subject" = "assertion.sub"
  }

  oidc {
    allowed_audiences = [azuread_application.gcp_wif.client_id]
    issuer_uri        = "https://sts.windows.net/${var.tenant_id}"
    jwks_json         = null
  }
}

# Create a project for Gemini usage
module "gemini_project" {
  source  = "terraform-google-modules/project-factory/google"
  version = "~> 18.0"

  name              = "${var.project_prefix}-gemini"
  random_project_id = true
  org_id            = var.org_id
  billing_account   = var.billing_account_id

  activate_apis = [
    "aiplatform.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "serviceusage.googleapis.com",
  ]
}
