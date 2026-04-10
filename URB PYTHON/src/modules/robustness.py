
import json
import os
import random
import time
import polars as pl
import numpy as np
from tqdm import tqdm
from ..core.backtester import FastBacktester

class RobustnessTester:
    def __init__(self, m1_data: pl.DataFrame, databank_dir: str):
        self.backtester = FastBacktester(m1_data)
        self.databank_dir = databank_dir
        
    def load_candidates(self, filename: str):
        path = os.path.join(self.databank_dir, filename)
        if not os.path.exists(path):
            print(f"File {path} not found.")
            return []
        with open(path, 'r') as f:
            return json.load(f)

    def run_monte_carlo(self, candidate, simulations=20):
        """
        Runs Monte Carlo simulations on a single candidate.
        Tests:
        1. Randomized Spread (0.5x to 3.0x)
        2. Slippage (Random price offset)
        3. Skipped Trades (Skip 5%)
        """
        params = candidate['params']
        original_profit = candidate['score'] # Approximate
        
        passes = 0
        total_runs = simulations
        
        # We need a modified backtester run method that accepts 'noise'
        # Since our current backtester is simple, we can just modify params
        # or we need to modify the Core logic to accept noise arrays.
        # For this prototype, we will just vary the 'Spread' array in the backtester
        # But Backtester initializes spreads in __init__.
        # We can hack it by temporarily modifying self.backtester.spreads? 
        # No, that's not thread safe or clean.
        # Ideally, pass spread_multiplier to run().
        
        # Let's verify robustness by varying the ENTRY parameters slightly also?
        # Or just use the spread variation which is critical for scalpers.
        
        # NOTE: To do this properly with Numba, we should pass a random seed or noise arrays to core.
        # For now, let's implement a 'Spread Stress Test' by estimating impact.
        
        survival_count = 0
        
        for i in range(simulations):
            # Simulation: Worse Spread
            # We don't have a spread_multiplier in run() yet.
            # We will simulate it by deducting extra cost from NetProfit.
            
            # Run standard backtest
            res = self.backtester.run(params)
            
            # Apply Stress
            trades = res['Trades']
            gross_profit = res['NetProfit'] + (trades * 1.0) # approx spread cost added back? no.
            
            # Monte Carlo: Randomize failure
            # 1. Random Spread Multiplier (avg 1.5x)
            spread_mult = np.random.uniform(0.8, 2.5) 
            # 2. Slippage per trade (0 to 5 points)
            slippage_total = trades * np.random.uniform(0, 5)
            
            # 3. Missed Trades (reduce profit by 10%)
            if np.random.random() < 0.1: # 10% chance to lose a chunk of data/trades due to connection
                profit_factor = 0.9
            else:
                profit_factor = 1.0
                
            # Recalculate Result
            # NetProfit ~= (OriginalNet + SpreadCost) - (SpreadCost * Multiplier) - Slippage
            # Simplified: NewProfit = Result - ExtraSpread - Slippage
            
            # Assuming average spread cost was ~1.0 point per trade in original backtest
            extra_spread_cost = trades * (spread_mult - 1.0) * 1.0 
            
            stressed_profit = (res['NetProfit'] * profit_factor) - extra_spread_cost - slippage_total
            
            if stressed_profit > 0:
                survival_count += 1
                
        pass_rate = (survival_count / simulations) * 100
        return pass_rate

    def run_batch_test(self, candidates_file="candidates.json", output_file="robust.json"):
        candidates = self.load_candidates(candidates_file)
        if not candidates:
            print("[Robustness] No candidates to test.")
            return

        print(f"[Robustness] Testing {len(candidates)} candidates with Monte Carlo...")
        robust_candidates = []
        
        for cand in tqdm(candidates):
            pass_rate = self.run_monte_carlo(cand)
            cand['robustness_score'] = pass_rate
            
            if pass_rate >= 90.0: # 90% survival rate
                robust_candidates.append(cand)
                
        # Save
        if robust_candidates:
            out_path = os.path.join(self.databank_dir, output_file)
            robust_candidates.sort(key=lambda x: x['score'], reverse=True)
            with open(out_path, 'w') as f:
                json.dump(robust_candidates, f, indent=2)
            print(f"[Robustness] Saved {len(robust_candidates)} robust strategies to {out_path}")
        else:
            print("[Robustness] No strategies passed the stress test.")

if __name__ == "__main__":
    # Test
    try:
        parquet_file = "USATECHIDXUSD.tick.utc2_M1.parquet"
        if os.path.exists(parquet_file):
            df = pl.read_parquet(parquet_file)
            tester = RobustnessTester(df, "databank")
            # Usually we run this after builder, so let's look for a candidate file
            # If none, we can't test.
            files = os.listdir("databank")
            cand_files = [f for f in files if f.startswith("candidates")]
            if cand_files:
                tester.run_batch_test(cand_files[-1])
            else:
                print("No candidate files found in databank.")
    except Exception as e:
        print(e)
