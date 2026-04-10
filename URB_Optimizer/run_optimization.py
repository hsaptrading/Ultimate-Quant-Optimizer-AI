"""
URB Optimizer - Main Entry Point (Enhanced with Full Reporting)

Run the complete optimization pipeline:
1. Load tick data and convert to M15
2. Run parameter optimization (Grid/Random)
3. Apply stress tests (Monte Carlo)
4. Export results, reports, and .set files
"""

import sys
import os
from pathlib import Path
from datetime import datetime
import json
import traceback

# Add project root to path
PROJECT_ROOT = Path(__file__).parent
sys.path.insert(0, str(PROJECT_ROOT))

# Ensure all folders exist
(PROJECT_ROOT / "data").mkdir(exist_ok=True)
(PROJECT_ROOT / "reports").mkdir(exist_ok=True)
(PROJECT_ROOT / "databank").mkdir(exist_ok=True)
(PROJECT_ROOT / "output").mkdir(exist_ok=True)


def log_print(msg: str, log_file=None):
    """Print and optionally log to file."""
    print(msg)
    if log_file:
        log_file.write(msg + "\n")
        log_file.flush()


def main():
    """Main optimization pipeline with full reporting."""
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    
    # Open log file
    log_path = PROJECT_ROOT / "reports" / f"optimization_log_{timestamp}.txt"
    log_file = open(log_path, 'w', encoding='utf-8')
    
    try:
        log_print("="*70, log_file)
        log_print("  URB OPTIMIZER - Ultimate Range Breaker Optimization System", log_file)
        log_print("="*70, log_file)
        log_print(f"\nStarted: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}", log_file)
        log_print(f"Log file: {log_path}", log_file)
        
        # Import modules (after path setup)
        log_print("\n[INFO] Loading modules...", log_file)
        
        try:
            from config.broker_config import FTMO_US100, FTMO_ACCOUNT, DEFAULT_PARAMS
            log_print("  ✓ broker_config loaded", log_file)
        except Exception as e:
            log_print(f"  ✗ ERROR loading broker_config: {e}", log_file)
            raise
        
        try:
            from src.data_loader import load_tick_data, create_m15_data, get_data_info
            log_print("  ✓ data_loader loaded", log_file)
        except Exception as e:
            log_print(f"  ✗ ERROR loading data_loader: {e}", log_file)
            raise
        
        try:
            from src.range_breaker import generate_signals, calculate_sl_tp
            log_print("  ✓ range_breaker loaded", log_file)
        except Exception as e:
            log_print(f"  ✗ ERROR loading range_breaker: {e}", log_file)
            raise
        
        try:
            from src.backtester import Backtester, print_backtest_summary
            log_print("  ✓ backtester loaded", log_file)
        except Exception as e:
            log_print(f"  ✗ ERROR loading backtester: {e}", log_file)
            raise
        
        try:
            from src.optimizer import Optimizer, PARAM_SPACE, PARAM_SPACE_REDUCED, run_single_backtest
            log_print("  ✓ optimizer loaded", log_file)
        except Exception as e:
            log_print(f"  ✗ ERROR loading optimizer: {e}", log_file)
            raise
        
        try:
            from src.stress_tests import StressTester, print_monte_carlo_summary
            log_print("  ✓ stress_tests loaded", log_file)
        except Exception as e:
            log_print(f"  ✗ ERROR loading stress_tests: {e}", log_file)
            raise
        
        log_print("\n[INFO] All modules loaded successfully!", log_file)
        
        # ========== CONFIGURATION ==========
        
        log_print("\n" + "="*50, log_file)
        log_print("CONFIGURATION", log_file)
        log_print("="*50, log_file)
        
        # Find tick data file
        DATA_DIR = PROJECT_ROOT / "data"
        tick_files = list(DATA_DIR.glob("*.csv"))
        
        log_print(f"\nData directory: {DATA_DIR}", log_file)
        log_print(f"CSV files found: {len(tick_files)}", log_file)
        
        if not tick_files:
            log_print("\n⚠️ ERROR: No tick data CSV files found in 'data' folder!", log_file)
            log_print("\nPlease place your tick data file in:", log_file)
            log_print(f"  {DATA_DIR}", log_file)
            log_print("\nExpected format: DateTime,Bid,Ask,Volume", log_file)
            log_print("Example: 20250623 01:08:47.793,21510.9,21512.6,1", log_file)
            
            # Run module tests instead
            log_print("\n" + "="*50, log_file)
            log_print("Running module tests with synthetic data...", log_file)
            log_print("="*50, log_file)
            run_module_tests(log_file)
            return
        
        # Use first CSV file found
        TICK_FILE = tick_files[0]
        log_print(f"\nUsing tick data: {TICK_FILE.name}", log_file)
        
        # Optimization settings
        OPTIMIZATION_METHOD = "random"  # "grid" or "random"
        N_COMBINATIONS = 200            # Start with fewer for testing
        TOP_N_RESULTS = 30              # Keep top N results
        TRAIN_RATIO = 0.80              # 80% in-sample, 20% out-of-sample
        
        # Date range
        START_DATE = None  # Use all data
        END_DATE = None    # Use all data
        
        # Monte Carlo settings
        MC_SIMULATIONS = 500  # Reduced for faster testing
        
        log_print(f"\nOptimization method: {OPTIMIZATION_METHOD}", log_file)
        log_print(f"Combinations to test: {N_COMBINATIONS}", log_file)
        log_print(f"Top results to keep: {TOP_N_RESULTS}", log_file)
        log_print(f"Train/Test split: {TRAIN_RATIO*100:.0f}% / {(1-TRAIN_RATIO)*100:.0f}%", log_file)
        log_print(f"Monte Carlo simulations: {MC_SIMULATIONS}", log_file)
        
        # ========== STEP 1: LOAD DATA ==========
        
        log_print("\n" + "="*50, log_file)
        log_print("STEP 1: Loading Data", log_file)
        log_print("="*50, log_file)
        
        # Get file info
        try:
            info = get_data_info(str(TICK_FILE))
            log_print(f"\nFile: {TICK_FILE.name}", log_file)
            log_print(f"Size: {info['file_size_mb']:.1f} MB", log_file)
            log_print(f"Total ticks: {info['total_ticks']:,}", log_file)
            log_print(f"Date range: {info['first_date']} to {info['last_date']}", log_file)
            log_print(f"Days of data: {info['date_range_days']}", log_file)
        except Exception as e:
            log_print(f"\n⚠️ ERROR getting file info: {e}", log_file)
            log_print(traceback.format_exc(), log_file)
            raise
        
        # Load and convert to M15
        log_print("\n[INFO] Loading and converting to M15 bars...", log_file)
        log_print("(This may take several minutes for large files)", log_file)
        
        try:
            m15_data = create_m15_data(
                str(TICK_FILE), 
                start_date=START_DATE, 
                end_date=END_DATE,
                use_cache=True
            )
            
            log_print(f"\n✓ M15 bars loaded: {len(m15_data):,}", log_file)
            log_print(f"Period: {m15_data['datetime'].min()} to {m15_data['datetime'].max()}", log_file)
            
            # Show sample data
            log_print("\nSample M15 data (first 5 bars):", log_file)
            log_print(str(m15_data.head()), log_file)
            
        except Exception as e:
            log_print(f"\n⚠️ ERROR loading data: {e}", log_file)
            log_print(traceback.format_exc(), log_file)
            raise
        
        # ========== STEP 1.5: DIAGNOSTIC - Test signal generation ==========
        
        log_print("\n" + "="*50, log_file)
        log_print("STEP 1.5: Signal Generation Diagnostic", log_file)
        log_print("="*50, log_file)
        
        try:
            # Test signal generation with default params
            log_print("\nTesting signal generation with default parameters...", log_file)
            test_signals = generate_signals(m15_data, DEFAULT_PARAMS)
            test_signals = calculate_sl_tp(test_signals, DEFAULT_PARAMS)
            
            signal_count = (test_signals['signal'] != 0).sum()
            buy_count = (test_signals['signal'] == 1).sum()
            sell_count = (test_signals['signal'] == -1).sum()
            
            log_print(f"\nSignal Statistics:", log_file)
            log_print(f"  Total signals: {signal_count}", log_file)
            log_print(f"  Buy signals: {buy_count}", log_file)
            log_print(f"  Sell signals: {sell_count}", log_file)
            
            if signal_count == 0:
                log_print("\n⚠️ WARNING: No signals generated!", log_file)
                log_print("This may indicate a problem with range detection.", log_file)
                log_print("\nChecking data for range period...", log_file)
                
                # Check if data covers the range hours
                hours = m15_data['datetime'].dt.hour
                log_print(f"  Hours in data: {hours.min()} to {hours.max()}", log_file)
                
                # Check for hour 14 (range start)
                hour_14_count = (hours == 14).sum()
                hour_15_count = (hours == 15).sum()
                log_print(f"  Bars at hour 14: {hour_14_count}", log_file)
                log_print(f"  Bars at hour 15: {hour_15_count}", log_file)
            else:
                # Run quick backtest
                log_print("\nRunning quick backtest with default params...", log_file)
                backtester = Backtester(FTMO_US100, FTMO_ACCOUNT)
                quick_result = backtester.run(test_signals, m15_data, DEFAULT_PARAMS)
                log_print(f"  Trades executed: {quick_result.total_trades}", log_file)
                log_print(f"  Win rate: {quick_result.win_rate:.1%}", log_file)
                log_print(f"  Profit factor: {quick_result.profit_factor:.2f}", log_file)
                log_print(f"  Net profit: ${quick_result.net_profit:,.2f}", log_file)
                
        except Exception as e:
            log_print(f"\n⚠️ Diagnostic error: {e}", log_file)
            log_print(traceback.format_exc(), log_file)
        
        # ========== STEP 2: OPTIMIZATION ==========
        
        log_print("\n" + "="*50, log_file)
        log_print("STEP 2: Parameter Optimization", log_file)
        log_print("="*50, log_file)
        
        try:
            # Use PARAM_SPACE_REDUCED for faster testing (fewer parameters)
            # Switch to PARAM_SPACE for full optimization later
            optimizer = Optimizer(
                m15_data=m15_data,
                param_space=PARAM_SPACE_REDUCED,  # Use reduced space for testing
                train_ratio=TRAIN_RATIO,
                symbol_config=FTMO_US100,
                account_config=FTMO_ACCOUNT,
                n_jobs=-1  # Use all CPU cores
            )
            
            log_print(f"\n[INFO] Starting optimization with {N_COMBINATIONS} combinations...", log_file)
            log_print(f"[INFO] Using all available CPU cores for parallel processing", log_file)
            
            results = optimizer.run(
                method=OPTIMIZATION_METHOD,
                n_combinations=N_COMBINATIONS,
                top_n=TOP_N_RESULTS
            )
            
            log_print(f"\n✓ Optimization complete!", log_file)
            log_print(f"Valid results found: {len(results)}", log_file)
            
        except Exception as e:
            log_print(f"\n⚠️ ERROR during optimization: {e}", log_file)
            log_print(traceback.format_exc(), log_file)
            raise
        
        if not results:
            log_print("\n⚠️ No valid optimization results found.", log_file)
            log_print("Try increasing n_combinations or adjusting filters.", log_file)
            return
        
        # Print and export results
        log_print("\n--- Top 10 Results ---", log_file)
        for i, r in enumerate(results[:10]):
            log_print(f"\n#{i+1} Score: {r.combined_score:.4f}", log_file)
            log_print(f"   IS: {r.in_sample.total_trades} trades, PF={r.in_sample.profit_factor:.2f}, "
                      f"WR={r.in_sample.win_rate:.1%}, DD={r.in_sample.max_drawdown_pct:.1f}%", log_file)
            if r.out_of_sample:
                log_print(f"   OOS: {r.out_of_sample.total_trades} trades, PF={r.out_of_sample.profit_factor:.2f}, "
                          f"WR={r.out_of_sample.win_rate:.1%}", log_file)
        
        # Export to CSV
        results_csv = PROJECT_ROOT / "reports" / f"optimization_results_{timestamp}.csv"
        optimizer.export_results(results, str(results_csv))
        log_print(f"\n✓ Results exported: {results_csv}", log_file)
        
        # ========== STEP 3: STRESS TESTING ==========
        
        log_print("\n" + "="*50, log_file)
        log_print("STEP 3: Stress Testing Top Results", log_file)
        log_print("="*50, log_file)
        
        passed_results = []
        
        for i, opt_result in enumerate(results[:10]):
            log_print(f"\n[{i+1}/10] Testing strategy...", log_file)
            
            trades = opt_result.in_sample.trades
            if opt_result.out_of_sample:
                trades = trades + opt_result.out_of_sample.trades
            
            if len(trades) < 20:
                log_print(f"  Skipped - insufficient trades ({len(trades)})", log_file)
                continue
            
            try:
                tester = StressTester(
                    trades=trades,
                    initial_balance=FTMO_ACCOUNT['balance'],
                    max_dd_threshold=FTMO_ACCOUNT['max_total_loss_pct']
                )
                
                mc_result = tester.run_monte_carlo(MC_SIMULATIONS)
                passed = tester.passes_stress_test(mc_result)
                
                status = "PASSED ✓" if passed else "FAILED ✗"
                log_print(f"  {status} | Trades: {len(trades)}, Profit Mean: ${mc_result.profit_mean:,.0f}, "
                          f"Ruin Prob: {mc_result.ruin_probability:.1f}%", log_file)
                
                if passed:
                    passed_results.append({
                        'rank': i+1,
                        'opt_result': opt_result,
                        'mc_result': mc_result
                    })
                    
            except Exception as e:
                log_print(f"  ERROR: {e}", log_file)
        
        # ========== STEP 4: EXPORT TO DATABANK ==========
        
        log_print("\n" + "="*50, log_file)
        log_print("STEP 4: Exporting to Databank", log_file)
        log_print("="*50, log_file)
        
        databank_dir = PROJECT_ROOT / "databank"
        
        for i, res in enumerate(passed_results[:5]):  # Export top 5 passing strategies
            strategy_name = f"strategy_{timestamp}_{i+1:02d}"
            
            # Export as JSON
            json_file = databank_dir / f"{strategy_name}.json"
            strategy_data = {
                'name': strategy_name,
                'score': res['opt_result'].combined_score,
                'in_sample': {
                    'trades': res['opt_result'].in_sample.total_trades,
                    'profit_factor': res['opt_result'].in_sample.profit_factor,
                    'win_rate': res['opt_result'].in_sample.win_rate,
                    'net_profit': res['opt_result'].in_sample.net_profit,
                    'max_drawdown_pct': res['opt_result'].in_sample.max_drawdown_pct
                },
                'monte_carlo': {
                    'profit_mean': res['mc_result'].profit_mean,
                    'profit_5th_pct': res['mc_result'].profit_5th,
                    'ruin_probability': res['mc_result'].ruin_probability
                },
                'params': res['opt_result'].params
            }
            
            with open(json_file, 'w') as f:
                json.dump(strategy_data, f, indent=2, default=str)
            
            # Export as MT5 .set file
            set_file = databank_dir / f"{strategy_name}.set"
            export_mt5_set(res['opt_result'].params, str(set_file))
            
            log_print(f"✓ Exported: {strategy_name}", log_file)
        
        # ========== FINAL SUMMARY ==========
        
        log_print("\n" + "="*70, log_file)
        log_print("FINAL SUMMARY", log_file)
        log_print("="*70, log_file)
        
        log_print(f"\nTotal combinations tested: {N_COMBINATIONS}", log_file)
        log_print(f"Valid results: {len(results)}", log_file)
        log_print(f"Passed stress testing: {len(passed_results)}", log_file)
        
        if passed_results:
            log_print("\n✓ SUCCESS! Strategies exported to databank folder.", log_file)
            
            best = passed_results[0]
            log_print(f"\nBest Strategy (#{best['rank']}):", log_file)
            log_print(f"  Score: {best['opt_result'].combined_score:.4f}", log_file)
            log_print(f"  Trades: {best['opt_result'].in_sample.total_trades}", log_file)
            log_print(f"  Profit Factor: {best['opt_result'].in_sample.profit_factor:.2f}", log_file)
            log_print(f"  Win Rate: {best['opt_result'].in_sample.win_rate:.1%}", log_file)
            log_print(f"  Monte Carlo Profit: ${best['mc_result'].profit_mean:,.0f}", log_file)
        else:
            log_print("\n⚠️ No strategies passed stress testing.", log_file)
            log_print("Recommendations:", log_file)
            log_print("  - Try more combinations (increase N_COMBINATIONS)", log_file)
            log_print("  - Adjust parameter space", log_file)
            log_print("  - Use more historical data", log_file)
        
        log_print(f"\nCompleted: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}", log_file)
        log_print(f"\nOutput files:", log_file)
        log_print(f"  Log: {log_path}", log_file)
        log_print(f"  Results: {results_csv}", log_file)
        log_print(f"  Databank: {databank_dir}", log_file)
        log_print("="*70, log_file)
        
    except Exception as e:
        log_print(f"\n{'='*50}", log_file)
        log_print(f"CRITICAL ERROR", log_file)
        log_print(f"{'='*50}", log_file)
        log_print(f"\n{type(e).__name__}: {e}", log_file)
        log_print(f"\nFull traceback:", log_file)
        log_print(traceback.format_exc(), log_file)
        log_print(f"\nPlease check the error above and try again.", log_file)
        
    finally:
        log_file.close()
        print(f"\nLog saved to: {log_path}")


def export_mt5_set(params: dict, filepath: str):
    """Export parameters as MT5 .set file.
    
    IMPORTANT: Parameter names must EXACTLY match the EA input variable names.
    Enum values must be integers matching the enum order in MQL5.
    """
    
    # SL Method enum mapping (from EA):
    # SL_Fixed_Points = 0
    # SL_ATR_Based = 1
    # SL_Range_Based = 2
    sl_method_map = {
        'fixed': 0,
        'atr_based': 1,
        'range_based': 2
    }
    
    # Exit Strategy enum mapping (from EA):
    # Exit_Strategy_Off = 0
    # Breakeven_Points = 1
    # Trailing_Stop_Points = 2
    # Trailing_Stop_ATR = 3
    exit_strategy_map = {
        'off': 0,
        'breakeven': 1,
        'trailing_points': 2,
        'trailing_atr': 3
    }
    
    with open(filepath, 'w') as f:
        f.write("; URB Optimizer Generated Set File\n")
        f.write(f"; Generated: {datetime.now()}\n")
        f.write(";\n")
        
        # Risk Management
        if 'risk_percent' in params:
            f.write(f"InpRiskPerTradePct={params['risk_percent']}\n")
        
        # Stop Loss Method (enum as int)
        if 'sl_method' in params:
            sl_value = sl_method_map.get(params['sl_method'], 0)
            f.write(f"InpSlMethod={sl_value}\n")
        
        # SL Parameters
        if 'sl_fixed_points' in params:
            f.write(f"InpFixedSL_In_Points={params['sl_fixed_points']}\n")
        if 'sl_range_multiplier' in params:
            f.write(f"InpSLRangeMultiplier={params['sl_range_multiplier']}\n")
        if 'sl_min_points' in params:
            f.write(f"InpSLRangeMinPoints={params['sl_min_points']}\n")
        if 'sl_max_points' in params:
            f.write(f"InpSLRangeMaxPoints={params['sl_max_points']}\n")
        
        # TP (Risk:Reward)
        if 'tp_risk_reward' in params:
            f.write(f"InpRiskRewardRatio={params['tp_risk_reward']}\n")
        
        # Exit Strategy (enum as int)
        exit_strategy = params.get('exit_strategy', 'off')
        exit_value = exit_strategy_map.get(exit_strategy, 0)
        f.write(f"InpExitStrategyMode={exit_value}\n")
        
        # Trailing/Breakeven parameters
        if 'trailing_start_points' in params:
            f.write(f"InpTrailingStartPoints={params['trailing_start_points']}\n")
        if 'trailing_step_points' in params:
            f.write(f"InpTrailingStepPoints={params['trailing_step_points']}\n")
        if 'breakeven_trigger_points' in params:
            f.write(f"InpBreakevenTriggerPoints={params['breakeven_trigger_points']}\n")
        if 'breakeven_offset_points' in params:
            f.write(f"InpBreakevenOffsetPoints={params['breakeven_offset_points']}\n")
        
        # Range Schedule
        if 'range_start_hour' in params:
            f.write(f"InpRangeStartHour={params['range_start_hour']}\n")
        if 'range_end_hour' in params:
            f.write(f"InpRangeEndHour={params['range_end_hour']}\n")
        
        # Trading Window
        if 'trading_start_hour' in params:
            f.write(f"InpTradingStartHour={params['trading_start_hour']}\n")
        if 'trading_start_min' in params:
            f.write(f"InpTradingStartMin={params['trading_start_min']}\n")
        if 'trading_end_hour' in params:
            f.write(f"InpTradingEndHour={params['trading_end_hour']}\n")
        if 'trading_end_min' in params:
            f.write(f"InpTradingEndMin={params['trading_end_min']}\n")
        
        # Breakout Buffer
        if 'breakout_buffer_points' in params:
            f.write(f"InpBreakoutBuffer={params['breakout_buffer_points']}\n")


def run_module_tests(log_file):
    """Run basic tests with synthetic data."""
    import numpy as np
    import pandas as pd
    
    from config.broker_config import FTMO_US100, FTMO_ACCOUNT, DEFAULT_PARAMS
    from src.range_breaker import generate_signals, calculate_sl_tp
    from src.backtester import Backtester
    from src.optimizer import Optimizer, generate_param_combinations
    from src.stress_tests import StressTester
    
    log_print("\n[TEST] Creating synthetic M15 data...", log_file)
    
    np.random.seed(42)
    dates = pd.date_range('2024-01-02 00:00', periods=500, freq='15min')
    price = 21000 + np.cumsum(np.random.randn(500) * 15)
    
    m15_data = pd.DataFrame({
        'datetime': dates,
        'open': price,
        'high': price + np.random.rand(500) * 30,
        'low': price - np.random.rand(500) * 30,
        'close': price + np.random.randn(500) * 10,
        'tick_volume': np.random.randint(100, 1000, 500),
        'spread_avg': np.random.uniform(10, 20, 500)
    })
    
    log_print(f"  ✓ Created {len(m15_data)} synthetic bars", log_file)
    
    # Test signal generation
    log_print("\n[TEST] Signal generation...", log_file)
    try:
        signals = generate_signals(m15_data)
        signals = calculate_sl_tp(signals)
        signal_count = (signals['signal'] != 0).sum()
        log_print(f"  ✓ Generated {signal_count} signals", log_file)
    except Exception as e:
        log_print(f"  ✗ ERROR: {e}", log_file)
    
    # Test backtester
    log_print("\n[TEST] Backtester...", log_file)
    try:
        backtester = Backtester(FTMO_US100, FTMO_ACCOUNT)
        result = backtester.run(signals, m15_data, DEFAULT_PARAMS)
        log_print(f"  ✓ Backtest: {result.total_trades} trades, PF: {result.profit_factor:.2f}", log_file)
    except Exception as e:
        log_print(f"  ✗ ERROR: {e}", log_file)
    
    # Test optimizer
    log_print("\n[TEST] Optimizer (3 combinations)...", log_file)
    try:
        combos = generate_param_combinations({'risk_percent': [1.0, 1.5, 2.0]}, 'grid')
        log_print(f"  ✓ Generated {len(combos)} parameter combinations", log_file)
    except Exception as e:
        log_print(f"  ✗ ERROR: {e}", log_file)
    
    log_print("\n" + "="*50, log_file)
    log_print("All module tests completed!", log_file)
    log_print("="*50, log_file)
    log_print("\nTo run full optimization:", log_file)
    log_print("1. Place your tick data CSV file in the 'data' folder", log_file)
    log_print("2. Run this script again", log_file)


if __name__ == "__main__":
    main()
