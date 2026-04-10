"""
URB Optimizer v2.0 - Multi-Timeframe Engine

This script demonstrates the upgraded workflow:
1. Load M1 Data (Generic from CSV)
2. Resample M1 -> Target Timeframe (e.g., H4)
3. Generate Signals on Target Timeframe
4. Simulate Execution on M1 (High Precision)
"""

import sys
from pathlib import Path
import pandas as pd
from datetime import datetime

# Setup Paths
PROJECT_ROOT = Path(__file__).parent
sys.path.insert(0, str(PROJECT_ROOT))

# Import New Modules
from src.data_loader_m1 import load_m1_data, resample_m1_to_tf
from src.backtester_m1 import BacktesterM1

# Config
DATA_FILE = "data/EURUSD_M1_2024.csv" # Example filename
TARGET_TIMEFRAME = "4h"  # '15min', '1h', '4h', '1d'

def main():
    print(f"--- URB Optimizer v2.0 (M1 Precision Engine) ---")
    
    # 1. Check Data
    csv_path = PROJECT_ROOT / DATA_FILE
    if not csv_path.exists():
        print(f"Error: Data file not found at {csv_path}")
        print("Please place an M1 CSV file in the 'data' folder.")
        # Create Dummy Data for demonstration if file missing?
        # No, let's ask user for real data.
        return

    # 2. Load M1 Data
    try:
        m1_df = load_m1_data(str(csv_path), use_cache=True)
        print(f"✓ Loaded {len(m1_df):,} M1 bars.")
    except Exception as e:
        print(f"Failed to load data: {e}")
        return

    # 3. Resample to Strategy Timeframe
    print(f"Resampling M1 to {TARGET_TIMEFRAME}...")
    strategy_df = resample_m1_to_tf(m1_df, TARGET_TIMEFRAME)
    print(f"✓ Created {len(strategy_df):,} {TARGET_TIMEFRAME} bars.")

    # 4. Generate Signals (Placeholder for your strategy logic)
    print("Generating Signals on Strategy Timeframe...")
    # Here you would call your strategy logic:
    # signals = generate_signals(strategy_df)
    
    # Mock Signals for testing the engine: Buy every time RSI < 30 (simple example)
    strategy_df['signal'] = 0
    # Add random signals just to test the backtester loop
    import numpy as np
    strategy_df['signal'] = np.random.choice([0, 1, -1], size=len(strategy_df), p=[0.95, 0.025, 0.025])
    
    # Add Dummy SL/TP prices
    strategy_df['sl_price'] = strategy_df['close'] - (0.0050 * strategy_df['signal']) # 50 pips SL
    strategy_df['tp_price'] = strategy_df['close'] + (0.0100 * strategy_df['signal']) # 100 pips TP
    
    # Filter only active signals
    active_signals = strategy_df[strategy_df['signal'] != 0].copy()
    print(f"-> Generated {len(active_signals)} test signals.")

    # 5. Run Precision Backtest
    print("Running M1 Execution Simulation...")
    
    # Broker Config (Simple)
    symbol_conf = {'spread': 10, 'point_size': 0.00001, 'value_per_point': 1, 'contract_size': 100000}
    account_conf = {'balance': 10000}
    
    backtester = BacktesterM1(symbol_conf, account_conf)
    
    results = backtester.run(
        signals=active_signals,
        signal_tf_data=strategy_df,
        m1_data=m1_df,
        params={'risk_percent': 1.0}
    )
    
    # 6. Report
    print("\n--- Backtest Results ---")
    print(f"Total Trades: {results['total_trades']}")
    print(f"Final Equity: ${results['final_equity']:,.2f}")
    if results['trades']:
        df_trades = pd.DataFrame(results['trades'])
        print(f"Win Rate: {(df_trades['net_profit'] > 0).mean():.1%}")
        print(f"Avg Profit: ${df_trades['net_profit'].mean():.2f}")

if __name__ == "__main__":
    main()
