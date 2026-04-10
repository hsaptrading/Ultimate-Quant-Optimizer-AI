"""
Stress Testing Module

Implements robustness tests:
- Monte Carlo simulation (trade shuffling)
- Parameter sensitivity analysis
- Drawdown probability estimation
"""

import pandas as pd
import numpy as np
from typing import List, Dict, Tuple
from dataclasses import dataclass
import sys
from pathlib import Path
from tqdm import tqdm

sys.path.append(str(Path(__file__).parent.parent))
from src.backtester import BacktestResult, Trade


@dataclass
class MonteCarloResult:
    """Results of Monte Carlo simulation."""
    n_simulations: int
    original_profit: float
    original_drawdown: float
    
    # Profit distribution
    profit_mean: float
    profit_std: float
    profit_5th: float  # 5th percentile (worst case)
    profit_95th: float  # 95th percentile (best case)
    profit_positive_pct: float  # % of simulations profitable
    
    # Drawdown distribution
    drawdown_mean: float
    drawdown_std: float
    drawdown_95th: float  # 95th percentile (worst case)
    
    # Ruin probability
    ruin_probability: float  # % of simulations hitting max DD


@dataclass
class SensitivityResult:
    """Results of parameter sensitivity analysis."""
    base_score: float
    param_name: str
    variations: List[dict]  # List of {value, score, pct_change}
    is_stable: bool  # True if no variation causes >30% score drop


def monte_carlo_simulation(trades: List[Trade],
                           initial_balance: float = 100000,
                           n_simulations: int = 1000,
                           max_dd_pct: float = 10.0) -> MonteCarloResult:
    """
    Run Monte Carlo simulation by shuffling trade order.
    
    This tests if the strategy is robust or if results depend on
    specific trade sequence (curve-fitting red flag).
    
    Args:
        trades: List of Trade objects from backtest
        initial_balance: Starting balance
        n_simulations: Number of random shuffles
        max_dd_pct: Maximum drawdown considered as "ruin"
        
    Returns:
        MonteCarloResult with distribution statistics
    """
    if not trades:
        return MonteCarloResult(
            n_simulations=0, original_profit=0, original_drawdown=0,
            profit_mean=0, profit_std=0, profit_5th=0, profit_95th=0,
            profit_positive_pct=0, drawdown_mean=0, drawdown_std=0,
            drawdown_95th=0, ruin_probability=0
        )
    
    # Extract trade P&L
    trade_profits = [t.net_profit for t in trades]
    original_profit = sum(trade_profits)
    
    # Calculate original drawdown
    equity = initial_balance
    peak = initial_balance
    max_dd = 0
    for p in trade_profits:
        equity += p
        if equity > peak:
            peak = equity
        dd = (peak - equity) / peak * 100
        max_dd = max(max_dd, dd)
    original_drawdown = max_dd
    
    # Run simulations
    profits = []
    drawdowns = []
    ruin_count = 0
    
    for _ in tqdm(range(n_simulations), desc="Monte Carlo"):
        # Shuffle trade order
        shuffled = trade_profits.copy()
        np.random.shuffle(shuffled)
        
        # Calculate equity curve
        equity = initial_balance
        peak = initial_balance
        sim_max_dd = 0
        
        for p in shuffled:
            equity += p
            if equity > peak:
                peak = equity
            dd_pct = (peak - equity) / peak * 100
            sim_max_dd = max(sim_max_dd, dd_pct)
        
        final_profit = equity - initial_balance
        profits.append(final_profit)
        drawdowns.append(sim_max_dd)
        
        if sim_max_dd >= max_dd_pct:
            ruin_count += 1
    
    profits = np.array(profits)
    drawdowns = np.array(drawdowns)
    
    return MonteCarloResult(
        n_simulations=n_simulations,
        original_profit=original_profit,
        original_drawdown=original_drawdown,
        profit_mean=np.mean(profits),
        profit_std=np.std(profits),
        profit_5th=np.percentile(profits, 5),
        profit_95th=np.percentile(profits, 95),
        profit_positive_pct=(profits > 0).mean() * 100,
        drawdown_mean=np.mean(drawdowns),
        drawdown_std=np.std(drawdowns),
        drawdown_95th=np.percentile(drawdowns, 95),
        ruin_probability=(ruin_count / n_simulations) * 100
    )


def parameter_sensitivity(base_params: dict,
                          param_name: str,
                          test_values: List,
                          run_backtest_func,
                          m15_data: pd.DataFrame,
                          backtester) -> SensitivityResult:
    """
    Test how sensitive the strategy is to a single parameter.
    
    Args:
        base_params: Original optimized parameters
        param_name: Name of parameter to vary
        test_values: List of values to test
        run_backtest_func: Function to run backtest with params
        m15_data: M15 data
        backtester: Backtester instance
        
    Returns:
        SensitivityResult
    """
    from src.optimizer import calculate_score
    
    # Base score
    base_result = run_backtest_func(base_params, m15_data, backtester)
    base_score = calculate_score(base_result)
    
    variations = []
    
    for value in test_values:
        test_params = base_params.copy()
        test_params[param_name] = value
        
        result = run_backtest_func(test_params, m15_data, backtester)
        score = calculate_score(result)
        
        pct_change = ((score - base_score) / base_score * 100) if base_score > 0 else 0
        
        variations.append({
            'value': value,
            'score': score,
            'pct_change': pct_change,
            'trades': result.total_trades,
            'pf': result.profit_factor
        })
    
    # Check stability (no variation causes >30% drop)
    min_change = min(v['pct_change'] for v in variations)
    is_stable = min_change >= -30
    
    return SensitivityResult(
        base_score=base_score,
        param_name=param_name,
        variations=variations,
        is_stable=is_stable
    )


def full_sensitivity_analysis(base_params: dict,
                               run_backtest_func,
                               m15_data: pd.DataFrame,
                               backtester) -> Dict[str, SensitivityResult]:
    """
    Run sensitivity analysis on key parameters.
    
    Args:
        base_params: Optimized parameters
        run_backtest_func: Function to run backtest
        m15_data: M15 data
        backtester: Backtester instance
        
    Returns:
        Dictionary of parameter name to SensitivityResult
    """
    # Define test variations for each key parameter
    param_tests = {
        'risk_percent': [0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
        'sl_range_multiplier': [0.6, 0.8, 1.0, 1.2, 1.4, 1.6],
        'tp_risk_reward': [1.0, 1.5, 2.0, 2.5, 3.0, 3.5],
        'trailing_start_points': [2000, 3000, 4000, 5000, 6000, 7000],
        'range_buffer_points': [20, 30, 50, 75, 100, 150],
    }
    
    results = {}
    
    for param_name, test_values in param_tests.items():
        print(f"Testing sensitivity: {param_name}...")
        result = parameter_sensitivity(
            base_params, param_name, test_values,
            run_backtest_func, m15_data, backtester
        )
        results[param_name] = result
    
    return results


def print_monte_carlo_summary(mc_result: MonteCarloResult):
    """Print formatted Monte Carlo results."""
    print("\n" + "="*60)
    print("MONTE CARLO SIMULATION RESULTS")
    print(f"({mc_result.n_simulations:,} simulations)")
    print("="*60)
    
    print(f"\n--- Profit Distribution ---")
    print(f"Original Profit:    ${mc_result.original_profit:,.2f}")
    print(f"Mean Profit:        ${mc_result.profit_mean:,.2f}")
    print(f"Std Dev:            ${mc_result.profit_std:,.2f}")
    print(f"5th Percentile:     ${mc_result.profit_5th:,.2f} (worst case)")
    print(f"95th Percentile:    ${mc_result.profit_95th:,.2f} (best case)")
    print(f"% Profitable:       {mc_result.profit_positive_pct:.1f}%")
    
    print(f"\n--- Drawdown Distribution ---")
    print(f"Original Drawdown:  {mc_result.original_drawdown:.1f}%")
    print(f"Mean Drawdown:      {mc_result.drawdown_mean:.1f}%")
    print(f"95th Percentile:    {mc_result.drawdown_95th:.1f}% (worst case)")
    
    print(f"\n--- Risk Assessment ---")
    print(f"Ruin Probability:   {mc_result.ruin_probability:.1f}%")
    
    # Traffic light assessment
    if mc_result.ruin_probability < 5 and mc_result.profit_positive_pct > 90:
        assessment = "🟢 EXCELLENT - Low risk, highly consistent"
    elif mc_result.ruin_probability < 15 and mc_result.profit_positive_pct > 75:
        assessment = "🟡 GOOD - Acceptable risk, mostly consistent"
    elif mc_result.ruin_probability < 25:
        assessment = "🟠 CAUTION - Moderate risk, needs monitoring"
    else:
        assessment = "🔴 HIGH RISK - May need parameter adjustment"
    
    print(f"\nOverall: {assessment}")
    print("="*60)


def print_sensitivity_summary(sensitivity_results: Dict[str, SensitivityResult]):
    """Print formatted sensitivity analysis results."""
    print("\n" + "="*60)
    print("PARAMETER SENSITIVITY ANALYSIS")
    print("="*60)
    
    stable_params = []
    unstable_params = []
    
    for param_name, result in sensitivity_results.items():
        status = "✅ STABLE" if result.is_stable else "⚠️ SENSITIVE"
        
        print(f"\n{param_name}: {status}")
        print(f"  Base Score: {result.base_score:.4f}")
        
        for v in result.variations:
            indicator = "  " if abs(v['pct_change']) < 20 else "→ "
            print(f"  {indicator}Value={v['value']}: Score={v['score']:.4f} ({v['pct_change']:+.1f}%)")
        
        if result.is_stable:
            stable_params.append(param_name)
        else:
            unstable_params.append(param_name)
    
    print("\n" + "-"*40)
    print(f"Stable parameters ({len(stable_params)}): {', '.join(stable_params)}")
    print(f"Sensitive parameters ({len(unstable_params)}): {', '.join(unstable_params)}")
    print("="*60)


class StressTester:
    """
    Combined stress testing suite.
    """
    
    def __init__(self, 
                 trades: List[Trade],
                 initial_balance: float = 100000,
                 max_dd_threshold: float = 10.0):
        """
        Initialize stress tester.
        
        Args:
            trades: List of trades from backtest
            initial_balance: Starting balance
            max_dd_threshold: Max DD for FTMO (10%)
        """
        self.trades = trades
        self.initial_balance = initial_balance
        self.max_dd = max_dd_threshold
    
    def run_monte_carlo(self, n_simulations: int = 1000) -> MonteCarloResult:
        """Run Monte Carlo simulation."""
        return monte_carlo_simulation(
            self.trades, 
            self.initial_balance, 
            n_simulations, 
            self.max_dd
        )
    
    def passes_stress_test(self, 
                           mc_result: MonteCarloResult,
                           min_profit_positive_pct: float = 80,
                           max_ruin_probability: float = 15) -> bool:
        """
        Check if strategy passes stress test criteria.
        
        Args:
            mc_result: Monte Carlo result
            min_profit_positive_pct: Minimum % of profitable simulations
            max_ruin_probability: Maximum acceptable ruin probability
            
        Returns:
            True if passes all criteria
        """
        criteria = [
            mc_result.profit_positive_pct >= min_profit_positive_pct,
            mc_result.ruin_probability <= max_ruin_probability,
            mc_result.profit_5th > 0,  # Even worst case should be profitable
        ]
        
        return all(criteria)


# Test
if __name__ == "__main__":
    print("Stress Testing module loaded successfully!")
    
    # Create sample trades for testing
    sample_trades = []
    for i in range(50):
        t = Trade(
            entry_bar=i*10,
            entry_time=pd.Timestamp('2024-01-01') + pd.Timedelta(days=i),
            entry_price=21000 + i*10,
            direction=1,
            lot_size=0.1,
            sl_price=20950,
            tp_price=21100,
            exit_bar=i*10+5,
            exit_time=pd.Timestamp('2024-01-01') + pd.Timedelta(days=i, hours=4),
            exit_price=21050 if np.random.random() > 0.4 else 20970,
            exit_reason='tp' if np.random.random() > 0.4 else 'sl'
        )
        t.net_profit = (t.exit_price - t.entry_price) * t.lot_size * 1
        sample_trades.append(t)
    
    print(f"\nTesting with {len(sample_trades)} sample trades...")
    
    tester = StressTester(sample_trades, 100000, 10.0)
    mc_result = tester.run_monte_carlo(100)
    print_monte_carlo_summary(mc_result)
    
    passed = tester.passes_stress_test(mc_result)
    print(f"\nPasses stress test: {'YES ✅' if passed else 'NO ❌'}")
