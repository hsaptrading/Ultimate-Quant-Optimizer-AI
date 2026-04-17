# TOOLS_SESSION_LOG â€” URB Strategy Factory
## Diario de Obra del URB_StrategyFactory

> Todo cambio en archivos de `URB_StrategyFactory/` va aquÃ­.
> Entradas nuevas van ARRIBA.

---

## 2026-04-17 09:55:41 -06:00 | Codex CLI
- Implementación en: `URB_StrategyFactory/backend/main.py`, `URB_StrategyFactory/backend/app/api/strategy_api.py`, `URB_StrategyFactory/backend/app/api/endpoints.py`, `URB_StrategyFactory/backend/app/api/data_api.py`, `URB_StrategyFactory/backend/app/api/generation.py`, `URB_StrategyFactory/backend/app/engine/genetic.py`, `URB_StrategyFactory/backend/app/engine/worker.py`, `URB_StrategyFactory/backend/app/engine/memory.py`, `URB_StrategyFactory/backend/app/core/ai_translator.py`, `URB_StrategyFactory/backend/app/core/state.py`, `URB_StrategyFactory/backend/app/core/backtester.py`, `URB_StrategyFactory/backend/app/strategies/urb_killzone.py`
- Objetivo: Diagnóstico completo del backend activo sin modificar código.
- Cambios: Solo lectura de código, arranque de diagnóstico con `uvicorn main:app --reload`, consultas HTTP a endpoints y prueba aislada del worker/backtester.
- Resultado: Parcial. El backend arranca y varias rutas responden, pero el flujo completo todavía no está sano.
- Reporte:
- ✅ `main.py` arranca `FastAPI` y registra routers en `/api`, `/api/config`, `/api/data`, `/api/builder`, `/api/strategy` y alias `/api/strategies`.
- ✅ `GET /` responde `{"status":"ok","message":"URB Engine Online","version":"0.1.0"}`.
- ✅ `GET /health` responde correctamente con Python `3.11.9`.
- ✅ `GET /api/config/schema` responde y devuelve el schema default de `URB Killzone`.
- ✅ `GET /api/strategy/list` responde con `urb_killzone`.
- ✅ `GET /api/strategies/list` también responde por el alias de compatibilidad.
- ✅ `GET /api/bridge/terminals` responde con 8 instalaciones MT5 detectadas.
- ✅ `GET /api/bridge/connect` conecta con MT5 real y devuelve cuenta `504057977` en `TTPMarkets-Server`.
- ✅ `GET /api/bridge/symbol/EURUSD` responde con metadata del símbolo.
- ❌ `GET /api/data/status` devuelve `500` antes y después de cargar datos.
- ✅ `POST /api/data/load_dummy` carga 100000 filas dummy.
- ✅ `POST /api/builder/start` acepta la orden de optimización y `GET /api/builder/status` llega a `Gen 2/2`.
- ❌ `GET /api/builder/strategies` devuelve lista vacía tras correr la optimización.
- ✅ AI Translator: hay `GROQ_API_KEY` presente en variables de entorno y Ollama local está activo en `http://localhost:11434` con modelo `qwen2.5-coder:latest`.
- ✅ `strategy_api.py` sí intenta usar Groq (`os.getenv("GROQ_API_KEY")`) o `ollama` según `ai_mode`.
- ❌ Motor genético end-to-end: no está funcionando de forma útil. La corrida termina, pero no produce estrategias válidas.
- Errores encontrados con causa probable:
- ❌ Desacople de estado en `data_api.py` vs `core/state.py`.
- Causa probable: `data_api.py` lee `data_state.active_start` y `data_state.active_end`, pero `DataState` define `start_date` y `end_date`. Eso explica el `500` en `/api/data/status`.
- ❌ Carga incorrecta de estrategia nativa en `worker.py`.
- Causa probable: el worker busca subclases de `app.core.base_strategy.BaseStrategy`, pero `urb_killzone.py` hereda de `app.strategies.base.BaseStrategy`. Como no coincide la clase base, el worker no reconoce `URBKillzoneStrategy` y la reemplaza por `DynamicAIStrategy`.
- ❌ Falla funcional del backtester en prueba aislada.
- Evidencia: al aislar `init_worker(...)` + `run_batch_backtest(...)`, el resultado fue `{'id': 'diag1', 'error': 'Backtest Run Error: Cada estrategia debe implementar su lógica de señales.', 'NetProfit': -999999}`.
- Causa probable: al envolver `urb_killzone` como `DynamicAIStrategy`, termina usando la implementación abstracta de `app.core.base_strategy.BaseStrategy.calculate_signals`.
- ❌ Arranque con `uvicorn main:app --reload` genera ruido severo de `multiprocessing.resource_sharer`.
- Evidencia: spam repetido de `PermissionError: [WinError 5] Acceso denegado` al crear named pipes.
- Causa probable: interacción entre `--reload`, multiprocessing/shared memory en Windows y restricciones del entorno actual. No impidió que rutas simples respondieran, pero contamina el runtime y puede afectar pruebas del engine.
- ⚠️ `generation.py` reporta progreso aunque no haya resultados válidos.
- Causa probable: `valid_results` filtra errores y el estado expone `progress/current_gen`, pero no hace visible por API que todos los individuos fallaron.
- Recomendación: arreglar primero la incompatibilidad entre `worker.py` y la jerarquía real de estrategias (`BaseStrategy` duplicada en `app/core` y `app/strategies`). Sin eso, el motor genético no puede evaluar `URBKillzone` ni ninguna estrategia Python nativa de forma confiable.
- Recomendación: corregir inmediatamente el contrato de `DataState` para que `/api/data/status` no devuelva `500`.
- Recomendación: después de esas dos correcciones, volver a probar el flujo mínimo `load_dummy -> start generation -> builder/strategies` sin `--reload` para aislar el problema de `WinError 5`.
- Pendiente: aprobación del diagnóstico y decisión de qué corregir primero en la siguiente sesión.

## [Las entradas irÃ¡n apareciendo conforme avance el trabajo]

### Formato esperado:
```
YYYY-MM-DD HH:MM:SS -06:00 | NombreIA
- ImplementaciÃ³n en: [archivo/mÃ³dulo]
- Objetivo: [para quÃ©]
- Cambios: [quÃ© se hizo]
- Resultado: [funcionÃ³ / parcial / fallÃ³]
- Pendiente: [si quedÃ³ algo]
```
