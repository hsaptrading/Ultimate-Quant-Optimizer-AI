
import polars as pl
import numpy as np
from src.core.backtester import FastBacktester

def debug():
    print("Loading data...")
    df = pl.read_parquet("USATECHIDXUSD.tick.utc2_M1.parquet").slice(0, 100000)
    
    tester = FastBacktester(df)
    
    # Check that indicators were calc
    print(f"ADX Sample: {tester.adx_14[100:110]}")
    print(f"RSI Sample: {tester.rsi_14[100:110]}")
    
    # Valid Params
    params = {
        'RangeStartHour': 14, 'RangeStartMin': 0,
        'RangeEndHour': 16, 'RangeEndMin': 0, 
        'TradingStartHour': 16, 'TradingStartMin': 30,
        'TradingEndHour': 22, 'TradingEndMin': 0,
        'BufferPoints': 10.0,
        'SLPoints': 50.0,
        'TPPoints': 100.0,
        
        # Production Params
        'UseADX': True,
        'AdxThreshold': 20.0,
        'UseRSI': False,
        'Commission': 3.5,
        'SwapLong': -1.0,
        'SwapShort': -0.5
    }
    
    print("Running Production Backtest...")
    result = tester.run(params)
    print(result)

if __name__ == "__main__":
    debug()
