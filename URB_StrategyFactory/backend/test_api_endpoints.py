import requests

# Test Groq
groq_url = "https://api.groq.com/openai/v1/chat/completions"
# Actually, Groq base URL is https://api.groq.com/openai/v1 and endpoint is /chat/completions.
# Let's see what error it returns when no key or dummy key is used
try:
    resp = requests.post(groq_url, json={"model": "llama3-8b-8192", "messages": [{"role": "user", "content": "hi"}]})
    print("Groq response without auth:", resp.status_code, resp.text)
except Exception as e:
    print("Groq error:", e)

# Test Ollama
ollama_url = "http://localhost:11434/api/generate"
try:
    resp = requests.post(ollama_url, json={"model": "llama3", "prompt": "hi"})
    print("Ollama response llama3:", resp.status_code, resp.text)
except Exception as e:
    print("Ollama error:", e)

try:
    resp = requests.post(ollama_url, json={"model": "llama3.2", "prompt": "hi"}) # Try another name
    print("Ollama response llama3.2:", resp.status_code, resp.text)
except Exception as e:
    print("Ollama error:", e)
    
try:
    # See what models are actually installed
    resp = requests.get("http://localhost:11434/api/tags")
    print("Ollama tags:", resp.status_code, resp.text)
except Exception as e:
    print("Ollama tags error:", e)
