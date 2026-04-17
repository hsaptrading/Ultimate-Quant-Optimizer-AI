# TODO — URB Strategy Factory
## Plan de Fases Actualizado (Abril 2026)

> **Foco actual:** MT5 → Custom Strategy Import → llevarla a producción completa
> **Regla:** Solo avanzar de fase con la anterior APROBADA por Herberth

---

## ✅ COMPLETADO (base existente)

- ✅ MQL5 Parser dinámico (extrae inputs sin correr MT5)
- ✅ Digital Twin UI (formulario auto-generado)
- ✅ Motor genético con multiprocessing (32 threads)
- ✅ AI Translator MQL5 → Python/Numba (via Groq/Ollama)
- ✅ Strategy Vault (caché MD5 de traducciones)
- ✅ MT5 Farm Bridge (delegación a instancias headless)
- ✅ Frontend base (ConfigView + BuilderView)
- ✅ Launcher .bat funcional

---

## 🔥 FASE ACTIVA: Fase 1 — Walk-Forward Validation

### Módulo 1.1 — Walk-Forward Engine (backend)
- [ ] Diseño del split IS/OOS configurable por el usuario
- [ ] Integración con el motor genético existente (engine/genetic.py)
- [ ] Métricas por ventana: profit factor, drawdown, win rate, expectancy
- [ ] Almacenamiento de resultados por ventana en databank
- [ ] ⚡ PRUEBAS del módulo
- [ ] ✔️ APROBACIÓN de Herberth

### Módulo 1.2 — Walk-Forward UI (frontend)
- [ ] Sección en BuilderView para configurar WF (num. ventanas, % IS/OOS)
- [ ] Visualización de resultados por ventana (tabla + gráfico de equity)
- [ ] ⚡ PRUEBAS del módulo
- [ ] ✔️ APROBACIÓN de Herberth

---

## ⏳ FASE 2 — Monte Carlo Robustness Testing

### Módulo 2.1 — Monte Carlo Engine
- [ ] Generador de simulaciones por permutación de trades
- [ ] Cálculo de percentiles (P5, P50, P95) de métricas clave
- [ ] Umbral configurable de robustez (ej: P10 drawdown < X%)

### Módulo 2.2 — Monte Carlo UI
- [ ] Visualización de distribución de resultados
- [ ] Indicador visual de robustez (verde/amarillo/rojo)

---

## ⏳ FASE 3 — Results & Export mejorado

### Módulo 3.1 — Dashboard de resultados
- [ ] Vista unificada: métricas principales + WF + MC en una pantalla
- [ ] Export a CSV, PDF de reporte completo

### Módulo 3.2 — .set Export para MT5
- [ ] Generar el .set file del mejor candidato listo para MT5
- [ ] Instrucciones de uso en la interfaz

---

## ⏳ FASE 4 — PropFirm Mode

### Módulo 4.1 — Filtro PropFirm
- [ ] Reglas configurables: max daily DD, max total DD
- [ ] Filtrado automático de candidatos que violan las reglas
- [ ] Score de "prop-friendliness" por estrategia

### Módulo 4.2 — PropFirm Optimizer
- [ ] Modo de optimización que prioriza bajo drawdown sobre profit
- [ ] Sugerencia de position sizing para cumplir reglas

---

## ⏳ FASE 5 — Preloaded Templates

- [ ] Selección de 5-10 estrategias base pre-validadas
- [ ] UI de selección de template antes del Builder
- [ ] Descripción de cada template con parámetros recomendados

---

## 🔮 FASE 6 — Atom Builder SQX-Style (baja prioridad)

- [ ] Definir catálogo de indicadores disponibles
- [ ] Motor de combinación genética desde bloques
- [ ] Generador de código MQL5 desde la combinación ganadora

---

## 📌 PENDIENTES TÉCNICOS CONOCIDOS

- [ ] Eliminar carpeta `ruflo/` del proyecto ECO Vision
- [ ] Añadir `URB PYTHON/generated_sets/` al .gitignore
- [ ] Limpiar código legacy de URB_Optimizer (la versión original de range breaker)
- [ ] Renombrar proyecto: el nombre "URB" ya no refleja el scope real

---

## 💡 NOTAS DE ARQUITECTURA

El proyecto evolucionó desde optimizar una sola estrategia (Ultimate Range Breaker)
a ser una plataforma universal. El nombre "URB" es histórico, el producto real es
un "Strategy Optimization Factory" genérico para cualquier EA o estrategia de trading.

La ruta de comercialización: MT5 Custom Import → WF + MC → PropFirm Mode → SaaS.
