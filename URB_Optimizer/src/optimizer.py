"""
Optimizer Module

Parallel parameter optimization using:
- Grid Search
- Random Search
- In-Sample / Out-of-Sample splitting
"""

import pandas as pd
import numpy as np
from typing import List, Dict, Tuple, Callable
from dataclasses import dataclass
from datetime import datetime
from itertools import product
import multiprocessing as mp
from joblib import Parallel, delayed
from tqdm import tqdm
import sys
from pathlib import Path

sys.path.append(str(Path(__file__).parent.parent))
from config.broker_config import DEFAULT_PARAMS, FTMO_US100, FTMO_ACCOUNT
from config.param_space import PARAM_SPACE, PARAM_SPACE_REDUCED
from src.range_breaker import generate_signals, calculate_sl_tp
from src.backtester import Backtester, BacktestResult, print_backtest_summary


@dataclass
class OptimizationResult:
    """Results of a single parameter combination."""
    params: dict
    in_sample: BacktestResult
    out_of_sample: BacktestResult = None
    combined_score: float = 0




def generate_param_combinations(param_space: dict, 
                                 method: str = 'grid',
                                 n_random: int = 1000) -> List[dict]:
    """
    Generate parameter combinations for optimization.
    
    Args:
        param_space: Dictionary of parameter names to list of values
        method: 'grid' for full grid, 'random' for random sampling
        n_random: Number of random combinations if method='random'
        
    Returns:
        List of parameter dictionaries
    """
    if method == 'grid':
        keys = list(param_space.keys())
        values = list(param_space.values())
        
        combinations = []
        for combo in product(*values):
            params = DEFAULT_PARAMS.copy()
            params.update(dict(zip(keys, combo)))
            combinations.append(params)
        
        return combinations
    
    elif method == 'random':
        combinations = []
        for _ in range(n_random):
            params = DEFAULT_PARAMS.copy()
            for key, values in param_space.items():
                params[key] = np.random.choice(values)
            combinations.append(params)
        
        return combinations
    
    else:
        raise ValueError(f"Unknown method: {method}")


def split_data(m15_data: pd.DataFrame, 
               train_ratio: float = 0.8) -> Tuple[pd.DataFrame, pd.DataFrame]:
    """
    Split data into in-sample (training) and out-of-sample (testing) sets.
    
    Args:
        m15_data: Full M15 DataFrame
        train_ratio: Ratio of data for training (0.8 = 80%)
        
    Returns:
        Tuple of (in_sample_df, out_of_sample_df)
    """
    split_idx = int(len(m15_data) * train_ratio)
    
    in_sample = m15_data.iloc[:split_idx].copy().reset_index(drop=True)
    out_of_sample = m15_data.iloc[split_idx:].copy().reset_index(drop=True)
    
    return in_sample, out_of_sample


def run_single_backtest(params: dict, 
                        m15_data: pd.DataFrame,
                        backtester: Backtester) -> BacktestResult:
    """
    Run a single backtest with given parameters.
    
    Args:
        params: Strategy parameters
        m15_data: M15 bar data
        backtester: Backtester instance
        
    Returns:
        BacktestResult
    """
    # Generate signals with these params
    signals = generate_signals(m15_data, params)
    signals = calculate_sl_tp(signals, params)
    
    # Run backtest
    result = backtester.run(signals, m15_data, params)
    
    return result


def calculate_score(result: BacktestResult,
                    min_trades: int = 10,
                    max_drawdown_pct: float = 15.0) -> float:
    """
    Calculate optimization score for ranking results.
    
    Score considers:
    - Profit factor
    - Win rate
    - Number of trades (statistical significance)
    - Drawdown (penalty)
    
    Args:
        result: BacktestResult
        min_trades: Minimum trades for valid result (reduced for shorter data)
        max_drawdown_pct: Maximum allowed drawdown
        
    Returns:
        Score (higher is better), 0 if fails filters
    """
    # Filter out invalid results
    if result.total_trades < min_trades:
        return 0
    
    if result.max_drawdown_pct > max_drawdown_pct:
        return 0
    
    # Allow profit factor >= 0.8 (slightly losing strategies can still be optimized)
    if result.profit_factor < 0.8:
        return 0
    
    # Calculate composite score
    # Weight: Profit Factor (40%), Win Rate (20%), Sharpe (30%), DD penalty (10%)
    
    pf_score = min(result.profit_factor, 3.0) / 3.0  # Cap at 3.0
    wr_score = result.win_rate
    sharpe_score = min(max(result.sharpe_ratio, 0), 3.0) / 3.0  # Cap at 3.0
    dd_penalty = 1.0 - (result.max_drawdown_pct / max_drawdown_pct)
    
    score = (
        0.40 * pf_score +
        0.20 * wr_score +
        0.30 * sharpe_score +
        0.10 * dd_penalty
    )
    
    # Bonus for more trades (statistical reliability)
    trade_bonus = min(result.total_trades / 50, 1.0) * 0.1
    
    return score + trade_bonus


def optimize_worker(args: Tuple) -> OptimizationResult:
    """
    Worker function for parallel optimization.
    
    Args:
        args: Tuple of (params, in_sample_data, out_sample_data, symbol_config, account_config)
        
    Returns:
        OptimizationResult
    """
    params, in_sample, out_sample, symbol_config, account_config = args
    
    backtester = Backtester(symbol_config, account_config)
    
    # In-sample backtest
    is_result = run_single_backtest(params, in_sample, backtester)
    
    # Out-of-sample backtest (if provided)
    oos_result = None
    if out_sample is not None and len(out_sample) > 0:
        oos_result = run_single_backtest(params, out_sample, backtester)
    
    # Calculate combined score
    is_score = calculate_score(is_result)
    oos_score = calculate_score(oos_result) if oos_result else 0
    
    # Combined score weights IS more if no OOS, otherwise balanced
    if oos_score > 0:
        combined = 0.5 * is_score + 0.5 * oos_score
    else:
        combined = is_score * 0.8  # Penalty for no OOS validation
    
    return OptimizationResult(
        params=params,
        in_sample=is_result,
        out_of_sample=oos_result,
        combined_score=combined
    )


class Optimizer:
    """
    Main optimization engine.
    """
    
    def __init__(self,
                 m15_data: pd.DataFrame,
                 param_space: dict = None,
                 train_ratio: float = 0.8,
                 symbol_config: dict = None,
                 account_config: dict = None,
                 n_jobs: int = -1):
        """
        Initialize optimizer.
        
        Args:
            m15_data: Full M15 data
            param_space: Parameter space to search (default: PARAM_SPACE)
            train_ratio: In-sample ratio (default: 0.8 = 80%)
            symbol_config: Broker symbol config
            account_config: Account settings
            n_jobs: Number of parallel jobs (-1 = all cores)
        """
        self.m15_data = m15_data
        self.param_space = param_space or PARAM_SPACE
        self.train_ratio = train_ratio
        self.symbol_config = symbol_config or FTMO_US100
        self.account_config = account_config or FTMO_ACCOUNT
        self.n_jobs = n_jobs if n_jobs > 0 else mp.cpu_count()
        
        # Split data
        self.in_sample, self.out_of_sample = split_data(m15_data, train_ratio)
        
        print(f"Data split: {len(self.in_sample):,} IS bars, {len(self.out_of_sample):,} OOS bars")
        print(f"IS period: {self.in_sample['datetime'].min()} to {self.in_sample['datetime'].max()}")
        print(f"OOS period: {self.out_of_sample['datetime'].min()} to {self.out_of_sample['datetime'].max()}")
    
    def run(self,
            method: str = 'random',
            n_combinations: int = 1000,
            top_n: int = 50) -> List[OptimizationResult]:
        """
        Run optimization.
        
        Args:
            method: 'grid' or 'random'
            n_combinations: Number of combinations for random search
            top_n: Number of top results to return
            
        Returns:
            List of top OptimizationResults sorted by score
        """
        # Generate parameter combinations
        print(f"\nGenerating parameter combinations ({method})...")
        
        if method == 'grid':
            combinations = generate_param_combinations(self.param_space, 'grid')
            print(f"Total grid combinations: {len(combinations):,}")
        else:
            combinations = generate_param_combinations(self.param_space, 'random', n_combinations)
            print(f"Random combinations: {len(combinations):,}")
        
        # Prepare worker arguments
        args_list = [
            (params, self.in_sample, self.out_of_sample, self.symbol_config, self.account_config)
            for params in combinations
        ]
        
        # Run parallel optimization
        print(f"\nRunning optimization on {self.n_jobs} cores...")
        
        results = Parallel(n_jobs=self.n_jobs, verbose=10)(
            delayed(optimize_worker)(args) for args in tqdm(args_list, desc="Optimizing")
        )
        
        # Filter and sort results
        valid_results = [r for r in results if r.combined_score > 0]
        valid_results.sort(key=lambda x: x.combined_score, reverse=True)
        
        print(f"\nOptimization complete!")
        print(f"Total combinations tested: {len(results)}")
        print(f"Valid results (passed filters): {len(valid_results)}")
        
        return valid_results[:top_n]
    
    def print_top_results(self, results: List[OptimizationResult], n: int = 10):
        """Print summary of top results."""
        print("\n" + "="*80)
        print(f"TOP {min(n, len(results))} OPTIMIZATION RESULTS")
        print("="*80)
        
        for i, r in enumerate(results[:n]):
            print(f"\n--- #{i+1} (Score: {r.combined_score:.4f}) ---")
            print(f"IS Trades: {r.in_sample.total_trades}, PF: {r.in_sample.profit_factor:.2f}, "
                  f"WR: {r.in_sample.win_rate:.1%}, DD: {r.in_sample.max_drawdown_pct:.1f}%")
            
            if r.out_of_sample:
                print(f"OOS Trades: {r.out_of_sample.total_trades}, PF: {r.out_of_sample.profit_factor:.2f}, "
                      f"WR: {r.out_of_sample.win_rate:.1%}, DD: {r.out_of_sample.max_drawdown_pct:.1f}%")
            
            # Print key params that differ from default
            key_params = ['risk_percent', 'sl_method', 'sl_range_multiplier', 
                          'tp_risk_reward', 'use_trailing_stop', 'trailing_start_points']
            param_str = ", ".join([f"{k}={r.params.get(k)}" for k in key_params])
            print(f"Params: {param_str}")
    
    def export_results(self, 
                       results: List[OptimizationResult], 
                       filepath: str):
        """Export results to CSV."""
        rows = []
        for r in results:
            row = {
                'score': r.combined_score,
                'is_trades': r.in_sample.total_trades,
                'is_pf': r.in_sample.profit_factor,
                'is_wr': r.in_sample.win_rate,
                'is_dd_pct': r.in_sample.max_drawdown_pct,
                'is_sharpe': r.in_sample.sharpe_ratio,
                'is_net_profit': r.in_sample.net_profit
            }
            
            if r.out_of_sample:
                row.update({
                    'oos_trades': r.out_of_sample.total_trades,
                    'oos_pf': r.out_of_sample.profit_factor,
                    'oos_wr': r.out_of_sample.win_rate,
                    'oos_dd_pct': r.out_of_sample.max_drawdown_pct,
                    'oos_net_profit': r.out_of_sample.net_profit
                })
            
            row.update(r.params)
            rows.append(row)
        
        df = pd.DataFrame(rows)
        df.to_csv(filepath, index=False)
        print(f"Results exported to: {filepath}")


# Quick test
if __name__ == "__main__":
    print("Optimizer module loaded successfully!")
    print(f"Default parameter space has {len(PARAM_SPACE)} parameters")
    print(f"CPU cores available: {mp.cpu_count()}")
    
    # Example of generating combinations
    combos = generate_param_combinations({'risk_percent': [1, 2], 'sl_method': ['fixed', 'range_based']}, 'grid')
    print(f"\nExample grid combinations: {len(combos)}")
    for c in combos[:3]:
        print(f"  {c['risk_percent']}, {c['sl_method']}")
