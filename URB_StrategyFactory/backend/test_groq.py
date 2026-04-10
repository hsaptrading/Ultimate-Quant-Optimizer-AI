import requests
# Test Groq with wrong model
try:
    resp = requests.post("https://api.groq.com/openai/v1/chat/completions", headers={"Authorization": "Bearer ASDF"}, json={"model": "llama3", "messages": [{"role": "user", "content": "hi"}]})
    print("Groq wrong model:", resp.status_code, resp.text)
except Exception as e:
    print("Groq wrong model error:", e)
