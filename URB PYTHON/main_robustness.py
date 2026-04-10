
import os
import sys
import polars as pl
from src.modules.robustness import RobustnessTester
from src.utils.set_converter import SetConverter

def main():
    print("=== URB Robustness Tester (Python) ===")
    
    # 1. Load Data
    parquet_file = "USATECHIDXUSD.tick.utc2_M1.parquet"
    if not os.path.exists(parquet_file):
        print(f"Error: Parquet file {parquet_file} not found. Run main_builder.py first.")
        return
        
    m1_data = pl.read_parquet(parquet_file)
    print(f"Data Loaded: {len(m1_data)} bars.")

    # 2. Check for Candidates
    databank_dir = "databank"
    files = [f for f in os.listdir(databank_dir) if f.startswith("candidates") and f.endswith(".json")]
    
    if not files:
        print("No candidates found in 'databank/'. Run main_builder.py first.")
        return
        
    # Pick the latest candidate file
    files.sort(reverse=True) # Sort by name (timestamp is in name)
    latest_file = files[0]
    
    print(f"Testing candidates from: {latest_file}")
    
    tester = RobustnessTester(m1_data, databank_dir)
    tester.run_batch_test(latest_file, "robust.json")
    
    # 3. Export to Set Files
    robust_file = os.path.join(databank_dir, "robust.json")
    if os.path.exists(robust_file):
        import json
        with open(robust_file, 'r') as f:
            strategies = json.load(f)
            
        print(f"Exporting {len(strategies)} strategies to .set files...")
        
        sets_dir = "generated_sets"
        converter = SetConverter()
        
        for strat in strategies:
            name = strat['id']
            params = strat['params']
            params['score'] = strat['score'] # Add score for comment
            converter.save_set_file(params, name, sets_dir)
            
        print(f"Done. Sets in '{sets_dir}/'")

if __name__ == "__main__":
    main()
