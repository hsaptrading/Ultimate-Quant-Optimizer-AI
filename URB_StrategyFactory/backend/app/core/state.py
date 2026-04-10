from typing import List, Any
# Import SharedMemoryManager (Ensure no circular imports)
# memory.py checks nothing external usually
from ..engine.memory import SharedMemoryManager

# --- Global Shared Components ---
memory_manager = SharedMemoryManager()

# --- Generator State ---
class GeneratorState:
    is_running = False
    progress = 0
    total_generations = 0
    current_generation = 0
    strategies_found = [] 
    current_best = -999999.0
    manager = None # Holds the GeneticManager instance

gen_state = GeneratorState()

# --- Data State ---
class DataState:
    loaded: bool = False
    filename: str = ""
    total_rows: int = 0
    min_date: str = ""
    max_date: str = ""
    
    # Active Configuration
    start_date: str = ""
    end_date: str = ""
    oos_split_pct: float = 0.80 
    modeling_type: str = "m1_ohlc" # 'm1_ohlc' or 'tick'
    
data_state = DataState()

# --- Strategy State ---
class StrategyState:
    active_name: str = "URB Killzone Strategy"
    active_strategy_slug: str = "urb_killzone" # Internal Slug for Class Loading
    active_schema: Any = None # Holds the list of inputs for the UI

strat_state = StrategyState()
