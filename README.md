# Terraform Azure Workload Identity Federation
Implementation of [Workload Identity Federation with Azure](https://cloud.google.com/iam/docs/workload-identity-federation-with-other-clouds#azure)

## Architecture
![Architecture diagram](./docs/architecture.png)
**Note:** The architecture diagram shows all possible components. The deployment of the API Management service and the App Service is optional and can be enabled or disabled using variables in your configuration.

## Configuration

Before running `terraform apply`, you need to set some required variables. The recommended approach is to create a `terraform.tfvars` file in the root of this project.

### Required Variables

*   `tenant_id`: The tenant ID for your Azure AD (Entra ID).
*   `subscription_id`: The subscription ID where Azure resources will be created.
*   `org_id`: The GCP Organization ID where projects will be created.
*   `billing_account_id`: The GCP Billing Account to attach to the projects.
*   `project_prefix`: Unique prefix to apply to created GCP projects
*   `terraform_service_account`: Terraform service account used for impersonation

### Optional Variables
*   `deploy_api_management`: (Default: `false`) Set to `true` to deploy the Azure API Management service.
*   `deploy_app_service`: (Default: `false`) Set to `true` to deploy the Azure App Service.
*   `gcp_region`: (Default: `global`) The GCP location for Vertex AI / Gemini Enterprise Agent Platform endpoints. Supports `global`, multi-regions (`us`, `eu`), or regional endpoints (e.g., `us-central1`).
*   `allowed_models`: (Default: `[]`) Optional list of allowed model IDs to enforce in the APIM gateway policy (e.g., `["gemini-4-argon", "gemini-3.8-flash", "gemini-3.5-flash-lite"]`). When empty, all models are allowed.
*   `location`: (Default: `East US 2`) The Azure region for resources.
*   `app_name`: (Default: `gemini-chat-app`) The name of the App Service application.


Create a `terraform.tfvars` file with the following content, replacing the placeholder values:

```hcl
tenant_id                 = "YOUR_AZURE_TENANT_ID"
subscription_id           = "YOUR_AZURE_SUBSCRIPTION_ID"
org_id                    = "YOUR_GCP_ORG_ID"
billing_account_id        = "YOUR_GCP_BILLING_ID"
project_prefix            = "YOUR_GCP_PROJECT_PREFIX"
terraform_service_account = "YOUR_TERRAFORM_SERVICE_ACCOUNT"

# Optional: Enable API Management and/or App Service
# deploy_api_management   = true
# deploy_app_service      = true
# gcp_region              = "global" # Or "us", "eu", "us-central1"
# allowed_models          = ["gemini-4-argon", "gemini-3.8-flash", "gemini-3.5-flash-lite"]
```

Alternatively, you can provide variables using environment variables prefixed with `TF_VAR_`. For example: `export TF_VAR_tenant_id="YOUR_AZURE_TENANT_ID"`.

## Apply Terraform
The Terraform configuration creates:
- Dedicated GCP project for the workload identity pool
- GCP project for accessing Gemini via Vertex AI
- Entra ID application and service principal
- Workload identity pool and provider
- **(Optional)** Azure API Management service to proxy requests to Vertex AI.
- **(Optional)** Azure App Service application to demonstrate calling Vertex AI.

1. Initialize Terraform:
    ```
    terraform init
    ```
    This command prepares your working directory for Terraform by downloading the necessary providers and modules.

2. Apply the Terraform configuration:
    ```
    terraform apply
    ```
    This command creates or updates resources according to your Terraform configuration. You will be prompted to confirm the actions before they are executed.

## Using with Azure API Management
If you have deployed the API Management service (`deploy_api_management = true`), you can use it to proxy requests to the Gemini Enterprise Agent Platform (Vertex AI) API. This provides a single unified endpoint for both the **Google Gen AI SDK** and **Google Antigravity (Enterprise Gateway)** while caching Workload Identity Federation authentication tokens.

The API Management endpoint is exposed at `https://<project_prefix>-apim.azure-api.net/vertex-ai`. To call the endpoint, you will need an APIM subscription key (`Ocp-Apim-Subscription-Key`). You can find the subscription key in the Azure portal under your API Management instance.

### Testing the API Proxy
Two examples are provided to demonstrate how to interact with the API Management gateway:

*   **`api-proxy-curl-usage.sh`**: A shell script demonstrating `curl` requests to the API proxy (including standard SDK unary requests, Antigravity streaming SSE requests, and Antigravity telemetry acknowledgment checks).
*   **`api-proxy-client-usage.ipynb`**: A Jupyter Notebook demonstrating how to interact with the API Management gateway using the `google-genai` client library.

### Connecting Google Antigravity (Enterprise Gateway)
The Azure API Management configuration in `api_management.tf` satisfies all [Antigravity Enterprise Gateway](https://docs.cloud.google.com/gemini/enterprise/docs/ai-developer-tools/deploy-enterprise-gateway) requirements:
*   **Header Preservation & Billing Attribution**: Forwards `User-Agent` (`antigravity/VERSION (aidev_client; auth_method=gateway)`), `X-Goog-Api-Client`, and custom `X-*` headers unchanged to Google Cloud while stripping `Ocp-Apim-Subscription-Key` before forwarding upstream.
*   **Unbuffered SSE Streaming**: Disables response buffering (`buffer-response="false"`) and extends request timeouts (`timeout="240"`) so `:streamGenerateContent?alt=sse` flushes chunks immediately.
*   **Antigravity Inference & Telemetry Routes**: Supports versioned inference routes (`/{version}/models/{model}:streamGenerateContent` and `/{version}/models/{model}:generateContent` for `v1`, `v1beta`, and `v1beta1`), rewrites them upstream to `/v1beta1/projects/...` on `aiplatform.googleapis.com`, and acknowledges background telemetry calls (`POST /v1beta:*`) with `200 OK` (`{}`).

#### Option 1: Managed Corporate Workstations (`admin_settings.json`)
A sample [`admin_settings.json`](./admin_settings.json) is included in the root of this repository. You can also generate `admin_settings.json` directly from Terraform outputs—which automatically populates your gateway URL (`project_prefix` / `api_management_gateway_url`), provisioned APIM subscription key (`api_management_subscription_key`), and configured `allowed_models`:

```bash
terraform output -raw antigravity_admin_settings_json | jq . > admin_settings.json
```

Deploy `admin_settings.json` to developer workstations via MDM (Intune, Jamf, Ansible):
*   **Windows**: `%ProgramData%\Antigravity\admin_settings.json`
*   **macOS**: `/Library/Application Support/Antigravity/admin_settings.json`
*   **Linux**: `/etc/antigravity/admin_settings.json`

Pass your APIM subscription key in `gateway.customHeaders` as `Ocp-Apim-Subscription-Key`:

```json
{
  "gateway": {
    "enabled": true,
    "url": "https://<project_prefix>-apim.azure-api.net/vertex-ai",
    "apiKey": "YOUR_APIM_SUBSCRIPTION_KEY",
    "wireProtocol": "genai",
    "customHeaders": {
      "Ocp-Apim-Subscription-Key": "YOUR_APIM_SUBSCRIPTION_KEY",
      "X-Cost-Center": "Platform-Engineering"
    }
  },
  "models": {
    "defaultModelId": "gemini-3.8-flash",
    "list": [
      { "modelId": "gemini-4-argon" },
      { "modelId": "gemini-3.8-flash" },
      { "modelId": "gemini-3.5-flash-lite" }
    ]
  }
}
```

#### Option 2: Environment Variables (CLI, VS Code, Containers, Sandboxes)
Configure Antigravity in interactive shells (`~/.bashrc` / `~/.zshrc`), containers, or CI/CD runners:

```bash
export AGY_LLM_GATEWAY_URL="https://<project_prefix>-apim.azure-api.net/vertex-ai"
export AGY_LLM_GATEWAY_API_KEY="YOUR_APIM_SUBSCRIPTION_KEY"
export AGY_LLM_GATEWAY_WIRE_PROTOCOL="genai"
export AGY_LLM_GATEWAY_HEADERS="Ocp-Apim-Subscription-Key: YOUR_APIM_SUBSCRIPTION_KEY"
export AGY_LLM_GATEWAY_MODELS="gemini-4-argon,gemini-3.8-flash,gemini-3.5-flash-lite"
```

#### Verifying the Antigravity Connection
1. **Test streaming SSE directly with `curl`**:
   ```bash
   curl -N -X POST "https://<project_prefix>-apim.azure-api.net/vertex-ai/v1beta/models/gemini-3.8-flash:streamGenerateContent?alt=sse" \
     -H "Ocp-Apim-Subscription-Key: YOUR_APIM_SUBSCRIPTION_KEY" \
     -H "Authorization: Bearer YOUR_APIM_SUBSCRIPTION_KEY" \
     -H "Content-Type: application/json" \
     -H "User-Agent: antigravity/1.2.15 (aidev_client; auth_method=gateway)" \
     -d '{"contents": [{"role": "user", "parts": [{"text": "Reply with PONG"}]}]}'
   ```
2. **Test the Antigravity CLI**:
   ```bash
   agy -p "Explain binary search in Go"
   ```
3. **Verify Attribution in Google Cloud Logging**:
   In the GCP Console Logs Explorer for the Gemini project, run:
   ```text
   resource.type="aiplatform.googleapis.com/Endpoint" OR protoPayload.serviceName="aiplatform.googleapis.com"
   ```
   Verify `protoPayload.requestMetadata.callerSuppliedUserAgent` contains `antigravity/VERSION (aidev_client; auth_method=gateway)`.

## Using with Azure App Service
If you have deployed the App Service (`deploy_app_service = true`), the Terraform deploys an Azure App Service application that demonstrates how to call Vertex AI using the Google Gen AI SDK with credentials obtained through workload identity federation.

**NOTE:** When running on Azure App Service your credential config will differ as it must dynamically obtain the identity URL from [environment variables](https://learn.microsoft.com/en-us/azure/app-service/overview-managed-identity?tabs=portal%2Cpython#rest-endpoint-reference) for `IDENTITY_ENDPOINT` and `IDENTITY_HEADER`.

Additionally, the sample application in `gemini-streamlit-app` configures the Google Gen AI SDK using environment variables for `GOOGLE_GENAI_USE_VERTEXAI`, `GOOGLE_CLOUD_PROJECT` and `GOOGLE_CLOUD_LOCATION`.

The Terraform output includes the URL of the Azure Service App to validate functionality.

## Using with Azure VMs
Virtual Machines have access to the Azure Instance Metadata Service(`169.254.169.254`) to obtain the credentials unlike the identity URL used by App Service which requires a different credential config.
### Generate credential file
From your local machine generate the credential config file:
```
WIP_PROJECT_NUMBER=$(terraform output -raw wip_project_number)
POOL_ID=$(terraform output -raw pool_id)
PROVIDER_ID=$(terraform output -raw provider_id)
APPLICATION_ID_URI=$(terraform output -raw application_id_uri)

gcloud iam workload-identity-pools create-cred-config \
    projects/$WIP_PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL_ID/providers/$PROVIDER_ID \
    --azure \
    --app-id-uri $APPLICATION_ID_URI \
    --output-file=credential-config.json
```

### Test with VM
1. Create an Azure VM with a system assigned managed identity.
1. Grant the managed identity access to the Gemini GCP project
    ```bash
    # NOTE: Replace placeholder values for YOUR_AZURE_VM_RESOURCE_GROUP and YOUR_AZURE_VM_NAME
    AZURE_VM_RESOURCE_GROUP=YOUR_AZURE_VM_RESOURCE_GROUP
    AZURE_VM_NAME=YOUR_AZURE_VM_NAME
    MANAGED_IDENTITY=$(az vm show --resource-group $AZURE_VM_RESOURCE_GROUP --name $AZURE_VM_NAME --query identity.principalId -o tsv)
    WIP_PROJECT_NUMBER=$(terraform output -raw wip_project_number)
    POOL_ID=$(terraform output -raw pool_id)
    GEMINI_PROJECT_ID=$(terraform output -raw gemini_project_id)
    gcloud projects add-iam-policy-binding $GEMINI_PROJECT_ID \
        --member="principal://iam.googleapis.com/projects/$WIP_PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL_ID/subject/$MANAGED_IDENTITY" \
        --role="roles/aiplatform.user"
    ```
1. SSH into an Azure VM.
1. [Install](https://cloud.google.com/sdk/docs/install) the Google Cloud CLI
1. Add the credential file(`credential-config.json`) to the VM
1. Authenticate gcloud with the credential file.
    ```
    gcloud auth login --cred-file=credential-config.json
    ```
1. Validate access to the GCP project
    Use the credential file to [access Google Cloud](https://cloud.google.com/iam/docs/workload-identity-federation-with-other-clouds#cred-config-access)
    ```
    # NOTE: Replace placeholder values for YOUR_GEMINI_PROJECT_ID
    gcloud ai model-garden models list --project=YOUR_GEMINI_PROJECT_ID
    ```
