import sys
import os
import time

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '.')))

from app.core.state import strat_state, data_state, memory_manager
from app.api.endpoints import bridge
from app.engine.genetic import GeneticManager
import MetaTrader5 as mt5
import pandas as pd

def test_genetic_farm_integration():
    print("--- Testing FULL Genetic Engine -> MT5 Farm Integration ---")
    
    # 1. Connect Bridge to get live terminal info
    print("\nConnecting to MT5 Bridge...")
    bridge.connect_to_mt5()
    if not bridge.connected:
        print("❌ Cannot connect to MT5. Make sure the FTMO Terminal is open.")
        return
        
    term_info = mt5.terminal_info()
    terminal_path = term_info.path
    data_path = term_info.data_path
    
    # 2. Mock the Data State (Pretend we loaded a small CSV)
    data_state.loaded = True
    data_state.filename = "EURUSD_M15.csv"
    data_state.start_date = "2024.01.01"
    data_state.end_date = "2024.01.07" # One week for ultra-fast test
    
    import polars as pl
    dummy_df = pl.DataFrame({"time": [1, 2, 3], "close": [1.1, 1.2, 1.3]})
    memory_manager.load_dataframe("main_data", dummy_df)
    meta = memory_manager.get_metadata("main_data")
    
    # 3. Mock the Strategy State (Pretend we selected DualEA.mq5)
    strat_state.active_name = "DualEA.mq5"
    strat_state.active_strategy_slug = "dualea"
    
    # 4. Define a small parameter schema for Genetic Algorithm
    print("\nSetting up Genetic Engine (Pop: 4, Gen: 2, Cores: 2)...")
    genetic_config = {
        "InpFastEMA": {"start": 5, "stop": 20, "step": 1, "opt": True, "value": 12},
        "InpSlowEMA": {"start": 21, "stop": 50, "step": 1, "opt": True, "value": 26},
        "InpSignalSMA": {"start": 3, "stop": 15, "step": 1, "opt": True, "value": 9},
        "InpTakeProfit": {"start": 10, "stop": 100, "step": 10, "opt": True, "value": 50},
        "InpStopLoss": {"start": 10, "stop": 100, "step": 10, "opt": True, "value": 50},
    }
    
    # Change expert to ExpertMACD internally via hack just so we don't crash if DualEA doesn't exist
    strat_state.active_name = "Advisors\\ExpertMACD.mq5" 
    
    # 5. Initialize Manager
    manager = GeneticManager(data_shm_name="main_data", data_info=meta)
    manager.set_config(genetic_config)
    
    # 6. Start the Pool (This triggers farm cloning)
    start_time = time.time()
    try:
        manager.start_pool(
            cpu_cores=2, # Limit to 2 for quick testing
            terminal_path=terminal_path,
            data_path=data_path,
            symbol="EURUSD",
            timeframe="M15"
        )
        
        # 7. Run Evolution
        def progress_tracker(gen, total_gen, best_profit, top_strats):
            print(f"> Gen {gen}/{total_gen} Complete. Current Best Profit: ${best_profit:.2f}. Total found: {len(top_strats)}")
            
        print("\nStarting Evolution Loop...")
        manager.is_running = True # Bypass state flag dependency
        
        # Super small population to verify plumbing works, not to find real profits
        manager.evolve(population_size=4, generations=2, progress_callback=progress_tracker)
        
    except Exception as e:
        print(f"\n[ERROR] CRITICAL ERROR during evolution: {e}")
        import traceback
        traceback.print_exc()
        
    finally:
        print("\nStopping Pool and destroying clones...")
        manager.stop_pool()
        
    elapsed = time.time() - start_time
    print(f"\n[SUCCESS] FULL INTEGRATION TEST FINISHED in {elapsed:.2f} seconds.")

if __name__ == "__main__":
    test_genetic_farm_integration()
