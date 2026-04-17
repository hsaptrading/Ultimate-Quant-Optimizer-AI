# Manual De Trabajo Con IA — URB Strategy Factory
## Sistema Híbrido de Coordinación Multi-Agente

> **Versión:** 2.0 — Fusión del protocolo original + sistema operativo multi-agente
> **Proyecto:** URB Strategy Factory (SA Trading Tools)
> **Propietario:** Herberth

---

## Principio General

Toda IA que trabaje aquí debe documentar su trabajo de forma automática y constante.
No basta con implementar cambios. También debe dejar registro de:
- qué hizo
- cuándo lo hizo
- por qué lo hizo
- qué problema encontró
- cómo lo resolvió
- qué riesgos o pendientes detectó

**Formato de timestamp obligatorio:**
`YYYY-MM-DD HH:MM:SS -06:00 | NombreIA`

Ejemplo: `2026-04-17 09:30:00 -06:00 | Codex`

---

## Jerarquía de Agentes

| Rol | Agente | Responsabilidad | Costo |
|-----|--------|-----------------|-------|
| Director | Herberth | Define QUÉ se construye, aprueba fases | - |
| Chef Ejecutivo | Claude Chat | Arquitectura, decisiones críticas, escribe DISPATCH.md | Tokens limitados |
| Sous Chef | Codex CLI | Backend Python complejo, lógica de algoritmos, tests | ChatGPT Plus |
| Cocinero | Gemini CLI | Frontend React/JS, refactoring, tareas de volumen | Gratis |
| Emergencia | Claude Code | Debugging profundo que otros no resuelven | Último recurso |

**Regla de escalado:** Gemini primero → si no resuelve, Codex → si no resuelve, Claude Code.

---

## Sistema de Archivos — Mapa Completo

```
URB Optimizer/
│
├── AI_WORKFLOW_MANUAL.md        ← Este archivo. Base de todos los protocolos.
│
├── [ARCHIVOS DE CONTEXTO — leídos automáticamente por cada agente]
├── CLAUDE.md                    ← Claude Code lee esto al abrir el proyecto
├── GEMINI.md                    ← Gemini CLI lee esto al iniciar
├── CODEX.md                     ← Codex CLI lee esto al iniciar
│
├── [ARCHIVOS OPERATIVOS — la "pizarra central"]
├── DISPATCH.md                  ← Órdenes del día (Claude Chat las escribe)
├── SESSION_LOG.md               ← Diario de obra general (todos escriben)
├── TOOLS_SESSION_LOG.md         ← Diario específico del URB_StrategyFactory
├── TODO.md                      ← Lista maestra de tareas por fases
├── TESTING.md                   ← Registro de pruebas y aprobaciones
├── BACKUP_RECOVERY.md           ← Checkpoints de retorno
│
├── [CONOCIMIENTO DURABLE]
├── GLOSSARY.md                  ← Términos técnicos en lenguaje simple
├── AI_BLIND_DISCUSSION_LOG.md   ← Debates multi-IA con protocolo anti-sesgo
└── notes/                       ← Zettelkasten — ideas reutilizables
    ├── walk-forward-basics.md
    ├── genetic-vs-grid-search.md
    ├── mt5-bridge-architecture.md
    └── ...
```

---

## Dónde Va Cada Tipo de Información

### SESSION_LOG.md
- Avances generales del proyecto
- Cambios importantes
- Problemas detectados y resueltos
- Decisiones relevantes
- *No va:* teoría larga ni conocimiento abstracto permanente

### BACKUP_RECOVERY.md
- Estados clave antes de cambios grandes
- Hitos estables a los que conviene poder volver
- *Analogía:* puntos de guardado de videojuego

### TOOLS_SESSION_LOG.md
- Todo lo específico al URB_StrategyFactory y sus módulos
- Errores y soluciones por componente
- Cambios de arquitectura internos
- *Regla:* si el cambio toca un archivo dentro de URB_StrategyFactory, va aquí

### DISPATCH.md
- Las órdenes del día escritas por Claude Chat
- Quién hace qué, con qué instrucciones exactas
- Criterios de "terminado" para cada tarea
- *Regla:* lo escribe Claude Chat, lo ejecutan Codex/Gemini

### TODO.md
- Lista maestra organizada por fases
- Solo avanzar a la siguiente fase con la anterior aprobada

### TESTING.md
- Registro formal de pruebas por módulo
- Estado: APROBADO / FALLIDO / PARCIAL
- Veredicto final de Herberth antes de avanzar

### GLOSSARY.md
- Términos técnicos explicados para no-programador
- Con analogías y ejemplos concretos

### notes/
- Conocimiento reutilizable y durable (no cronológico)
- Comparaciones, tradeoffs, principios de diseño

### AI_BLIND_DISCUSSION_LOG.md
- Debates estructurados entre IAs
- Protocolo anti-sesgo (ver sección dedicada)

---

## Protocolo Operativo Diario

### Al INICIAR sesión con cualquier agente implementador:
```
"Lee CLAUDE.md (o GEMINI.md/CODEX.md), luego lee DISPATCH.md y SESSION_LOG.md.
Dime qué tarea te corresponde y qué entendiste antes de empezar."
```

### Al TERMINAR sesión con cualquier agente:
```
"Antes de cerrar, actualiza SESSION_LOG.md (o TOOLS_SESSION_LOG.md) con:
1. Qué hiciste exactamente
2. Archivos modificados
3. Errores encontrados y cómo los resolviste
4. Qué quedó pendiente
5. Notas para el próximo agente"
```

### Regla anti-sobreescritura:
Un solo agente trabaja en un archivo a la vez. Nunca dos agentes en paralelo en el mismo archivo.

---

## Protocolo de Fases

**Regla de oro: NUNCA avanzar sin aprobar la fase actual.**

```
FASE 1: PLANIFICACIÓN (Claude Chat)
  → Define el módulo, diseña la arquitectura
  → Escribe las instrucciones en DISPATCH.md
  → Define criterios de "terminado"

FASE 2: IMPLEMENTACIÓN (Codex o Gemini)
  → Lee DISPATCH.md y ejecuta
  → Agrega prints/logs de debug
  → Actualiza SESSION_LOG o TOOLS_SESSION_LOG

FASE 3: PRUEBAS INTERNAS (el mismo agente implementador)
  → Ejecuta el código
  → Verifica criterios de "terminado"
  → Documenta en TESTING.md

FASE 4: VERIFICACIÓN (Herberth)
  → Prueba manualmente
  → Si OK → marca APROBADO en TESTING.md y TODO.md
  → Si no OK → vuelve a Fase 2 con instrucciones claras

FASE 5: SIGUIENTE MÓDULO
  → Solo después de APROBADO
  → Claude Chat actualiza DISPATCH.md
```

**Tamaño de módulos:** máximo 1-2 funcionalidades por ciclo. Si algo es grande, dividirlo.

---

## Cómo Registrar un Error

```
YYYY-MM-DD | NombreIA
- Error: [qué falló]
- Dónde: [archivo, función, línea aprox.]
- Causa: [detectada o probable]
- Solución: [qué se aplicó]
- Riesgo pendiente: [si quedó algo sin resolver]
```

## Cómo Registrar una Implementación

```
YYYY-MM-DD | NombreIA
- Implementación en: [archivo/módulo]
- Objetivo: [para qué se hizo]
- Cambios: [qué se agregó o modificó]
- Resultado: [funcionó, parcial, falló]
```

---

## AI_BLIND_DISCUSSION_LOG — Protocolo Anti-Sesgo

Cuando se necesite que múltiples IAs debatan una decisión técnica:

1. Claude Chat abre una ronda en estado `BLIND`
2. Cada IA agrega su propuesta SIN leer las demás
3. Cuando Claude Chat cambia a `OPEN`, se pueden leer, contrastar y refutar
4. Al final, conclusión marcada como: `APPROVED` / `REJECTED` / `REWORK` / `NO_DECISION`

**Formato de entrada:**
```
YYYY-MM-DD HH:MM:SS -06:00 | NombreIA | PROPOSAL
- Hipótesis:
- Ventajas:
- Riesgos:
- Veredicto provisional:
```

---

## Regla de Calidad

La documentación no debe ser relleno. Debe ser útil, clara, breve cuando baste, detallada cuando haga falta. El objetivo es que cualquier IA nueva que entre al proyecto pueda orientarse en menos de 5 minutos leyendo estos archivos.

---

## Regla de Continuidad

Antes de empezar a trabajar, toda IA debe:
1. Leer este manual
2. Leer DISPATCH.md para saber qué toca hoy
3. Leer SESSION_LOG.md para entender dónde estamos
4. Continuar con trazabilidad consistente

**Objetivo final:** Que el proyecto nunca dependa de la memoria de una sola IA o sesión.
