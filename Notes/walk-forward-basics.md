# Walk-Forward Validation — Conceptos Clave
## notes/walk-forward-basics.md

---

## Qué es y por qué importa

Walk-Forward (WF) es el estándar de oro en validación de estrategias algorítmicas. Resuelve el problema del overfitting demostrando que una estrategia optimizada no solo "memoriza" el pasado sino que tiene capacidad predictiva real.

## Tipos de Walk-Forward

**Rolling (ventana deslizante):**
```
IS1[2020-2021] → OOS1[2022-Q1]
IS2[2021-2022] → OOS2[2022-Q2]  
IS3[2022-2023] → OOS3[2022-Q3]
```
Cada ventana avanza en el tiempo. La IS siempre tiene el mismo tamaño.

**Anchored (anclada):**
```
IS1[2018-2021] → OOS1[2022-Q1]
IS2[2018-2022] → OOS2[2022-Q2]
IS3[2018-2023] → OOS3[2022-Q3]
```
La IS siempre empieza desde el mismo punto y crece. Más datos de entrenamiento con el tiempo.

## Métricas clave por ventana OOS

- Profit Factor: > 1.3 mínimo, > 1.5 bueno
- Max Drawdown: < 15% recomendado para prop firms
- Win Rate: depende del tipo de estrategia
- Expectancy: positiva en la mayoría de ventanas OOS

## Señales de overfitting en WF

- IS performance >> OOS performance consistentemente
- OOS results erráticos (algunas ventanas muy buenas, otras muy malas)
- Solo 1-2 ventanas OOS positivas de 5-8 totales

## Implementación en URB

El WF debe integrarse con el motor genético existente:
1. Definir splits IS/OOS sobre los datos históricos disponibles
2. Por cada split: correr optimización genética en IS
3. Tomar el mejor candidato IS y evaluarlo en OOS
4. Reportar métricas por ventana + resumen agregado

## Ratio IS/OOS recomendado

- Conservador: 70% IS / 30% OOS
- Estándar: 80% IS / 20% OOS
- Para mercados volátiles: 75% IS / 25% OOS

## Referencias
- "Evidence-Based Technical Analysis" - David Aronson
- "Building Winning Algorithmic Trading Systems" - Kevin Davey
