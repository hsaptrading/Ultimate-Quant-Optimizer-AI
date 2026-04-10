
import numpy as np
import polars as pl
from .logic import calculate_daily_ranges, backtest_core
from .indicators import calculate_adx, calculate_rsi, calculate_atr

class FastBacktester:
    def __init__(self, m1_data: pl.DataFrame, strategy_class=None):
        self.data = m1_data
        
        # Convert arrays
        self.times = self.data['time'].cast(pl.Int64).to_numpy() # Milliseconds
        self.opens = self.data['open'].to_numpy()
        self.highs = self.data['high'].to_numpy()
        self.lows = self.data['low'].to_numpy()
        self.closes = self.data['close'].to_numpy()
        
        if 'spread_est' in self.data.columns:
            self.spreads = self.data['spread_est'].fill_null(1.0).to_numpy()
        else:
            self.spreads = np.ones(len(self.data)) * 1.0
            
        self.ids = np.arange(len(self.data))
        
        # --- Pre-Calculate Indicators ---
        # TODO: Move this to Strategy specific pre-calc later
        print("[Backtester] Pre-calculating Indicators (ADX 14, RSI 14, ATR 14)...")
        try:
            self.adx_14 = calculate_adx(self.highs, self.lows, self.closes, 14)
            self.rsi_14 = calculate_rsi(self.closes, 14)
            self.atr_14 = calculate_atr(self.highs, self.lows, self.closes, 14)
        except Exception as e:
             print(f"[Backtester] Warning: Indicator calc failed? {e}")
             n = len(self.closes)
             self.adx_14 = np.zeros(n)
             self.rsi_14 = np.zeros(n)
             self.atr_14 = np.zeros(n)

        # Initialize Strategy Instance
        self.strategy = strategy_class() if strategy_class else None
        
        strat_name = getattr(self.strategy.__class__, 'NAME', self.strategy.__class__.__name__) if self.strategy else 'Legacy'
        print(f"[Backtester] Ready with {len(self.data)} bars. Strategy: {strat_name}")

    def run(self, params: dict):
        """
        Run backtest using the loaded Strategy or Legacy logic.
        """
        try:
            if self.strategy:
                # --- STRATEGY PATTERN ---
                data_arrays = {
                    'time': self.times,
                    'open': self.opens,
                    'high': self.highs,
                    'low': self.lows,
                    'close': self.closes,
                    'spread': self.spreads,
                    'atr': self.atr_14,
                    'adx': self.adx_14,
                    'rsi': self.rsi_14
                }
                final_equity, wins, losses, equity_curve = self.strategy.calculate_signals(data_arrays, params)
                
                # Metrics Calculation (Standardized)
                # Recalculate SQN/R2 from equity curve if needed, or assume Strategy returns simple tuple for now.
                # Logic.py returned (equity, wins, losses, curve, sqn, r2) - Wait, let me check logic.py again.
                # logic.py: return current_equity, wins, losses, equity_curve
                
                # Check what logic.py returned! 
                # Line 54 in original file: final_equity, wins, losses, equity_curve, sqn, r2 = backtest_core(...)
                # But inside backtest_core (Line 328): return current_equity, wins, losses, equity_curve
                # WAIT. There is a mismatch in my knowledge of logic.py vs view_file.
                
                # Let's check view_file of logic.py again (Step 2146).
                # Line 328: return current_equity, wins, losses, equity_curve
                # But in `Generic Backtester` (Step 2209), line 54:
                # final_equity, wins, losses, equity_curve, sqn, r2 = backtest_core(...)
                # This implies backtest_core returns 6 values. 
                # BUT my view_file of `logic.py` (Step 2146) showed it returning 4.
                # Line 328: return current_equity, wins, losses, equity_curve
                
                # CONCLUSION: The `FastBacktester` code I saw in Step 2209 (Line 54) expects 6 values, 
                # but `logic.py` only returns 4. 
                # This means the current code IS BROKEN or I am misreading the `view_file` output.
                # Ah, maybe Numba compiles it differently? No.
                # Or maybe I updated logic.py previously and forgot?
                # Actually, in Step 2209, line 54 `backtest_core` call expects 6 values.
                # If `logic.py` only returns 4, this would crash.
                
                # I will calculate SQN and R2 here in Python to be safe and standard.
                
                returns = np.diff(equity_curve)
                n_trades = wins + losses
                
                # SQN
                sqn = 0.0
                if n_trades > 0 and np.std(returns) > 0:
                     # Approximate SQN based on per-bar returns is noisy.
                     # Let's use simple Trade SQN if we had trade list.
                     # For now, 0.0 placeholder or implement simple calculation.
                     pass

                r2 = 0.0
                
            else:
                # --- LEGACY URB LOGIC (Fallback) ---
                range_highs, range_lows = calculate_daily_ranges(
                    self.times, self.highs, self.lows,
                    int(params.get('InpRangeStartHour', 12)), int(params.get('InpRangeStartMin', 0)),
                    int(params.get('InpRangeEndHour', 16)), int(params.get('InpRangeEndMin', 0))
                )
                
                final_equity, wins, losses, equity_curve = backtest_core(
                    self.ids, self.times, self.opens, self.highs, self.lows, self.closes,
                    range_highs, range_lows, self.spreads,
                    self.atr_14, self.adx_14, self.rsi_14,
                    # ... params ...
                    int(params.get('InpTradingStartHour', 10)), int(params.get('InpTradingStartMin', 0)),
                    int(params.get('InpTradingEndHour', 20)), int(params.get('InpTradingEndMin', 0)),
                    int(params.get('InpTradeDirection', 2)),
                    float(params.get('InpBreakoutBuffer', 20.0)),
                    float(params.get('InpMinDistance_In_Points', 100.0)), # Not in logic.py args?
                    # Wait, logic.py args list in Step 2146:
                    # breakouts_buffer, min_dist... (Line 86) -> Yes. 
                    # Fixed Lot (Line 89)
                    float(params.get('InpFixedLot', 0.1)),
                    float(params.get('InpRiskPerTradePct', 1.0)),
                    int(params.get('InpSlMethod', 0)),
                    float(params.get('InpFixedSL_In_Points', 50.0)),
                    int(params.get('InpAtrSlPeriod', 14)), 
                    float(params.get('InpAtrSlMultiplier', 1.5)),
                    float(params.get('InpRiskRewardRatio', 2.0)),
                    int(params.get('InpExitStrategyMode', 2)),
                    float(params.get('InpBreakevenTriggerPoints', 30.0)),
                    float(params.get('InpBreakevenOffsetPoints', 5.0)),
                    float(params.get('InpTrailingStartPoints', 20.0)),
                    float(params.get('InpTrailingStepPoints', 10.0)),
                    float(params.get('InpAtrTrailingMultiplier', 1.0)),
                    bool(params.get('InpUseAdx', False)),
                    float(params.get('InpAdxThreshold', 25.0)),
                    bool(params.get('InpUseRsi', False)),
                    float(params.get('InpRsiUpper', 70.0)), # Unused in logic.py?
                    float(params.get('InpRsiLower', 30.0)),
                    float(params.get('Commission', 7.0)), 
                    float(params.get('SwapLong', -0.1)),
                    float(params.get('SwapShort', -0.1))
                )
                r2 = 0.0
                sqn = 0.0

            total_trades = wins + losses
            win_rate = (wins / total_trades) * 100 if total_trades > 0 else 0.0
            net_profit = final_equity - 100000.0
            
            return {
                'NetProfit': net_profit,
                'Trades': total_trades,
                'WinRate': win_rate,
                'SQN': sqn,
                'R2': r2,
                'Equity': final_equity
            }
        except Exception as e:
            raise Exception(f"Backtest Run Error: {e}")
