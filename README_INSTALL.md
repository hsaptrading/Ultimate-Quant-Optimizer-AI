# README — Paquete de Traslado a VSCode
## URB Strategy Factory — SA Trading Tools

---

## Qué hay en esta carpeta

Estos son los archivos de coordinación del proyecto URB Strategy Factory.
Deben vivir en la RAÍZ de la carpeta `URB Optimizer/` en tu PC.

## Instrucciones de instalación

**Paso 1:** Copiá todos estos archivos a `C:\Users\Shakti Ayala\Desktop\URB Optimizer\`

**Paso 2:** Creá la carpeta `notes/` en esa misma raíz (si no existe), y copiá los archivos de `notes/` dentro.

**Paso 3:** Abrí VSCode en esa carpeta (File → Open Folder → URB Optimizer)

**Paso 4:** Verificá que los agentes pueden arrancar:
```powershell
# En la terminal integrada de VSCode (Ctrl + `)
claude    # Claude Code
gemini    # Gemini CLI
codex     # Codex CLI
```

**Paso 5:** Leé DISPATCH.md para saber qué hacer primero.

## Archivos y su función

| Archivo | Qué hace |
|---------|----------|
| AI_WORKFLOW_MANUAL.md | Protocolo base — todas las reglas del juego |
| CLAUDE.md | Auto-cargado por Claude Code — contexto del proyecto |
| GEMINI.md | Auto-cargado por Gemini CLI — rol y reglas |
| CODEX.md | Auto-cargado por Codex CLI — rol y reglas |
| DISPATCH.md | Órdenes del día — Claude Chat las escribe |
| SESSION_LOG.md | Diario general del proyecto |
| TOOLS_SESSION_LOG.md | Diario específico del URB_StrategyFactory |
| TODO.md | Lista de tareas por fases |
| TESTING.md | Registro de pruebas |
| BACKUP_RECOVERY.md | Checkpoints de retorno |
| GLOSSARY.md | Términos técnicos explicados |
| AI_BLIND_DISCUSSION_LOG.md | Debates multi-IA |
| notes/ | Conocimiento durable reutilizable |

## Flujo de trabajo diario

1. Abrís Claude Chat → "Revisemos el URB, actualizá DISPATCH.md con tareas de hoy"
2. Claude escribe las órdenes
3. Abrís VSCode → iniciás Codex o Gemini según lo asignado
4. El agente lee DISPATCH.md y trabaja
5. Al terminar: actualiza SESSION_LOG o TOOLS_SESSION_LOG
6. Vos probás → actualizás TESTING.md → aprobás o pedís correcciones
