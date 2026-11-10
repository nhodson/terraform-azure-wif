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

variable "billing_account_id" {
  description = "The ID of the GCP billing account to associate this project with."
  type        = string
}

variable "org_id" {
  description = "The GCP organization ID."
  type        = string
}

variable "project_prefix" {
  description = "Prefix to assign to project ID. Project will be {project_prefix}-wip-{random_string}"
  type        = string
}

variable "subscription_id" {
  description = "Azure Subscription ID to use."
  type        = string
}

variable "tenant_id" {
  description = "Azure Tenant ID to use."
  type        = string
}

variable "terraform_service_account" {
  description = "Service account for Terraform to impersonate for authentication."
  type        = string
}

variable "app_name" {
  description = "The name of the App Service application."
  type        = string
  default     = "gemini-chat-app"
}

variable "gcp_region" {
  description = "The GCP location for Vertex AI / Gemini Enterprise Agent Platform endpoints. Supports 'global' (default), multi-regions ('us', 'eu'), or regional endpoints (e.g., 'us-central1')."
  type        = string
  default     = "global"
}

variable "allowed_models" {
  description = "Optional list of allowed model IDs to enforce in the APIM gateway policy (e.g., [\"gemini-4-argon\", \"gemini-3.8-flash\", \"gemini-3.5-flash-lite\"]). When empty, all models are allowed."
  type        = list(string)
  default     = []
}

variable "location" {
  description = "The Azure region to deploy the resources in."
  type        = string
  default     = "East US 2"
}

variable "deploy_api_management" {
  description = "Whether to deploy the API Management service and related components."
  type        = bool
  default     = false
}

variable "deploy_app_service" {
  description = "Whether to deploy the App Service and related components."
  type        = bool
  default     = false
}