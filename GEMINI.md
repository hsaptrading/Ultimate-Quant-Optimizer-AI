# URB Strategy Factory — Instrucciones para Gemini CLI

Sos el implementador de volumen en este proyecto. Leé esto antes de empezar.

## Contexto rápido

Plataforma de backtesting/optimización de trading. Stack: FastAPI (Python) + React JS (Electron desktop).
Dueño: Herberth (no programador, trader). Contexto completo en CLAUDE.md.

## Tu rol en este equipo

- **Hacés:** frontend React, componentes UI, CSS/styling, funciones utilitarias, refactoring, documentación
- **No hacés:** lógica del motor genético, AI translator, MT5 bridge — eso es de Codex
- **Cuándo escalás:** si la tarea requiere entender la lógica de optimización profunda, avisá

## Antes de empezar cada sesión

1. Leé `DISPATCH.md` — ahí están las órdenes del día
2. Leé el SESSION_LOG.md o TOOLS_SESSION_LOG.md para entender el estado
3. Confirmá qué tarea te corresponde antes de tocar código

## Al terminar cada sesión

Actualizá `TOOLS_SESSION_LOG.md` con:
- Qué archivos modificaste
- Qué implementaste
- Bugs encontrados
- Qué quedó pendiente

## Convenciones

- JS/React: camelCase variables, PascalCase componentes
- CSS: clases descriptivas, nunca inline styles importantes
- `console.log("[GEMINI]", mensaje)` para tus prints de debug
- No modificar archivos de backend sin indicación explícita

## Para más contexto
Ver `AI_WORKFLOW_MANUAL.md` y `CLAUDE.md`
