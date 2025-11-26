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
  service_url         = "https://aiplatform.googleapis.com"
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
    <!-- Try to get the token from cache -->
    <cache-lookup-value key="stsToken" variable-name="stsToken" />

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
        <cache-store-value key="stsToken" value="@((string)context.Variables["stsToken"])" duration="@{
            var stsResponse = (JObject)context.Variables["stsResponseObject"];
            if (stsResponse != null) {
                return (int)stsResponse["expires_in"] - 60;
            }
            return 0;
        }" />
      </when>
    </choose>

    <!-- Set Authorization header for the backend request -->
    <set-header name="Authorization" exists-action="override">
      <value>@("Bearer " + (string)context.Variables["stsToken"])</value>
    </set-header>
  </inbound>
  <backend>
    <forward-request timeout="60" />
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


# Operation for generateContent
resource "azurerm_api_management_api_operation" "generate_content" {
  count               = var.deploy_api_management ? 1 : 0
  api_name            = azurerm_api_management_api.vertex_ai[0].name
  api_management_name = azurerm_api_management.api_management[0].name
  resource_group_name = azurerm_resource_group.api_management[0].name
  operation_id        = "generate-content"
  display_name        = "Generate Content"
  method              = "POST"
  url_template        = "/publishers/google/models/{model}:generateContent"
  description         = "Generate content using Gemini models"

  template_parameter {
    name     = "model"
    type     = "string"
    required = true
  }
}

resource "azurerm_api_management_api_operation_policy" "generate_content_policy" {
  count               = var.deploy_api_management ? 1 : 0
  api_name            = azurerm_api_management_api_operation.generate_content[0].api_name
  api_management_name = azurerm_api_management_api_operation.generate_content[0].api_management_name
  resource_group_name = azurerm_api_management_api_operation.generate_content[0].resource_group_name
  operation_id        = azurerm_api_management_api_operation.generate_content[0].operation_id

  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <rewrite-uri template="/v1/projects/${module.gemini_project.project_id}/locations/${var.gcp_region}/publishers/google/models/{model}:generateContent" />
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

# Operation for streamGenerateContent
resource "azurerm_api_management_api_operation" "stream_generate_content" {
  count               = var.deploy_api_management ? 1 : 0
  api_name            = azurerm_api_management_api.vertex_ai[0].name
  api_management_name = azurerm_api_management.api_management[0].name
  resource_group_name = azurerm_resource_group.api_management[0].name
  operation_id        = "stream-generate-content"
  display_name        = "Stream Generate Content"
  method              = "POST"
  url_template        = "/publishers/google/models/{model}:streamGenerateContent"
  description         = "Stream generate content using Gemini models"

  template_parameter {
    name     = "model"
    type     = "string"
    required = true
  }
}

resource "azurerm_api_management_api_operation_policy" "stream_generate_content_policy" {
  count               = var.deploy_api_management ? 1 : 0
  api_name            = azurerm_api_management_api_operation.stream_generate_content[0].api_name
  api_management_name = azurerm_api_management_api_operation.stream_generate_content[0].api_management_name
  resource_group_name = azurerm_api_management_api_operation.stream_generate_content[0].resource_group_name
  operation_id        = azurerm_api_management_api_operation.stream_generate_content[0].operation_id

  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <rewrite-uri template="/v1/projects/${module.gemini_project.project_id}/locations/${var.gcp_region}/publishers/google/models/{model}:streamGenerateContent" />
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

# Operation for predict (Imagen)
resource "azurerm_api_management_api_operation" "predict" {
  count               = var.deploy_api_management ? 1 : 0
  api_name            = azurerm_api_management_api.vertex_ai[0].name
  api_management_name = azurerm_api_management.api_management[0].name
  resource_group_name = azurerm_resource_group.api_management[0].name
  operation_id        = "predict"
  display_name        = "Predict"
  method              = "POST"
  url_template        = "/publishers/google/models/{model}:predict"
  description         = "Predict using Vertex AI models (e.g., Imagen)"

  template_parameter {
    name     = "model"
    type     = "string"
    required = true
  }
}

resource "azurerm_api_management_api_operation_policy" "predict_policy" {
  count               = var.deploy_api_management ? 1 : 0
  api_name            = azurerm_api_management_api_operation.predict[0].api_name
  api_management_name = azurerm_api_management_api_operation.predict[0].api_management_name
  resource_group_name = azurerm_api_management_api_operation.predict[0].resource_group_name
  operation_id        = azurerm_api_management_api_operation.predict[0].operation_id

  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <rewrite-uri template="/v1/projects/${module.gemini_project.project_id}/locations/${var.gcp_region}/publishers/google/models/{model}:predict" />
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

# Operation for predictLongRunning (Veo)
resource "azurerm_api_management_api_operation" "predict_long_running" {
  count               = var.deploy_api_management ? 1 : 0
  api_name            = azurerm_api_management_api.vertex_ai[0].name
  api_management_name = azurerm_api_management.api_management[0].name
  resource_group_name = azurerm_resource_group.api_management[0].name
  operation_id        = "predict-long-running"
  display_name        = "Predict Long Running"
  method              = "POST"
  url_template        = "/publishers/google/models/{model}:predictLongRunning"
  description         = "Predict Long Running using Vertex AI models (e.g., Veo)"

  template_parameter {
    name     = "model"
    type     = "string"
    required = true
  }
}

resource "azurerm_api_management_api_operation_policy" "predict_long_running_policy" {
  count               = var.deploy_api_management ? 1 : 0
  api_name            = azurerm_api_management_api_operation.predict_long_running[0].api_name
  api_management_name = azurerm_api_management_api_operation.predict_long_running[0].api_management_name
  resource_group_name = azurerm_api_management_api_operation.predict_long_running[0].resource_group_name
  operation_id        = azurerm_api_management_api_operation.predict_long_running[0].operation_id

  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <rewrite-uri template="/v1/projects/${module.gemini_project.project_id}/locations/${var.gcp_region}/publishers/google/models/{model}:predictLongRunning" />
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

# Operation for fetchPredictOperation (LRO status)
resource "azurerm_api_management_api_operation" "fetch_predict_operation" {
  count               = var.deploy_api_management ? 1 : 0
  api_name            = azurerm_api_management_api.vertex_ai[0].name
  api_management_name = azurerm_api_management.api_management[0].name
  resource_group_name = azurerm_resource_group.api_management[0].name
  operation_id        = "fetch-predict-operation"
  display_name        = "Fetch Predict Operation"
  method              = "POST"
  url_template        = "/projects/{project_id}/locations/{location}/publishers/google/models/{model}:fetchPredictOperation"
  description         = "Get status of long-running predict operations"

  template_parameter {
    name     = "project_id"
    type     = "string"
    required = true
  }

  template_parameter {
    name     = "location"
    type     = "string"
    required = true
  }

  template_parameter {
    name     = "model"
    type     = "string"
    required = true
  }
}

resource "azurerm_api_management_api_operation_policy" "fetch_predict_operation_policy" {
  count               = var.deploy_api_management ? 1 : 0
  api_name            = azurerm_api_management_api_operation.fetch_predict_operation[0].api_name
  api_management_name = azurerm_api_management_api_operation.fetch_predict_operation[0].api_management_name
  resource_group_name = azurerm_api_management_api_operation.fetch_predict_operation[0].resource_group_name
  operation_id        = azurerm_api_management_api_operation.fetch_predict_operation[0].operation_id

  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <rewrite-uri template="/v1/projects/{project_id}/locations/{location}/publishers/google/models/{model}:fetchPredictOperation" />
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

# Google Cloud IAM permission for managed identity of API Management to call Gemini via Vertex AI
resource "google_project_iam_member" "api_management_principal" {
  for_each = toset(var.deploy_api_management ? [
    "roles/aiplatform.user"
  ] : [])
  project = module.gemini_project.project_id
  role    = each.key
  member  = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.azure.name}/subject/${azurerm_api_management.api_management[0].identity[0].principal_id}"
}