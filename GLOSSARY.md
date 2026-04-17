# GLOSSARY — URB Strategy Factory
## Términos Técnicos en Lenguaje Simple

---

### Walk-Forward Validation
**Qué es:** Una técnica para probar si una estrategia optimizada realmente funciona o si solo "memorizó" los datos históricos.

**Cómo funciona:** Dividís los datos en pedazos. Optimizás la estrategia en el primer pedazo (período "In-Sample"), luego la probás en el siguiente pedazo que nunca vio (período "Out-of-Sample"). Si funciona en ambos, la estrategia es más confiable.

**Analogía:** Es como estudiar para un examen con unos ejercicios (IS), pero el examen real (OOS) tiene ejercicios distintos. Si pasás ambos, realmente aprendiste.

---

### Monte Carlo Testing
**Qué es:** Una prueba de robustez que simula miles de escenarios distintos del futuro para ver qué tan confiable es la estrategia.

**Cómo funciona:** Toma los trades históricos y los reordena aleatoriamente miles de veces. Si en la mayoría de los escenarios la estrategia sigue siendo rentable, es robusta.

**Analogía:** En vez de hacer una sola prueba de manejo, probás el auto en 1000 rutas distintas para ver si siempre funciona.

---

### Overfitting (Sobreoptimización)
**Qué es:** Cuando una estrategia está tan ajustada a los datos históricos que funciona perfectamente en el pasado pero falla en el futuro.

**Analogía:** Como memorizar exactamente las respuestas de un examen viejo pero no entender el tema. Cuando llega un examen nuevo, fallás.

---

### Algoritmo Genético
**Qué es:** Un método de optimización inspirado en la evolución biológica. Crea muchas combinaciones de parámetros, selecciona las mejores, las "cruza" para crear nuevas combinaciones, y repite el proceso.

**Analogía:** Como criar animales seleccionando los más rápidos para que sus crías sean más rápidas todavía.

---

### Multiprocessing
**Qué es:** Usar múltiples núcleos del procesador al mismo tiempo para hacer varias tareas en paralelo.

**En este proyecto:** El motor genético corre 32 procesos simultáneos (uno por thread del Ryzen 9 7950X3D) para evaluar 32 combinaciones de parámetros al mismo tiempo.

**Analogía:** En vez de tener 1 cocinero preparando 32 platos uno por uno, tenés 32 cocineros preparando todos al mismo tiempo.

---

### Numba / @jit
**Qué es:** Una librería de Python que compila código Python a lenguaje de máquina, haciéndolo mucho más rápido.

**En este proyecto:** El AI Translator convierte el MQL5 a Python/Numba para que el backtesting corra a velocidad nativa en vez de velocidad de Python puro.

---

### FastAPI
**Qué es:** Un framework de Python para crear APIs web. Es el "servidor" que conecta el frontend (React) con el backend (Python).

**Analogía:** Es el mesero que lleva los pedidos de la mesa (frontend) a la cocina (backend) y trae de vuelta los platos.

---

### React / Electron
**Qué es:** React es una librería de JavaScript para construir interfaces de usuario. Electron envuelve una app web (React) para que funcione como una app de escritorio nativa.

**En este proyecto:** La UI del URB Factory es una app React corriendo dentro de Electron, por eso tiene barra de menú (File/Edit/View) como cualquier programa de Windows.

---

### Strategy Vault
**Qué es:** El sistema de caché del AI Translator. Guarda una "huella digital" (hash MD5) de cada EA traducido. Si subís el mismo EA de nuevo, carga la traducción guardada instantáneamente en vez de volver a llamar a la API.

**Analogía:** Como guardar la foto de un documento en vez de volver a sacarlo del cajón cada vez.

---

### .set File
**Qué es:** Archivo de configuración que MetaTrader 5 usa para cargar parámetros en un EA. Contiene nombre y valor de cada parámetro.

**En este proyecto:** El optimizador genera miles de .set files (uno por combinación), los pasa al MT5 Farm, y recibe los resultados de cada uno.

---

[Nuevos términos se agregan aquí conforme aparezcan]
