"""
Backtester Module (Two-Timeframe Architecture)

Simulates trades using:
1. Signal Timeframe (e.g., M15, H1, H4) -> To detect entries
2. Execution Timeframe (M1) -> To simulate precise price movement (SL/TP hit accuracy)

This replaces the naive single-timeframe simulation.
"""

import pandas as pd
import numpy as np
from typing import List, Dict, Optional
from dataclasses import dataclass
from datetime import datetime, time

# Reuse Trade dataclass from original but extended if needed
@dataclass
class Trade:
    entry_time: datetime
    entry_price: float
    direction: int  # 1 (Long) or -1 (Short)
    lot_size: float
    sl_price: float
    tp_price: float
    
    # Exit info
    exit_time: datetime = None
    exit_price: float = None
    exit_reason: str = None
    
    # Metrics
    net_profit: float = 0.0
    duration_bars: int = 0
    max_favorable: float = 0.0
    max_adverse: float = 0.0

class BacktesterM1:
    def __init__(self, symbol_config: dict, account_config: dict):
        self.symbol = symbol_config
        self.account = account_config
        self.equity_curve = []
        
    def run(self, 
            signals: pd.DataFrame, 
            signal_tf_data: pd.DataFrame, 
            m1_data: pd.DataFrame,
            params: dict) -> Dict:
        """
        Run backtest using dual-timeframe logic.
        
        Args:
            signals: DataFrame containing ONLY rows with entry signals (from Signal TF).
            signal_tf_data: Full Signal TF OHLC data (for general context).
            m1_data: Full M1 OHLC data (for execution simulation).
            params: Strategy parameters.
        """
        
        trades: List[Trade] = []
        equity = self.account['balance']
        self.equity_curve = [equity]
        
        # Performance Optimization: Convert M1 data to arrays/dict for faster lookup
        # Index M1 data by time for fast slicing
        # Ensure M1 is sorted
        # m1_data.sort_values('datetime', inplace=True) # Assumed sorted by loader
        
        # We need to quickly find M1 bars occurring AFTER a signal time.
        # Let's iterate through signals.
        
        active_trade: Optional[Trade] = None
        
        # Loop through signals
        for idx, signal_row in signals.iterrows():
            
            # Skip if we already have a trade open (Simple sequential logic)
            # Todo: Support multiple trades if strategy allows
            if active_trade is not None:
                # Check if specific trade closed?
                # For simplicity, we simulate the trade fully before taking the next signal
                # Wait, signals are chronological.
                # If signal time < active_trade.exit_time, ignore signal.
                if signal_row['datetime'] < active_trade.exit_time:
                    continue
                else:
                    active_trade = None # Trade finished, ready for new one
            
            current_time = signal_row['datetime']
            
            # Calculate Entry Price (Ask for Buy, Bid for Sell)
            # Default spread from config or data
            spread = signal_row.get('spread', self.symbol.get('spread', 10) * self.symbol['point_size'])
            
            direction = int(signal_row['signal'])
            
            # Simulate Slippage?
            slippage = 0 # Can add random noise here
            
            if direction == 1:
                entry_price = signal_row['close'] + (spread / 2) + slippage
                # SL/TP
                sl = signal_row['sl_price']
                tp = signal_row['tp_price']
            else:
                entry_price = signal_row['close'] - (spread / 2) - slippage
                sl = signal_row['sl_price']
                tp = signal_row['tp_price']
            
            # Create Trade Object
            # Lots calculation (simplified)
            risk_amt = equity * (params.get('risk_percent', 1.0) / 100)
            dist_pts = abs(entry_price - sl) / self.symbol['point_size']
            if dist_pts <= 0: dist_pts = 100 # Safety
            lot_size = risk_amt / (dist_pts * self.symbol['value_per_point'])
            lot_size = round(lot_size, 2)
            
            trade = Trade(
                entry_time=current_time,
                entry_price=entry_price,
                direction=direction,
                lot_size=lot_size,
                sl_price=sl,
                tp_price=tp
            )
            
            # --- EXECUTION SIMULATION (The M1 Loop) ---
            # Extract M1 bars that happen AFTER entry
            # Use searchsorted for speed if converted to numpy, otherwise boolean mask
            # For simplicity in Python:
            
            # Optimization: Masking is slow inside loop.
            # Better: Slice array via index search.
            
            # We assume m1_data has a DatetimeIndex or 'datetime' column
            # Find index of entry time
            
            # This is the heavy part.
            start_idx = m1_data['datetime'].searchsorted(current_time)
            
            # Iterate M1 bars from start_idx
            # We use a subset for efficiency
            # Max trade duration assumption? 1 week?
            # Let's take next 5000 M1 bars (roughly 3-4 days) to avoid creating huge slice
            max_bars = 5000 
            subset = m1_data.iloc[start_idx : start_idx + max_bars]
            
            trade_closed = False
            
            for _, bar in subset.iterrows():
                # Check for Valid Bar time (must be >= entry time)
                if bar['datetime'] <= current_time:
                    continue
                
                # Check High/Low vs SL/TP
                # Logic: In M1, we assume if Low hits SL, it happened.
                # If High hits TP, it happened.
                # Ambiguity: What if High > TP AND Low < SL in same M1 bar?
                # M1 Granularity is usually fine to assume Worst Case (SL first) or Random.
                # Let's use Worst Case (Pessimistic Backtest)
                
                # LONG TRADE
                if direction == 1:
                    # Check SL
                    if bar['low'] <= trade.sl_price:
                        trade.exit_price = trade.sl_price
                        trade.exit_time = bar['datetime']
                        trade.exit_reason = 'SL'
                        trade.net_profit = (trade.exit_price - trade.entry_price) * lot_size * self.symbol['contract_size']
                        trade_closed = True
                        break
                    
                    # Check TP
                    if bar['high'] >= trade.tp_price:
                        trade.exit_price = trade.tp_price
                        trade.exit_time = bar['datetime']
                        trade.exit_reason = 'TP'
                        trade.net_profit = (trade.exit_price - trade.entry_price) * lot_size * self.symbol['contract_size']
                        trade_closed = True
                        break
                        
                    # Time Check (End of Session / Friday Close)
                    # (Optional logic here)
                    
                # SHORT TRADE
                else:
                    # Check SL (High >= SL)
                    if bar['high'] >= trade.sl_price:
                        trade.exit_price = trade.sl_price
                        trade.exit_time = bar['datetime']
                        trade.exit_reason = 'SL'
                        trade.net_profit = (trade.entry_price - trade.exit_price) * lot_size * self.symbol['contract_size']
                        trade_closed = True
                        break
                        
                    # Check TP (Low <= TP)
                    if bar['low'] <= trade.tp_price:
                        trade.exit_price = trade.tp_price
                        trade.exit_time = bar['datetime']
                        trade.exit_reason = 'TP'
                        trade.net_profit = (trade.entry_price - trade.exit_price) * lot_size * self.symbol['contract_size']
                        trade_closed = True
                        break

            # If trade closed, add to list and update equity
            if trade_closed:
                trades.append(trade)
                equity += trade.net_profit
                self.equity_curve.append(equity)
                active_trade = trade # Mark as active so top loop knows to skip until this time
            else:
                # Trade didn't close in window? Force close or ignore?
                # For robust testing, mark as "Time Limit" or keep open
                pass
                
        return {
            'total_trades': len(trades),
            'final_equity': equity,
            'trades': trades
        }

