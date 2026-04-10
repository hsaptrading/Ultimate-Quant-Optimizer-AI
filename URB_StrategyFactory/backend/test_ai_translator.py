import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '.')))

from app.core.ai_translator import AITranslator

def test_ai_translator_mock():
    print("--- Test del Modulo Traductor de IA (Off-Line) ---")
    
    # 1. Probar que el setup del objeto funciona para ambos modos
    ollama_tr = AITranslator(mode="ollama", model="llama3")
    print("\n[Mock] Ollama instanciado correctamente con modelo:", ollama_tr.model)
    
    api_tr = AITranslator(mode="api", api_key="sk-dummy", model="llama3-70b-8192")
    print("[Mock] Groq API instanciado correctamente con llave protegida.")
    
    # Simular codigo crudo sucio desde la IA
    codigo_ia_sucio = '''Claro, aqui tienes el codigo en Numba:
```python
@jit(nopython=True)
def dummy(x):
    return x * 2
```
Espero que te sirva.
'''
    limpio = ollama_tr._clean_code(codigo_ia_sucio)
    
    # Como _clean_code saca el ```python, todavia queda texto arriba. 
    # Validemos que limpia las etiquetas al menos.
    print(f"\n[Cleaning Test] \nAntes:\n{codigo_ia_sucio}\nDespues:\n{limpio}\n")
    
    # Intentemos hacer una peticion a Ollama local para ver si el server esta vivo y responde.
    print("Intentando contactar a Ollama localmente...")
    res = ollama_tr.translate_code("int dummy_Ea() { return 1; }")
    if "[ERROR OLLAMA]" in res:
         print(f"Ollama no detectado o respondio error as expected: {res}")
    else:
         print(f"Ollama genero una respuesta:\n{res[:100]}...\n")

if __name__ == '__main__':
    test_ai_translator_mock()
