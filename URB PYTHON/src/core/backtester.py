
import numpy as np
import polars as pl
from .logic import calculate_daily_ranges, backtest_core
from .indicators import calculate_adx, calculate_rsi, calculate_atr

class FastBacktester:
    def __init__(self, m1_data: pl.DataFrame):
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
        # Optimized for standard periods used in optimization (14)
        # If Builder asks for AdxPeriod=20, we should calc it there?
        # For efficiency in Gen Loop, we'll calculate a standard set.
        
        print("[Backtester] Pre-calculating Indicators (ADX 14, RSI 14)...")
        self.adx_14 = calculate_adx(self.highs, self.lows, self.closes, 14)
        self.rsi_14 = calculate_rsi(self.closes, 14)
        
        print(f"[Backtester] Ready with {len(self.data)} bars")

    def run(self, params: dict):
        """
        Run backtest with extended params (Cost, Filters).
        """
        range_highs, range_lows = calculate_daily_ranges(
            self.times, self.highs, self.lows,
            int(params['RangeStartHour']), int(params['RangeStartMin']),
            int(params['RangeEndHour']), int(params['RangeEndMin'])
        )
        
        # Helper to get correct indicator array
        # For now, we only support Period=14. 
        # If params['AdxPeriod'] != 14, we ignore or calc on fly (slow).
        # We enforce Period=14 in Builder for now.
        
        final_equity, wins, losses, equity_curve = backtest_core(
            self.ids, self.times, self.opens, self.highs, self.lows, self.closes,
            range_highs, range_lows, self.spreads,
            
            self.adx_14,
            self.rsi_14,
            
            int(params['TradingStartHour']), int(params['TradingStartMin']),
            int(params['TradingEndHour']), int(params['TradingEndMin']),
            float(params['BufferPoints']),
            float(params['SLPoints']),
            float(params['TPPoints']),
            
            # Filters
            bool(params.get('UseADX', False)),
            float(params.get('AdxThreshold', 25.0)),
            bool(params.get('UseRSI', False)),
            70.0, 30.0, # RSI Upper/Lower fixed for now
            
            # Costs
            float(params.get('Commission', 0.0)), # $ Per Lot
            float(params.get('SwapLong', 0.0)),
            float(params.get('SwapShort', 0.0))
        )
        
        total_trades = wins + losses
        win_rate = (wins / total_trades) * 100 if total_trades > 0 else 0.0
        net_profit = final_equity - 100000.0
        
        return {
            'NetProfit': net_profit,
            'Trades': total_trades,
            'WinRate': win_rate,
            'Equity': final_equity
        }
