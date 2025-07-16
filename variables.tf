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

variable "location" {
  description = "The Azure region to deploy the resources in."
  type        = string
  default     = "East US 2"
}