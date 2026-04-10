
import polars as pl
import os
import sys
from src.loader import DataLoader
from src.modules.builder import StrategyBuilder

def main():
    print("=== URB Strategy Factory (Python) ===")
    
    # 1. Load Data
    csv_file = "USATECHIDXUSD.tick.utc2.csv"
    if not os.path.exists(csv_file):
        print(f"Error: Data file {csv_file} not found.")
        return

    loader = DataLoader(csv_file)
    try:
        # force_rebuild=False will load existing parquet if available
        m1_data = loader.convert_ticks_to_m1()
    except Exception as e:
        print(f"Error loading data: {e}")
        return

    print(f"Data Loaded: {len(m1_data)} bars. Range: {m1_data['time'].min()} to {m1_data['time'].max()}")

    # 2. Initialize Builder
    databank_dir = "databank"
    if not os.path.exists(databank_dir):
        os.makedirs(databank_dir)
        
    builder = StrategyBuilder(m1_data, databank_dir)
    
    # 3. Run Generation
    # User asked for "various 20, 50, 100 or more" strategies.
    # We need to run enough iterations to find them.
    # Random search efficiency is low (~1-5% success rate for strict criteria is common).
    # Let's try 5000 iterations to start.
    
    iterations = 5000
    print(f"Starting generation of {iterations} random strategies...")
    builder.run_generation(iterations)
    
    print("=== Generation Complete ===")

if __name__ == "__main__":
    main()
