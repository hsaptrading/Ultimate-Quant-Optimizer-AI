import multiprocessing
import numpy as np
import polars as pl
import time
from ..core.backtester import FastBacktester
from .memory import SharedMemoryManager, MemoryClient

# Global instance for the worker process
# This avoids pickling the entire dataset for every task
_backtester_instance = None
# We don't need SharedMemoryManager instance in worker, we act as client
_memory_client = None 

_is_mq5 = False
_mt5_controller = None
_mt5_node_exe = None
_mt5_start_date = None
_mt5_end_date = None

from ..strategies.urb_killzone import URBKillzoneStrategy
from ..core.state import strat_state

def init_worker(shm_name: str, metadata: dict):
    """
    Initializer function for each worker process.
    Connects to Shared Memory if Native, or Initializes MT5 Clone if MQ5.
    """
    global _backtester_instance, _memory_client, _is_mq5, _mt5_controller, _mt5_node_exe, _mt5_start_date, _mt5_end_date
    _is_mq5 = metadata.get('is_mq5', False)
    
    try:
        strat_name = metadata.get('active_strategy', 'urb_killzone')
        
        # --- Python Native Mode ---
        # 1. Attach to Shared Memory
        _memory_client = MemoryClient(metadata)
        data_dict = _memory_client.get_data()
            
            # 2. Reconstruct DataFrame (Lightweight wrapper)
        df = pl.DataFrame(data_dict)
        
        # 3. Resolve Strategy Class Dynamically
        strategy_class = None
        safe_name = strat_name.replace(" ", "_").lower().replace(".mq5", "")
        
        try:
            import importlib
            import inspect
            from ..core.base_strategy import BaseStrategy
            from ..core.dynamic_strategy import DynamicAIStrategy
            
            # Intenta cargar la clase Python nativa primero
            module = importlib.import_module(f"...strategies.{safe_name}", package=__name__)
            for name, obj in inspect.getmembers(module, inspect.isclass):
                if issubclass(obj, BaseStrategy) and obj is not BaseStrategy and obj is not DynamicAIStrategy:
                    strategy_class = obj
                    break
                    
            # Si no encontró una clase hija (porque es código Numba suelto de la IA), usa el Wrapper Dinámico
            if strategy_class is None:
                print(f"[Worker] Detectado código crudo Numba. Empaquetando '{safe_name}' en Wrapper Dinámico...")
                class DynamicInstance(DynamicAIStrategy):
                    def __init__(self):
                        super().__init__(ai_module_name=safe_name)
                strategy_class = DynamicInstance
                
        except ImportError as e:
            print(f"[Worker] Warning: No Companion Python Logic found for '{strat_name}'. Error: {e}")
            
        if strategy_class is None:
            # Fallback to URB for now to avoid crashing the engine on unknown EA schemas
            from ..strategies.urb_killzone import URBKillzoneStrategy
            print(f"[Worker] Fallback: Defaul URBKillzoneStrategy assigned to {multiprocessing.current_process().name}")
            strategy_class = URBKillzoneStrategy
            
        # 4. Initialize Backtester with Strategy
        _backtester_instance = FastBacktester(df, strategy_class)
        print(f"[Worker {multiprocessing.current_process().name}] Native Python Strategy Loaded: {strategy_class.__name__}")
            
    except Exception as e:
        print(f"[Worker Initialization Error] {e}")
        import traceback
        traceback.print_exc()

def run_batch_backtest(strategies: list):
    """
    Runs a batch of strategies using lightning-fast Python computation.
    """
    global _backtester_instance
    results = []
    
    # Native Python Execution
    if _backtester_instance is None:
        return [{"error": "Native Worker not initialized"}] * len(strategies)
        
    for params in strategies:
        try:
            res = _backtester_instance.run(params)
            # Append ID to result to track back
            res['id'] = params.get('id', 'unknown')
            results.append(res)
        except Exception as e:
            results.append({'id': params.get('id'), 'error': str(e), 'NetProfit': -999999})
            
    return results
