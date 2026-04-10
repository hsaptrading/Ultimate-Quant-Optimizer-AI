import os
import time
from app.engine.mt5_farm import MT5FarmController
import MetaTrader5 as mt5

def debug_farm():
    if not mt5.initialize():
        print("MT5 Init failed")
        return
        
    info = mt5.terminal_info()
    term_path = info.path
    data_path = info.data_path
    
    print("Found terminal:", term_path)
    print("Found data path:", data_path)
    
    farm = MT5FarmController(
        terminal_path=term_path,
        expert_name="Ultimate Range Breaker - copia\\Ultimate Range Breaker Fussion.ex5",
        symbol="US100",
        timeframe="M15",
        max_nodes=1
    )
    
    print("Cloning nodes...")
    farm.clone_nodes(data_path)
    
    node_exe = farm.nodes[0]
    print(f"Executing node: {node_exe}")
    
    # Run a test
    res = farm.execute_worker_test(
        params={"id": "test_1", "InpSignalTF": 15},
        exe_path=node_exe,
        start_date="2024.01.01",
        end_date="2024.12.31"
    )
    
    print("\n--- Worker Final Result ---")
    print(res)

if __name__ == "__main__":
    debug_farm()
