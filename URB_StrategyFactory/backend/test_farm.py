import sys
import os
import time

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '.')))

from app.engine.mt5_farm import MT5FarmController

def test_farm_execution():
    print("--- Testing MT5 Farm Controller ---")
    
    # Needs to match the terminal path installed on the system
    terminal_path = r"C:\Program Files\FTMO MetaTrader 5\terminal64.exe"
    
    # Make sure this EA exists in the MT5 Terminal's MQL5/Experts folder.
    # But since we are only testing the Farm mechanism, we will use a default one like "Advisors\ExpertMACD.ex5"
    # or the one you've been working on if it's already compiled in the terminal.
    # We will use "Advisors\ExpertMACD" which comes by default in MT5 to guarantee it works.
    expert_name = "Advisors\\ExpertMACD" 
    symbol = "EURUSD"
    
    print(f"Initializing Farm for {expert_name} on {symbol}...")
    
    # Use 1 node for simple test
    controller = MT5FarmController(
        terminal_path=terminal_path,
        expert_name=expert_name,
        symbol=symbol,
        timeframe="M15",
        max_nodes=1
    )
    
    # We found out that the actual FTMO data folder is here:
    data_path = r"C:\Users\Shakti Ayala\AppData\Roaming\MetaQuotes\Terminal\49CDDEAA95A409ED22BD2287BB67CB9C"
    
    print("Provisioning isolated clone node...")
    controller.clone_nodes(original_data_path=data_path)
    
    if not controller.nodes:
        print("Failed to provision nodes.")
        return
        
    test_node_path = controller.nodes[0]
    print(f"Node ready at: {test_node_path}")
    
    # Dummy parameters for MACD
    dummy_params = {
        "id": "TEST_001",
        "InpFastEMA": 12,
        "InpSlowEMA": 26,
        "InpSignalSMA": 9,
        "InpTakeProfit": 50,
        "InpStopLoss": 50
    }
    
    print("Generating Configs & Executing Headless Terminal Mode...")
    print("This usually takes a few seconds as the terminal opens silently and closes.")
    
    start_time = time.time()
    
    # Start Date and End Date format: YYYY.MM.DD
    results = controller.execute_worker_test(
        params=dummy_params, 
        exe_path=test_node_path,
        start_date="2024.01.01", 
        end_date="2024.01.31" # Just one month for speed test
    )
    
    elapsed = time.time() - start_time
    
    print(f"\nExecution Finished in {elapsed:.2f} seconds.")
    print("Parsed Results from MT5 XML:")
    print(results)
    
    if results.get("NetProfit") != -999999.0:
        print("\nSUCCESS: XML Report parsed correctly! The terminal properly simulated the EA.")
    else:
        print("\nFAILED: Could not correctly parse report or terminal errored out.")

if __name__ == "__main__":
    test_farm_execution()
