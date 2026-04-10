# URB Strategy Factory - Base de Conocimiento (FAQ y Propuesta de Valor)

Este documento recopila las dudas, inquietudes y conceptos técnicos discutidos durante el desarrollo del sistema. Está diseñado para servir como fuente de verdad para futuras preguntas frecuentes (FAQ) de clientes, material publicitario y documentación explicativa para usuarios sin perfil técnico.

---

## 🏗️ 1. Filosofía de Optimización y Rendimiento (El Hardware)

### P: ¿Este sistema necesita una "Súper Computadora" o Servidor gigantesco para funcionar?
**R:** No. A diferencia de otros programas heredados (como StrategyQuant X), nuestra arquitectura fue diseñada expresamente para no devorar la memoria de tu computadora. 
**La Analogía:** Si otros programas son como organizar una biblioteca intentando memorizar todos los libros al mismo tiempo (saturando tu Memoria RAM y trabando la PC), nuestro sistema es un lector hiper-veloz. Lee de los libreros (tu Disco Duro) página por página a la velocidad del rayo (usando el procesador).
**Qué pedirle a tu PC:** El sistema brilla y escala si tienes un buen *Procesador (Cores)* y un *Disco de Estado Sólido (SSD)* rápido, pero funcionará perfectamente y sin colapsar en máquinas modestas, usando cantidades mínimas de RAM.

### P: Si el sistema lanza simulaciones invisibles (Headless), ¿el no dibujar las velas en pantalla afecta en algo los resultados o la precisión?
**R:** No afecta absolutamente en nada. Te entregará el mismo porcentaje exacto de acierto al centavo.
**La Razón:** Para una computadora, una vela verde o roja no es un dibujo; matemáticamente es solo una lista de 4 números (Apertura, Máximo, Mínimo, Cierre). Al apagar el "dibujo visual" que gasta inútilmente tu Tarjeta Gráfica y ralentiza tu PC, canalizamos el 100% de la fuerza bruta de tu computadora hacia hacer los cálculos matemáticos a la velocidad de la luz. Es eficiencia pura, eliminando peso cosmético muerto.

---

## 🧬 2. La "Fábrica" Genética vs Los Optimizadores Tradicionales

### P: ¿Por qué es mejor nuestro Motor Genético de Python conectado a MetaTrader 5?
**R:** Porque combina "El Cerebro más Inteligente" con "El Músculo más Confiable".
Tradicionalmente, optimizar en MT5 es rígido y lento. Nuestro sistema Híbrido separa el trabajo: Python y su Inteligencia Artificial actúan como el cerebro que inventa y "muta" genéticamente miles de combinaciones estratégicas de forma inteligente. En paralelo, crea Nodos "Clones" de MetaTrader 5 que actúan como pura fuerza bruta operativa. Python le arroja el trabajo a los clones para que validen que todo funcionará al 100% en condiciones reales de broker, saltándose las limitaciones o atascos normales de usar un solo terminal de escritorio.

---

## 🔧 3. Superando las Limitaciones de la Industria

### P: He intentado correr varios MetaTraders a la vez y Windows se vuelve loco o no me deja abrir la misma cuenta. ¿Cómo lo resolvieron ustedes?
**R:** A esto le llamamos "El Engaño Maestro". MetaTrader está programado con una restricción de "Instancia Única" (protege y bloquea tus pesados archivos de historial de años pasados para que nadie los rompa). Nuestro Cerebro (El Farm Controller) sortea esto clonando tu programa de forma microscópica (nodos de 50MB en vez de Gigabytes). En lugar de copiar los datos bloqueados, usa tecnología del Sistema Operativo (*Junctions*) para "espejear" temporalmente tu conexión a internet y credenciales. Cada clon descarga en paralelo su propia historia, trabaja en una isla aislada y se autodestruye al terminar para mantener tu PC perfectamente limpia.

---

*Nota del Desarrollador (Antigravity): Este documento es vivo. Se irá expandiendo con nuevas explicaciones y descubrimientos clave a medida que avancemos.*
