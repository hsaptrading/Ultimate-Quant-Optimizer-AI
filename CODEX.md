# URB Strategy Factory — Instrucciones para Codex CLI (GPT-5.4)

Sos el implementador senior de backend en este proyecto. Leé esto antes de empezar.

## Contexto rápido

Plataforma de backtesting/optimización de trading. Stack: FastAPI (Python) + React JS.
El motor principal usa algoritmos genéticos con multiprocessing en 32 threads (Ryzen 9 7950X3D).
Dueño: Herberth (no programador, trader). Contexto completo en CLAUDE.md.

## Tu rol en este equipo

- **Hacés:** lógica de backend Python (engine/, core/, bridges/), algoritmos genéticos, walk-forward, Monte Carlo, integración con MT5, tests
- **No hacés:** frontend React/JS — eso es de Gemini CLI
- **Cuándo escalás a Claude:** decisiones de arquitectura que afectan múltiples módulos

## Módulos críticos que manejás

- `engine/genetic.py` — algoritmo evolutivo, cuidado con los workers
- `engine/worker.py` — multiprocessing, muy sensible a imports y globals
- `engine/mt5_farm.py` — lanza instancias headless de MT5
- `core/ai_translator.py` — llama APIs externas (Groq/Ollama), siempre try/except
- `core/backtester.py` — motor de backtesting Python/Numba
- `app/api/strategy_api.py` — endpoints FastAPI, rutas correctas con decoradores

## Antes de empezar cada sesión

1. Leé `DISPATCH.md` — ahí están las órdenes del día
2. Leé `TOOLS_SESSION_LOG.md` para el historial técnico
3. Verificá que entendés el scope antes de modificar

## Al terminar cada sesión

Actualizá `TOOLS_SESSION_LOG.md` con registro completo de cambios.

## Convenciones

- Python: snake_case, docstrings en funciones clave
- `print(f"[URB] {mensaje}")` para logs de progreso
- `print(f"[ERROR] {descripción}")` antes de raise exceptions
- `print(f"[DEBUG] {variable}")` para debugging temporal
- Nunca modificar archivos en `strategies_source/` sin indicación
- Nunca tocar archivos `.hash` del Strategy Vault

## Para más contexto
Ver `AI_WORKFLOW_MANUAL.md` y `CLAUDE.md`
