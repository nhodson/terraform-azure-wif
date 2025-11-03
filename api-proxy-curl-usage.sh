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
API_KEY="<UPDATE_ME>"

curl -X POST "${GATEWAY_URL}/vertex-ai/v1/projects/${GCP_PROJECT_ID}/locations/us-central1/publishers/google/models/gemini-2.5-flash:generateContent" \
  -H "Ocp-Apim-Subscription-Key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{ "contents": [ { "role": "user", "parts": [ { "text": "Tell me a joke about space." } ] } ] }'