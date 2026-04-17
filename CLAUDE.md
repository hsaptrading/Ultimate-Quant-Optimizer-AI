# URB Strategy Factory — Instrucciones para Claude Code
## Leé esto completo antes de tocar cualquier archivo.

---

## ¿Qué es este proyecto?

**URB Strategy Factory** es una plataforma de backtesting y optimización de estrategias de trading, construida para que cualquier trader (no programador) pueda optimizar sus ideas sin depender del tester nativo de MT5 ni de plataformas complejas como SQX.

**Stack:** Python (FastAPI backend) + React JS (frontend Electron desktop app)

**Autor:** Herberth — SA Trading Tools, El Salvador.

---

## Estado actual del proyecto (Abril 2026)

### Lo que ya funciona:
- **MQL5 Parser:** lee archivos `.mq5` y extrae inputs dinámicamente sin correr MT5
- **Digital Twin UI:** genera formulario de configuración automáticamente basado en el EA
- **Motor genético:** algoritmo evolutivo con multiprocessing usando 32 threads (Ryzen 9 7950X3D)
- **AI Translator:** convierte MQL5 a Python/Numba (`@jit`) via Groq/Ollama API
- **Strategy Vault:** cacheo MD5 de traducciones costosas (no reprocesa el mismo EA)
- **MT5 Farm Bridge:** delega backtests complejos a múltiples instancias de MT5 en paralelo
- **Frontend:** 3 vistas — Configuration, Strategy Builder, Results & Export

### Lo que FALTA (prioridad en orden):
1. Walk-Forward Validation (siguiente milestone principal)
2. Monte Carlo robustness testing
3. Portfolio Builder (múltiples estrategias)
4. PropFirm Mode (ajuste automático a reglas de drawdown)
5. Preloaded Templates (estrategias base precargadas)
6. Atom Builder SQX-Style (generador desde indicadores — último en lista)

### Plataformas soportadas:
- **MT5** — más avanzado, es la prioridad
- **Pine Script / TradingView** — parcialmente funcional
- **NinjaTrader, cTrader, Crypto** — UI mostrada pero sin implementación

---

## Arquitectura del código

```
URB Optimizer/
├── URB_StrategyFactory/
│   ├── backend/
│   │   ├── main.py                    ← FastAPI app, punto de entrada
│   │   ├── app/
│   │   │   ├── api/
│   │   │   │   ├── strategy_api.py    ← Upload EA, select, parse
│   │   │   │   ├── generation.py      ← Generación de .set files
│   │   │   │   ├── data_api.py        ← Manejo de datos históricos
│   │   │   │   └── endpoints.py       ← Endpoints generales
│   │   │   ├── core/
│   │   │   │   ├── mql5_parser.py     ← Parser de archivos .mq5
│   │   │   │   ├── ai_translator.py   ← MQL5 → Python/Numba via LLM
│   │   │   │   ├── backtester.py      ← Motor de backtesting Python
│   │   │   │   ├── dynamic_strategy.py ← Wrapper dinámico para estrategias
│   │   │   │   ├── set_generator.py   ← Generador de .set files
│   │   │   │   ├── resource_manager.py ← Control de RAM/CPU
│   │   │   │   └── indicators.py      ← Indicadores técnicos
│   │   │   ├── engine/
│   │   │   │   ├── genetic.py         ← Algoritmo genético principal
│   │   │   │   ├── worker.py          ← Workers multiprocessing
│   │   │   │   ├── mt5_farm.py        ← MT5 Terminal Farm bridge
│   │   │   │   └── memory.py          ← Memoria del proceso evolutivo
│   │   │   ├── bridges/
│   │   │   │   └── mt5_bridge.py      ← Conexión Python ↔ MT5
│   │   │   └── strategies/
│   │   │       ├── urb_killzone.py    ← Estrategia URB portada a Python
│   │   │       ├── dualea.py          ← DualEA portada
│   │   │       └── ultimate_h4_lsweep.py ← H4 LSweep portada
│   │   └── strategies_source/         ← EAs originales en MQL5
│   │       ├── DualEA.mq5
│   │       └── Ultimate H4 LSweep.mq5
│   └── frontend/
│       └── src/
│           ├── App.js
│           ├── views/
│           │   ├── ConfigView.js      ← Selección plataforma + modo
│           │   └── BuilderView.js     ← UI principal con Digital Twin
│           └── styles/
```

---

## Reglas de trabajo en este proyecto

1. **Nunca tocar** `strategies_source/` sin indicación explícita — son los EAs originales
2. **Nunca modificar** archivos `.hash` manualmente — son generados por el Vault
3. **El `worker.py`** usa multiprocessing agresivo — cuidar con imports y globals
4. **El `ai_translator.py`** llama a APIs externas (Groq/Ollama) — siempre manejar errores
5. **Primero leer** `DISPATCH.md` para saber qué toca hacer hoy
6. **Al terminar**, actualizar `TOOLS_SESSION_LOG.md` con lo implementado

## Convenciones de código

- Python: snake_case, docstrings en funciones clave, prints de debug en MAYÚSCULAS `[DEBUG]`
- JavaScript/React: camelCase, componentes en PascalCase
- Logs de progreso: `print(f"[URB] {mensaje}")` para distinguirlos
- Errores fatales: `print(f"[ERROR] {descripción}")` antes de raise

## Para iniciar el sistema localmente:
```bash
# Backend
cd URB_StrategyFactory/backend
uvicorn main:app --reload

# Frontend (en otra terminal)
cd URB_StrategyFactory/frontend
npm run dev
```

O usar el launcher: `Start_URB_Factory.bat`

---

## Protocolo de trabajo
Lee `AI_WORKFLOW_MANUAL.md` para las reglas completas.
Lee `DISPATCH.md` para las tareas de hoy.
Lee `TOOLS_SESSION_LOG.md` para ver el historial del proyecto.
