
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

