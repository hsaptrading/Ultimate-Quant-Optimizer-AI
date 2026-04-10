# 🧠 URB Strategy Factory - Context Memory 

## 🎯 Vision & Philosophy
The goal is to evolve the URB Optimizer into a **Universal Strategy Factory**. 
- **The Problem:** MetaTrader 5's default optimizer is slow, inefficient, and limited. StrategyQuant X is powerful but overwhelming and heavily restrictive for completely custom algorithmic ideas.
- **The Solution:** A hybrid system combining the simplicity of an intuitive UI and the brute-force speed of native Python/Multiprocessing, heavily restricting MT5 to just act as a "cashier" (fetching historical data and broker spreads/swaps).

## 🚀 Key Achievements
1. **Frontend EA Discovery & Loading:** The UI dynamically lists (`/api/strategies/list`) valid EAs from the backend's source folder.
2. **Dynamic UI Generation (Digital Twin):** Uploading or selecting an `.mq5` EA parses its inputs dynamically via `MQL5Parser` without running MT5 or hardcoded schemas, extracting limits, enums, types, and labels.
3. **Core Decoupling (Worker.py):** The genetic algorithm workers no longer blindly call `urb_killzone`. They attempt to `importlib` a strategy dynamically to prevent multi-process crashes on unexpected schemas.
4. **Full Hardware Utilitization (Uncapped Mode):** Multiprocessing was refactored to use `multiprocessing.cpu_count()` natively, unlocking 100% of PC resources (e.g., 32 threads) for maximum speed.
5. **UI Thread Adjuster:** Added a 'CPU Cores' dynamic allocator on `BuilderView.js` allowing the user to reserve some cores to prevent OS freezing.

## 🛠️ The Coupling Mechanism Plan (How we execute custom EAs)
Since running raw MQL5 code in Python numpy/polars environments isn't viable for custom logic at millions of bars per second, we are implementing a **Hybrid Terminal Simulation (Terminal Simulator Bridge)**.

### The Problem it solves:
How do we evaluate EAs that include custom, complex, or unknown indicators (e.g., `ShaktiMagicIndicator.ex5`), where translating logic natively to Python vectors is impossible?

### The Hybrid Solution:
1. **Preparation:** The `.mq5` is imported. Genetic logic runs natively in Python to quickly evolve 1,000s of different variable combinations (`.set` files).
2. **Terminal Farming:** Instead of native calculation, Python spins up multiple *headless MT5 Tester processes* in parallel (e.g., 32 processes representing the 32 threads).
3. **Delegation:** Python feeds the generated `.set` combinations to these MT5 Testers, letting MT5 do the dirty "execution" work that it handles best natively with its custom indicators.
4. **Collection:** Python extracts the resulting Trade Reports back, calculating NetProfit/Drawdown instantly to evaluate fitness and spawn the next generation.
*Note:* MT5 handles execution/pricing correctness; our Python AI handles the evolutionary algorithm and variable mutation safely away from the MT5 Optimizer layout. 

## 🐛 Latest Bug Fixes
- **404 Select Route:** Fixed a bug in `strategy_api.py` where the `select_strategy` function lacked the `@router.post("/select")` decorator, causing the 'Accept & Use This Strategy' button in the Digital Twin view to throw a 404 error. 

*(This document should be updated iteratively to prevent context dilution across sessions.)*

---

## 🤖 [2026-02-26 19:06:45] AI Code Translation & Transpilation Pivot
1. **The LLM Pivot:** Moving slightly away from relying 100% on MT5 Terminal Farms for *everything*. We implemented an **AI Translator (`ai_translator.py`)** that takes a massive `.mq5` file and translates its MQL5 logic into pure Python/Numba execution (`@jit(nopython=True)`).
2. **Dynamic AI Injection:** A `DynamicAIStrategy` wrapper was created. When the user "Accepts" an AI-translated strategy, the Numba Workers (`worker.py`) dynamically `importlib` the AI-generated python file during the Genetic Algorithm. Numba iterates the EA logic mathematically at millions of ticks per second, bypassing MT5 entirely for known logic.
3. **Adaptive Hardware Engine:** To prevent out-of-memory OS crashes, the system measures available PC RAM via `psutil`. If an EA is massive (e.g., 55k tokens) and the user has low RAM, it aggressively restricts the local `Ollama` context window or falls back to throwing a graceful error.

## 🚀 [2026-02-26 19:06:45] Future Ecosystem & Business Scaling (SaaS)
* **Walled Garden (SaaS Mode):** The UI `ConfigView.js` was modified to hide the Groq API key input for the "Cloud" mode. The system now depends on the server's `.env` master key. This ensures users cannot bypass our billing or tracking, locking them into the "URB Cloud Pro" tier if they want lightning-fast translation for giant EAs without using their local hardware.
* **Specialized Trading RAG:** A long-term vision to build a Retrieval-Augmented Generation (RAG) system containing robust, mathematical trading templates and MetaQuotes documentation. It will "assemble" EAs flawlessly without LLM hallucinations.
* **Crowdsourced Swarm Intelligence:** A plan to intercept and log the most successful optimizations done by users organically. The winning Parameters, Code Structure, and Prompts will feed back into the Vector Database, making the central AI smarter and more robust with every user iteration.

## 🛡️ [2026-03-05 06:11:53] UI Ghost-State Fix & Strategy Vault
1. **UI Ghost-State Protection:** Fixed a critical bug in `ConfigView.js` where the frontend falsely reported "Active & Confirmed", even if Ollama locally failed due to RAM limits. The UI now parses the AI output for `[ERROR` tags, locks the interaction box (turning it red/not-allowed), and prevents the user from pushing bugged logic into the Numba engines.
2. **The Strategy Vault (Asset Caching):** Implemented an MD5 Hashing logic in `strategy_api.py`. When massive scripts (like `DualEA.mq5`) are successfully translated by expensive enterprise APIs, their Numba translation is saved locally alongside an `.hash` file. Re-uploading the exact same source code will yield a 1-millisecond instant load (`Success (Loaded from Vault)`), saving thousands of API tokens and heavy computational time. Any edits to the source code invalidate the hash, forcing a re-translation.
