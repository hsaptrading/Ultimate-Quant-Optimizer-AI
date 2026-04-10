# 🔌 Strategy Coupling Mechanism Plan

This document outlines the proposed architecture to interpret and execute the logic of any given Expert Advisor (EA) dynamically within the URB Optimizer Backend. 

Currently, our engine parses `.mq5` inputs perfectly, exposing them to the UI, but relies on a manually transpiled Python (Numba) equivalent for the backtesting core logic. To achieve true universality, we need a mechanism to couple arbitrary strategy logic to the optimization engine without manual translation.

## 🎯 The Challenge
The Genetic Optimizer (Python/Multiprocessing) requires a native way to evaluate `calculate_signals()` at millions of bars per second. An arbitrary `.mq5` file cannot be natively executed by the Python process at this speed.

## 🚀 Options & Architectures

### Option 1: Strategy Building Blocks (The StrategyQuant Approach - Recommended)
Instead of trying to parse and execute arbitrary, unstructured MQL5 code, we formalize our strategies into **Building Blocks**. 
- **The Concept**: We build a library of vectorized native Python/Numba handlers for common trading concepts (e.g., `EMA_Cross`, `RSI_Threshold`, `Breakout_Entry`, `Trailing_Stop`).
- **How it Works**: The backend parses the `.mq5` (or a `.set` + `.json` manifest) and maps its features to our native building blocks, constructing an execution tree. E.g., `DualEA.mq5` uses `Breakout_Entry + PullbackFilter(RSI) + Exit(ATR_Trailing)`. The engine dynamically composes a pipeline combining array operations for these blocks. 
- **Pros**: Lightning fast, perfectly aligned with Python's vectorization capabilities (Polars/Numpy), high scalability, matches the conceptual intent of StrategyQuant generation.
- **Cons**: Requires standardizing the EAs to use known blocks. Black-box or wildly unique EAs won't map automatically.

### Option 2: The Universal C++ Engine
In previous iterations, the need for a C++ engine was identified to bypass Python's multiprocessing overhead and GIL limitations.
- **The Concept**: Build a highly-optimized C++ backtesting core (exported as a Python extension or DLL).
- **How it Works**: A transpiler translates the subset of MQL5 used by the EAs into C++ classes. When a new EA is uploaded, it is compiled as a shared library (`.dll` or `.so`) against the C++ Engine's headers. Python simply acts as the API layer, calling the compiled library for fitness evaluation.
- **Pros**: Absolute maximum performance. Closest 1:1 behavioral match to MT5.
- **Cons**: High development overhead. Requires setting up a dynamic build system (G++ / MSVC) that runs on the fly when adding a new strategy.

### Option 3: Distributed MT5 Testing (Bridge Mode)
- **The Concept**: Instead of simulating the logic, our Python engine delegates the heavy lifting to actual MetaTrader 5 terminals.
- **How it Works**: We boot up an array of headless MT5 instances (or rely on the MT5 Cloud/Local Farm). Python generates the parameters for the population, creates `.set` files, triggers the MT5 terminal command-line tester, and extracts the results via the API bridge or output HTML/XML.
- **Pros**: Zero translation errors. 100% EA compatibility. No need to maintain parallel backtesting logic.
- **Cons**: Dramatically slower due to MT5 initialization and I/O overhead. Limited by PC RAM/Terminal count constraints. Weak integration with custom fitness functions.

## 🛠️ Implementation Plan: Phase 1 -> Phase 2

For the current evolution of the **URB Strategy Factory**, we propose a hybrid **Phase 1 Strategy Protocol**, transitioning towards **Option 1 (Building Blocks)**.

### Phase 1: The `Strategy` Base Class Pattern
1. **Decouple the Backend API**: `worker.py` dynamically loads Python strategy classes corresponding to the selected EA instead of hardcoding `urb_killzone`.
2. **Strategy Payload**: When an EA is added, a companion Python template is generated inheriting from `BaseStrategy`. The user (or an LLM) implements `urb_backtest_core`-style Numba code inside.
3. **Execution**: The genetic algorithm uses Python's `importlib` and multiprocessing dynamically to execute the specific compiled logic for the active Strategy Slug.

### Phase 2: Vectorized Pipeline (Building Blocks)
1. **Core Overhaul**: We replace the monolithic `urb_backtest_core` loop with pre-computed signal arrays. 
2. **Pipeline**: `Long_Signal = (Close > EMA_200) & (RSI < 30) & (Market_Time in Killzone)`.
3. **Dynamic Generation**: The backend reads a strategy config, dynamically constructs the above boolean mask equations utilizing Numba/NumPy, applies vector logic, and spits out equity curves instantly without any explicit `for` loop over price bars.

---
*Next steps for this architecture:* Create the dynamically loaded strategy registry in `app/engine/worker.py` using `importlib` so custom Python strategy files in `app/strategies/` map automatically to the selected `.mq5` schema.
