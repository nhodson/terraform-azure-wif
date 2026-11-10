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

locals {
  vertex_ai_service_url = (
    var.gcp_region == "global" ? "https://aiplatform.googleapis.com" :
    contains(["us", "eu"], var.gcp_region) ? "https://aiplatform.${var.gcp_region}.rep.googleapis.com" :
    "https://${var.gcp_region}-aiplatform.googleapis.com"
  )

  model_inference_policy_xml = <<XML
<policies>
  <inbound>
    <base />
    <rewrite-uri template="/v1beta1/projects/${module.gemini_project.project_id}/locations/${var.gcp_region}/publishers/google/models/{model}:{action}" />
    <set-header name="X-Model-Id" exists-action="override">
      <value>{model}</value>
    </set-header>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
XML
}

# Create a resource group for the API Management service
resource "azurerm_resource_group" "api_management" {
  count    = var.deploy_api_management ? 1 : 0
  name     = "${var.project_prefix}-api-management-rg"
  location = var.location
}

# Create an API Management service
resource "azurerm_api_management" "api_management" {
  count               = var.deploy_api_management ? 1 : 0
  name                = "${var.project_prefix}-apim"
  location            = azurerm_resource_group.api_management[0].location
  resource_group_name = azurerm_resource_group.api_management[0].name
  publisher_name      = "Your Name"
  publisher_email     = "your-email@example.com"
  sku_name            = "Developer_1" # Cache not available on Consumption SKU, must be Developer_1 or higher

  identity {
    type = "SystemAssigned"
  }
}

# Import the Vertex AI API
resource "azurerm_api_management_api" "vertex_ai" {
  count               = var.deploy_api_management ? 1 : 0
  name                = "vertex-ai"
  resource_group_name = azurerm_resource_group.api_management[0].name
  api_management_name = azurerm_api_management.api_management[0].name
  revision            = "1"
  display_name        = "Vertex AI"
  path                = "vertex-ai"
  protocols           = ["https"]
  service_url         = local.vertex_ai_service_url
}

# Create a subscription for the Vertex AI API (strip ';rev=...' suffix so APIM scope matches the API)
resource "azurerm_api_management_subscription" "vertex_ai" {
  count               = var.deploy_api_management ? 1 : 0
  api_management_name = azurerm_api_management.api_management[0].name
  resource_group_name = azurerm_resource_group.api_management[0].name
  api_id              = replace(azurerm_api_management_api.vertex_ai[0].id, ";rev=${azurerm_api_management_api.vertex_ai[0].revision}", "")
  display_name        = "Vertex AI API Subscription"
  state               = "active"
  allow_tracing       = false
}

# Add a policy to handle the request to the Vertex AI API
resource "azurerm_api_management_api_policy" "vertex_ai_policy" {
  count               = var.deploy_api_management ? 1 : 0
  api_name            = azurerm_api_management_api.vertex_ai[0].name
  api_management_name = azurerm_api_management.api_management[0].name
  resource_group_name = azurerm_resource_group.api_management[0].name

  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <!-- Optional: Enforce allowed models if var.allowed_models is configured -->
    <set-variable name="isModelBlocked" value="@{
        string[] allowedModels = new string[] { ${join(", ", formatlist("\"%s\"", var.allowed_models))} };
        if (allowedModels.Length > 0) {
            string requestedModel = null;
            if (context.Request.MatchedParameters.ContainsKey("model")) {
                requestedModel = context.Request.MatchedParameters["model"];
            } else if (context.Operation.Id == "create-interaction" && context.Request.Body != null) {
                var body = context.Request.Body.As<JObject>(preserveContent: true);
                requestedModel = body?["model"]?.ToString();
            }
            if (!string.IsNullOrEmpty(requestedModel)) {
                return Array.IndexOf(allowedModels, requestedModel) == -1;
            }
        }
        return false;
    }" />
    <choose>
      <when condition="@((bool)context.Variables["isModelBlocked"])">
        <return-response>
          <set-status code="403" reason="Forbidden" />
          <set-header name="Content-Type" exists-action="override">
            <value>application/json</value>
          </set-header>
          <set-body>@{
            return new JObject(
              new JProperty("error", new JObject(
                new JProperty("code", 403),
                new JProperty("message", "Requested model is not in the allowed_models list for this gateway."),
                new JProperty("status", "PERMISSION_DENIED")
              ))
            ).ToString();
          }</set-body>
        </return-response>
      </when>
    </choose>

    <!-- Try to get the token from cache -->
    <cache-lookup-value key="stsToken-${module.gemini_project.project_id}-${var.gcp_region}" variable-name="stsToken" />

    <!-- If token is not in cache, then obtain it -->
    <choose>
      <when condition="@(!context.Variables.ContainsKey("stsToken"))">
        <!-- Get Azure AD token for the managed identity -->
        <authentication-managed-identity resource="${azuread_application.gcp_wif.client_id}" output-token-variable-name="azureToken" />

        <!-- Exchange Azure AD token for a Google STS token -->
        <send-request mode="new" response-variable-name="stsResponse" timeout="10" ignore-error="false">
          <set-url>https://sts.googleapis.com/v1/token</set-url>
          <set-method>POST</set-method>
          <set-header name="Content-Type" exists-action="override">
            <value>application/json</value>
          </set-header>
          <set-body>@{
            return new JObject(
              new JProperty("grant_type", "urn:ietf:params:oauth:grant-type:token-exchange"),
              new JProperty("subject_token_type", "urn:ietf:params:oauth:token-type:jwt"),
              new JProperty("requested_token_type", "urn:ietf:params:oauth:token-type:access_token"),
              new JProperty("subject_token", (string)context.Variables["azureToken"]),
              new JProperty("audience", "//iam.googleapis.com/${google_iam_workload_identity_pool_provider.azure.name}"),
              new JProperty("scope", "https://www.googleapis.com/auth/cloud-platform")
            ).ToString();
          }</set-body>
        </send-request>

        <!-- Extract STS token from response -->
        <set-variable name="stsResponseObject" value="@{
            var response = context.Variables.GetValueOrDefault<IResponse>("stsResponse");
            if (response != null && response.Body != null && response.StatusCode == 200) {
                return response.Body.As<JObject>();
            }
            return null;
        }" />

        <set-variable name="stsToken" value="@{
            var stsResponse = (JObject)context.Variables["stsResponseObject"];
            if (stsResponse != null) {
                return stsResponse["access_token"].ToString();
            }
            return "sts-token-not-found";
        }" />

        <!-- Store the STS token in the cache for future requests -->
        <cache-store-value key="stsToken-${module.gemini_project.project_id}-${var.gcp_region}" value="@((string)context.Variables["stsToken"])" duration="@{
            var stsResponse = (JObject)context.Variables["stsResponseObject"];
            if (stsResponse != null) {
                return (int)stsResponse["expires_in"] - 60;
            }
            return 0;
        }" />
      </when>
    </choose>

    <!-- Strip APIM subscription key and client API key headers so they are not forwarded upstream -->
    <set-header name="Ocp-Apim-Subscription-Key" exists-action="delete" />
    <set-header name="x-goog-api-key" exists-action="delete" />

    <!-- Set Authorization header for the backend request (User-Agent, X-Goog-Api-Client, and custom X-* attribution headers are preserved) -->
    <set-header name="Authorization" exists-action="override">
      <value>@("Bearer " + (string)context.Variables["stsToken"])</value>
    </set-header>
  </inbound>
  <backend>
    <!-- Disable response buffering so Server-Sent Events (SSE) flush immediately for Antigravity and SDK streaming -->
    <forward-request timeout="240" buffer-response="false" />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
XML
}

# Operation for SDK collection-scoped model inference (POST /publishers/google/models/{model}:{action})
resource "azurerm_api_management_api_operation" "sdk_model_inference" {
  count               = var.deploy_api_management ? 1 : 0
  api_name            = azurerm_api_management_api.vertex_ai[0].name
  api_management_name = azurerm_api_management.api_management[0].name
  resource_group_name = azurerm_resource_group.api_management[0].name
  operation_id        = "sdk-model-inference"
  display_name        = "Model Inference (SDK Collection Scope)"
  method              = "POST"
  url_template        = "/publishers/google/models/{model}:{action}"
  description         = "Unary and streaming inference (:generateContent, :streamGenerateContent, :countTokens) for SDK collection scope"

  template_parameter {
    name     = "model"
    type     = "string"
    required = true
  }

  template_parameter {
    name     = "action"
    type     = "string"
    required = true
  }
}

resource "azurerm_api_management_api_operation_policy" "sdk_model_inference_policy" {
  count               = var.deploy_api_management ? 1 : 0
  api_name            = azurerm_api_management_api_operation.sdk_model_inference[0].api_name
  api_management_name = azurerm_api_management_api_operation.sdk_model_inference[0].api_management_name
  resource_group_name = azurerm_api_management_api_operation.sdk_model_inference[0].resource_group_name
  operation_id        = azurerm_api_management_api_operation.sdk_model_inference[0].operation_id
  xml_content         = local.model_inference_policy_xml
}

# ==============================================================================
# Versioned & Antigravity Enterprise Gateway Operations (v1, v1beta, v1beta1)
# https://docs.cloud.google.com/gemini/enterprise/docs/ai-developer-tools/deploy-enterprise-gateway
# ==============================================================================

# Operation for versioned & Antigravity model inference (POST /{version}/models/{model}:{action})
resource "azurerm_api_management_api_operation" "versioned_model_inference" {
  count               = var.deploy_api_management ? 1 : 0
  api_name            = azurerm_api_management_api.vertex_ai[0].name
  api_management_name = azurerm_api_management.api_management[0].name
  resource_group_name = azurerm_resource_group.api_management[0].name
  operation_id        = "versioned-model-inference"
  display_name        = "Model Inference (Versioned / Antigravity)"
  method              = "POST"
  url_template        = "/{version}/models/{model}:{action}"
  description         = "Unary and streaming inference (:generateContent, :streamGenerateContent, :countTokens) for Antigravity (/v1beta) and versioned callers (v1, v1beta1)"

  template_parameter {
    name     = "version"
    type     = "string"
    required = true
  }

  template_parameter {
    name     = "model"
    type     = "string"
    required = true
  }

  template_parameter {
    name     = "action"
    type     = "string"
    required = true
  }
}

resource "azurerm_api_management_api_operation_policy" "versioned_model_inference_policy" {
  count               = var.deploy_api_management ? 1 : 0
  api_name            = azurerm_api_management_api_operation.versioned_model_inference[0].api_name
  api_management_name = azurerm_api_management_api_operation.versioned_model_inference[0].api_management_name
  resource_group_name = azurerm_api_management_api_operation.versioned_model_inference[0].resource_group_name
  operation_id        = azurerm_api_management_api_operation.versioned_model_inference[0].operation_id
  xml_content         = local.model_inference_policy_xml
}

# Operation for Interactions API (POST /{version}/interactions, e.g. gemini-omni-1.2-flash video generation)
resource "azurerm_api_management_api_operation" "create_interaction" {
  count               = var.deploy_api_management ? 1 : 0
  api_name            = azurerm_api_management_api.vertex_ai[0].name
  api_management_name = azurerm_api_management.api_management[0].name
  resource_group_name = azurerm_resource_group.api_management[0].name
  operation_id        = "create-interaction"
  display_name        = "Create Interaction (Gemini Omni / Interactions API)"
  method              = "POST"
  url_template        = "/{version}/interactions"
  description         = "Create an interaction using the Interactions API (e.g., gemini-omni-1.2-flash video generation)"

  template_parameter {
    name     = "version"
    type     = "string"
    required = true
  }
}

resource "azurerm_api_management_api_operation_policy" "create_interaction_policy" {
  count               = var.deploy_api_management ? 1 : 0
  api_name            = azurerm_api_management_api_operation.create_interaction[0].api_name
  api_management_name = azurerm_api_management_api_operation.create_interaction[0].api_management_name
  resource_group_name = azurerm_api_management_api_operation.create_interaction[0].resource_group_name
  operation_id        = azurerm_api_management_api_operation.create_interaction[0].operation_id

  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <rewrite-uri template="/v1beta1/projects/${module.gemini_project.project_id}/locations/${var.gcp_region}/interactions" />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
XML
}

# Operation to acknowledge Antigravity background telemetry calls (POST /{version}:{action})
resource "azurerm_api_management_api_operation" "agy_telemetry" {
  count               = var.deploy_api_management ? 1 : 0
  api_name            = azurerm_api_management_api.vertex_ai[0].name
  api_management_name = azurerm_api_management.api_management[0].name
  resource_group_name = azurerm_resource_group.api_management[0].name
  operation_id        = "agy-telemetry"
  display_name        = "Antigravity Telemetry Acknowledgment"
  method              = "POST"
  url_template        = "/{version}:{action}"
  description         = "Acknowledge Antigravity background metric calls (e.g. POST /v1beta:*)"

  template_parameter {
    name     = "version"
    type     = "string"
    required = true
  }

  template_parameter {
    name     = "action"
    type     = "string"
    required = true
  }
}

resource "azurerm_api_management_api_operation_policy" "agy_telemetry_policy" {
  count               = var.deploy_api_management ? 1 : 0
  api_name            = azurerm_api_management_api_operation.agy_telemetry[0].api_name
  api_management_name = azurerm_api_management_api_operation.agy_telemetry[0].api_management_name
  resource_group_name = azurerm_api_management_api_operation.agy_telemetry[0].resource_group_name
  operation_id        = azurerm_api_management_api_operation.agy_telemetry[0].operation_id

  xml_content = <<XML
<policies>
  <inbound>
    <return-response>
      <set-status code="200" reason="OK" />
      <set-header name="Content-Type" exists-action="override">
        <value>application/json</value>
      </set-header>
      <set-body>{}</set-body>
    </return-response>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
XML
}

# Google Cloud IAM permission for managed identity of API Management to call Gemini via Vertex AI
resource "google_project_iam_member" "api_management_principal" {
  for_each = toset(var.deploy_api_management ? [
    "roles/aiplatform.user"
  ] : [])
  project = module.gemini_project.project_id
  role    = each.key
  member  = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.azure.name}/subject/${azurerm_api_management.api_management[0].identity[0].principal_id}"
}
