import requests
import json
from typing import Optional

class AITranslator:
    """
    Modulo para traducir estrategias de MQL5/PineScript a Python (Numba) 
    usando Inteligencia Artificial (Ollama Local o API Externa como Groq).
    """
    def __init__(self, mode="ollama", api_key: Optional[str] = None, model: Optional[str] = None):
        self.mode = mode.lower() # 'ollama' o 'api'
        self.api_key = api_key
        self.model = model or "" # Will resolve dynamically if empty
        
        # Endpoint configs
        self.ollama_url = "http://localhost:11434/api/generate"
        self.groq_url = "https://api.groq.com/openai/v1/chat/completions"

    def _get_system_prompt(self) -> str:
        return (
            "Eres un experto en Algoritmos Genéticos de Trading y desarrollo en Numba Python. "
            "Tu objetivo es traducir la lógica de señales del código MQL5 a una función Numba estructurada "
            "que SIMULE UN BACKTEST COMPLETO y retorne el Net Profit final como un float.\n"
            "REGLAS ESTRÍCTAS:\n"
            "1. NO uses print(). Numba no lo soporta bien y frena la ejecución masiva.\n"
            "2. DEBES devolver ÚNICAMENTE código Python válido. Cero explicaciones, cero markdown.\n"
            "3. La función debe llamarse exactamente 'mi_estrategia' y estar decorada con @jit(nopython=True).\n"
            "4. Los primeros 6 parámetros son obligatorios: times, opens, highs, lows, closes, volumes.\n"
            "5. Después, desglosa los inputs externos (Inp...).\n"
            "Estructura OBLIGATORIA:\n"
            "```python\n"
            "import numpy as np\n"
            "from numba import jit\n"
            "@jit(nopython=True)\n"
            "def mi_estrategia(times, opens, highs, lows, closes, volumes, InpParam1...):\n"
            "    balance = 10000.0\n"
            "    position = 0 # 0=flat, 1=long, -1=short\n"
            "    entry_price = 0.0\n"
            "    for i in range(100, len(closes)):\n"
            "        # 1. Calcula valores de indicadores hasta la vela actual 'i'\n"
            "        # 2. Evalua SL / TP si position != 0\n"
            "        # 3. Traduce la logica MQL5 para definir si Comprar (position=1) o Vender (position=-1)\n"
            "    return float(balance)\n"
            "```"
        )

    def translate_code(self, source_code: str) -> str:
        """Envia el codigo a la IA y retorna el codigo Python generado."""
        prompt = f"Traduce el siguiente codigo MQL5 a la plantilla de Python Numba:\n\n{source_code}"
        
        if self.mode == "ollama":
            return self._translate_ollama(prompt)
        elif self.mode == "api":
            return self._translate_groq(prompt)
        else:
            raise ValueError("Modo no soportado. Usa 'ollama' o 'api'.")

    def _translate_ollama(self, prompt: str) -> str:
        # 1. Resolve which model is installed
        if not self.model:
            try:
                tags_resp = requests.get("http://localhost:11434/api/tags", timeout=5)
                tags_resp.raise_for_status()
                models = tags_resp.json().get("models", [])
                if models:
                    self.model = models[0]["name"] # Use the first available (e.g. qwen2.5-coder:latest)
                else:
                    self.model = "llama3" # Fallback
            except Exception:
                self.model = "llama3"
                
        import psutil
        
        # 2. Adaptacion de Recursos (Motor Inteligente)
        # 1 token aprox. = 3.5 a 4 caracteres en codigo
        estimated_content_tokens = int(len(prompt) / 3.5)
        # Requerimos el tamaño del input + 2048 reservados para el output
        target_ctx = estimated_content_tokens + 2048 
        
        # Medimos RAM disponible
        avail_gb = psutil.virtual_memory().available / (1024**3)
        
        # Asumimos ~6,000 tokens consumen ~1GB en modelos GGML ligeros, 
        # restando 2GB de holgura para Windows:
        max_safe_ctx = int(max(0, avail_gb - 2.0) * 6000)
        max_safe_ctx = max(4096, max_safe_ctx) # Minimo garantizado
        
        if target_ctx > max_safe_ctx and estimated_content_tokens > 8192:
            return f"# [ERROR DE RECURSOS OLLAMA] Tu PC es como un motor 800cc para esta pista. El archivo requiere ~{target_ctx} tokens de memoria, pero solo tienes {avail_gb:.1f}GB de RAM libres (Límite seguro: {max_safe_ctx} tokens). Por favor, cierra pestañas o programas, o usa la Nube de Groq."
            
        final_ctx = int(min(target_ctx, 100000)) # Limite duro a 100k
        final_ctx = max(final_ctx, 4096)
        
        payload = {
            "model": self.model,
            "system": self._get_system_prompt(),
            "prompt": prompt,
            "stream": False,
            "options": {
                "num_ctx": final_ctx
            }
        }
        try:
            # Aumentar timeout porque los modelos pesados/lentos pueden tardar mas de 2 min
            response = requests.post(self.ollama_url, json=payload, timeout=600)
            if response.status_code != 200:
                body = response.json() if "application/json" in response.headers.get("Content-Type", "") else response.text
                return f"# [ERROR OLLAMA] Error en la respuesta ({response.status_code}): {body}"
            response.raise_for_status()
            data = response.json()
            return self._clean_code(data.get("response", ""))
        except requests.exceptions.ReadTimeout:
            return "# [ERROR OLLAMA] El archivo es gigante y Ollama excedió el tiempo máximo (10 minutos). Prueba con la nube Groq o optimiza el MQL5."
        except requests.exceptions.ConnectionError:
            return "# [ERROR OLLAMA] No se pudo conectar a localhost:11434. ¿Esta Ollama en ejecucion?"
        except Exception as e:
            return f"# [ERROR OLLAMA] Ocurrio un error al generar: {e}"

    def _translate_groq(self, prompt: str) -> str:
        if not self.api_key:
            return "# [ERROR] Se requiere una API KEY de Groq."
            
        if not self.model:
            self.model = "llama-3.3-70b-versatile" # Stable Groq model
            
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": self._get_system_prompt()},
                {"role": "user", "content": prompt}
            ],
            "temperature": 0.1
        }
        try:
            response = requests.post(self.groq_url, headers=headers, json=payload, timeout=60)
            if response.status_code != 200:
                 body = response.json() if "application/json" in response.headers.get("Content-Type", "") else response.text
                 str_body = str(body).lower()
                 if response.status_code in [413, 429] and ("too large" in str_body or "limit ext" in str_body or "tokens" in str_body):
                     return "# [ERROR API] Este EA es gigantesco y superó tu límite asignado en Groq (aprox. 12,000 ~ 30,000 tokens gratis). Prueba conectando tu propio hardware con Ollama Local."
                 return f"# [ERROR API] Error de Groq ({response.status_code}): {body}"
                 
            response.raise_for_status()
            data = response.json()
            content = data["choices"][0]["message"]["content"]
            return self._clean_code(content)
        except requests.exceptions.ReadTimeout:
            return "# [ERROR API] La nube demoró mucho en responder (Timeout). Intenta usar un archivo mas pequeño o reconecta."
        except Exception as e:
            return f"# [ERROR API] Excepción no controlada: {e}"

    def _clean_code(self, raw_text: str) -> str:
        """Extrae unicamente el codigo de la respuesta aislando los bloques ``` """
        import re
        
        # Buscar bloques de codigo especificos (python, mql5, o sin especificar)
        # matches = re.findall(r'```(?:python)?(.*?)```', raw_text, re.IGNORECASE | re.DOTALL)
        
        # Un patron mas permisivo para capturar lo que esta entre triples comillas
        pattern = re.compile(r'```(?:python|py)?\s*\n(.*?)\n```', re.IGNORECASE | re.DOTALL)
        match = pattern.search(raw_text)
        
        if match:
             return match.group(1).strip()
             
        # Si la IA no uso bloques markdown y solo devolvio texto, limpiamos lineas
        # que claramente no son codigo (como "Aqui tienes el codigo:")
        lines = raw_text.splitlines()
        clean_lines = []
        for line in lines:
            ll = line.lower().strip()
            # Ignorar saludos y confirmaciones comunes al inicio/fin
            if ll.startswith("claro") or ll.startswith("aqui tienes") or ll.startswith("aqui esta") or ll.startswith("espero "):
                continue
            clean_lines.append(line)
            
        return "\n".join(clean_lines).strip()
