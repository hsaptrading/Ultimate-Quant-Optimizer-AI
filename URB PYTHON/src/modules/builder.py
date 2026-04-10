
import polars as pl
import numpy as np
import json
import os
import time
from tqdm import tqdm
from ..core.backtester import FastBacktester

class StrategyBuilder:
    def __init__(self, m1_data: pl.DataFrame, databank_dir: str):
        self.backtester = FastBacktester(m1_data)
        self.databank_dir = databank_dir
        self.data_len = len(m1_data)
        self.split_idx = int(self.data_len * 0.80)
        
    def generate_random_params(self):
        # Range Start
        r_start_h = np.random.randint(0, 21)
        duration = np.random.randint(1, 9)
        r_end_h = (r_start_h + duration) % 24
        
        # Trading Window
        t_start_h = r_end_h 
        t_start_m = np.random.choice([0, 15, 30, 45])
        win_duration = np.random.randint(1, 13)
        t_end_h = (t_start_h + win_duration) % 24
        
        # Filters (Randomly Enable)
        use_adx = np.random.choice([True, False], p=[0.3, 0.7]) # 30% chance to use
        use_rsi = np.random.choice([True, False], p=[0.2, 0.8])
        
        return {
            'RangeStartHour': int(r_start_h),
            'RangeStartMin': int(np.random.choice([0, 15, 30, 45])),
            'RangeEndHour': int(r_end_h),
            'RangeEndMin': int(np.random.choice([0, 15, 30, 45])),
            
            'TradingStartHour': int(t_start_h),
            'TradingStartMin': int(t_start_m),
            'TradingEndHour': int(t_end_h),
            'TradingEndMin': int(np.random.choice([0, 15, 30, 45])),
            
            'BufferPoints': float(np.random.choice([5, 10, 15, 20, 30])),
            'SLPoints': float(np.random.randint(50, 400)),
            'TPPoints': float(np.random.randint(50, 800)),
            
            # Production Params
            'UseADX': bool(use_adx),
            'AdxThreshold': float(np.random.choice([20, 25, 30])),
            'UseRSI': bool(use_rsi),
            
            # Broker Costs (Simulated)
            'Commission': 3.5, # $3.5 per side ($7 round trip)
            'SwapLong': -1.0,  # Points per day
            'SwapShort': -0.5
        }

    def run_generation(self, iterations=1000):
        print(f"[Builder] Starting PROD generation of {iterations} strategies...")
        
        candidates = []
        
        # Split Data Objects? No, Backtester slice handles logic? 
        # Currently standard Backtester.run runs on WHOLE data.
        # We need to adapt it. 
        # Hack: Pass whole data but ignore OOS in score?
        # Better: Create two tester instances as before.
        
        df_is = self.backtester.data.slice(0, self.split_idx)
        df_oos = self.backtester.data.slice(self.split_idx, self.data_len - self.split_idx)
        
        bt_is = FastBacktester(df_is)
        bt_oos = FastBacktester(df_oos)
        
        for i in tqdm(range(iterations)):
            params = self.generate_random_params()
            
            # 1. IS Backtest
            res_is = bt_is.run(params)
            
            # Tighter Filters for Production
            if res_is['Trades'] > 50 and res_is['NetProfit'] > 0 and res_is['WinRate'] > 35:
                
                # 2. OOS Backtest
                res_oos = bt_oos.run(params)
                
                if res_oos['NetProfit'] > 0:
                    score = res_is['NetProfit'] + res_oos['NetProfit']
                    
                    strategy_record = {
                        'id': f"strat_{int(time.time())}_{i}",
                        'params': params,
                        'metrics_is': res_is,
                        'metrics_oos': res_oos,
                        'score': score
                    }
                    candidates.append(strategy_record)
        
        if candidates:
            candidates.sort(key=lambda x: x['score'], reverse=True)
            output_file = os.path.join(self.databank_dir, f"candidates_prod_{int(time.time())}.json")
            with open(output_file, 'w') as f:
                json.dump(candidates, f, indent=2)
            print(f"[Builder] Saved {len(candidates)} PROD candidates to {output_file}")
        else:
            print("[Builder] No candidates found.")

if __name__ == "__main__":
    pass
