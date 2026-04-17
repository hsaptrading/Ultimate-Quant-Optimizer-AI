# DISPATCH — URB Strategy Factory
> **Actualizado:** 2026-04-17 | **Por:** Claude (Chef Ejecutivo)
> **Fase activa:** Fase 1 — Walk-Forward Validation
> **Estado:** Preparación para trabajo en VSCode

---

## ⚡ TAREA ACTIVA — Tarea 1: Diagnóstico del sistema

**Asignado a:** Codex CLI
**Prioridad:** 🔴 ALTA — sin esto no podemos avanzar
**Archivos a revisar (solo leer, NO modificar):**
- URB_StrategyFactory/backend/main.py
- URB_StrategyFactory/backend/app/api/strategy_api.py
- URB_StrategyFactory/backend/app/engine/genetic.py
- URB_StrategyFactory/backend/app/core/ai_translator.py
- URB_StrategyFactory/backend/app/engine/worker.py

**Lo que tenés que hacer:**
1. Leer los archivos listados arriba
2. Intentar arrancar el backend: `uvicorn main:app --reload` desde la carpeta backend
3. Reportar qué endpoints existen y si responden
4. Identificar si el motor genético puede correr end-to-end
5. Identificar si el AI Translator tiene API key configurada (Groq u Ollama)
6. Listar cualquier error o dependencia faltante que encuentres

**Criterio de terminado:**
Un reporte claro en TOOLS_SESSION_LOG.md con:
- ✅ / ❌ por cada punto revisado
- Lista de errores encontrados con causa probable
- Recomendación de qué arreglar primero

**NO hacer:**
- No modificar ningún archivo todavía
- No instalar dependencias sin confirmación
- Solo diagnosticar y reportar

---

## 📬 COLA DE TAREAS (orden de ejecución)

### Tarea 1 — Diagnóstico de estado actual
**Para:** Codex CLI
**Descripción:** Leer los archivos principales del backend y hacer un diagnóstico:
- ¿Qué endpoints existen y funcionan?
- ¿El motor genético corre end-to-end?
- ¿El AI Translator conecta con Groq/Ollama?
- ¿Qué falta para que el flujo completo funcione?
**Output esperado:** Reporte en TOOLS_SESSION_LOG.md

### Tarea 2 — Walk-Forward Engine (cuando Tarea 1 esté aprobada)
**Para:** Codex CLI
**Descripción:** Implementar el módulo de Walk-Forward en `engine/` 
**Instrucciones detalladas:** Claude Chat las escribirá aquí cuando llegue el momento.

### Tarea 3 — Walk-Forward UI (cuando Tarea 2 esté aprobada)
**Para:** Gemini CLI
**Descripción:** Agregar sección de Walk-Forward en BuilderView.js
**Instrucciones detalladas:** Claude Chat las escribirá aquí cuando llegue el momento.

---

## 📌 NOTAS DEL CHEF EJECUTIVO

**Contexto crítico para los agentes:**

El proyecto tiene dos "versiones" de código en la misma carpeta:
- `URB_Optimizer/` — versión vieja, Python puro, optimizaba solo el Range Breaker. Referencia histórica.
- `URB_StrategyFactory/` — versión nueva con FastAPI + React. ESTA es la activa.

Todo trabajo nuevo va en `URB_StrategyFactory/`. No tocar `URB_Optimizer/` ni `URB PYTHON/` salvo que Herberth lo indique.

El nombre "URB" es legado. El producto real es una plataforma universal de optimización — no está limitado al Range Breaker.

---

## 🔄 HISTORIAL DE DESPACHOS

### 2026-04-17 — Despacho #1
- Setup inicial y diagnóstico de estado
- Estado: PENDIENTE (esperando traslado a VSCode)
