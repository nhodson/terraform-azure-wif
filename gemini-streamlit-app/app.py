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


import streamlit as st
from google import genai

# Automatically authenticated by setting GOOGLE_APPLICATION_CREDENTIALS environment variable
# GOOGLE_GENAI_USE_VERTEXAI and GOOGLE_CLOUD_PROJECT env variables set to configure genai client
try:
    client = genai.Client()
except Exception as e:
    st.error(f"Failed to authenticate with Google GenAI. Please ensure you have configured Application Default Credentials correctly. Error: {e}")
    st.stop()


# Initialize chat history
if "messages" not in st.session_state:
    st.session_state.messages = []

# Display chat messages from history on app rerun
for message in st.session_state.messages:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])

# React to user input
if prompt := st.chat_input("What is up?"):
    # Display user message in chat message container
    with st.chat_message("user"):
        st.markdown(prompt)
    # Add user message to chat history
    st.session_state.messages.append({"role": "user", "content": prompt})

    # Get model response
    try:
        response = client.models.generate_content(
            model='gemini-2.5-flash',
            contents=prompt,
        )
        response_text = response.text
    except Exception as e:
        response_text = f"An error occurred: {e}"

    # Display assistant response in chat message container
    with st.chat_message("assistant"):
        st.markdown(response_text)
    # Add assistant response to chat history
    st.session_state.messages.append({"role": "assistant", "content": response_text})

