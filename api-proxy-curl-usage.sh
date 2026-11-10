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

GATEWAY_URL=$(terraform output -raw api_management_gateway_url)
GCP_PROJECT_ID=$(terraform output -raw gemini_project_id)
API_KEY=$(terraform output -raw api_management_subscription_key)

echo "=== 1. Standard SDK / Collection-Scoped Request ==="
curl -X POST "${GATEWAY_URL}/vertex-ai/publishers/google/models/gemini-3.8-flash:generateContent" \
  -H "Ocp-Apim-Subscription-Key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{ "contents": [ { "role": "user", "parts": [ { "text": "Tell me a joke about space." } ] } ] }'

echo -e "\n\n=== 2. Antigravity Enterprise Gateway Streaming SSE Request (/v1beta) ==="
curl -N -X POST "${GATEWAY_URL}/vertex-ai/v1beta/models/gemini-3.8-flash:streamGenerateContent?alt=sse" \
  -H "Ocp-Apim-Subscription-Key: ${API_KEY}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -H "User-Agent: antigravity/1.2.15 (aidev_client; auth_method=gateway)" \
  -d '{"contents": [{"role": "user", "parts": [{"text": "Reply with PONG"}]}]}'

echo -e "\n\n=== 3. Antigravity Telemetry Acknowledgment Check (/v1beta:*) ==="
curl -X POST "${GATEWAY_URL}/vertex-ai/v1beta:recordMetrics" \
  -H "Ocp-Apim-Subscription-Key: ${API_KEY}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -H "User-Agent: antigravity/1.2.15 (aidev_client; auth_method=gateway)" \
  -d '{}'
echo ""