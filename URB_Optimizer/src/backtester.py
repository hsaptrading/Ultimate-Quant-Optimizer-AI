"""
Backtester Module

Simulates trades based on Range Breaker signals with:
- Spread and slippage simulation
- SL/TP/Trailing stop execution
- Swap costs calculation
- Full trade logging and metrics
"""

import pandas as pd
import numpy as np
from typing import List, Dict, Tuple, Optional
from dataclasses import dataclass, field
from datetime import datetime, timedelta
import sys
from pathlib import Path

sys.path.append(str(Path(__file__).parent.parent))
from config.broker_config import FTMO_US100, FTMO_ACCOUNT, DEFAULT_PARAMS


@dataclass
class Trade:
    """Represents a single trade."""
    entry_bar: int
    entry_time: datetime
    entry_price: float
    direction: int  # 1 = buy, -1 = sell
    lot_size: float
    sl_price: float
    tp_price: float
    
    # Exit info (filled when closed)
    exit_bar: int = None
    exit_time: datetime = None
    exit_price: float = None
    exit_reason: str = None  # 'sl', 'tp', 'trailing', 'time', 'session'
    
    # Calculated fields
    profit_points: float = 0
    profit_usd: float = 0
    swap_cost: float = 0
    commission: float = 0
    net_profit: float = 0
    duration_bars: int = 0
    max_favorable: float = 0  # MAE/MFE
    max_adverse: float = 0


@dataclass
class BacktestResult:
    """Results of a backtest run."""
    trades: List[Trade]
    equity_curve: List[float]
    params: dict
    
    # Summary metrics
    total_trades: int = 0
    winning_trades: int = 0
    losing_trades: int = 0
    win_rate: float = 0
    
    gross_profit: float = 0
    gross_loss: float = 0
    net_profit: float = 0
    profit_factor: float = 0
    
    max_drawdown: float = 0
    max_drawdown_pct: float = 0
    sharpe_ratio: float = 0
    
    avg_win: float = 0
    avg_loss: float = 0
    avg_trade: float = 0
    
    max_consecutive_wins: int = 0
    max_consecutive_losses: int = 0


class Backtester:
    """
    Vectorized backtester for Range Breaker strategy.
    """
    
    def __init__(self, 
                 symbol_config: dict = None,
                 account_config: dict = None):
        """
        Initialize backtester with broker configuration.
        
        Args:
            symbol_config: Symbol specifications (default: FTMO_US100)
            account_config: Account settings (default: FTMO_ACCOUNT)
        """
        self.symbol = symbol_config or FTMO_US100
        self.account = account_config or FTMO_ACCOUNT
        
    def calculate_lot_size(self, 
                           sl_points: float, 
                           risk_percent: float,
                           equity: float) -> float:
        """
        Calculate position size based on risk parameters.
        
        Args:
            sl_points: Stop loss distance in points
            risk_percent: Risk per trade as percentage
            equity: Current account equity
            
        Returns:
            Lot size rounded to lot_step
        """
        risk_amount = equity * (risk_percent / 100)
        
        # Value per point per lot
        point_value = self.symbol['point_size']
        
        # Lot size = Risk / (SL points * point value)
        lot_size = risk_amount / (sl_points * point_value)
        
        # Round to lot step
        lot_step = self.symbol['lot_step']
        lot_size = round(lot_size / lot_step) * lot_step
        
        # Apply min/max limits
        lot_size = max(lot_size, self.symbol['min_lot'])
        lot_size = min(lot_size, self.symbol['max_lot'])
        
        # Check margin requirement
        margin_required = lot_size * self.symbol['margin_per_lot_usd']
        if margin_required > equity * 0.9:  # Max 90% margin usage
            lot_size = (equity * 0.9) / self.symbol['margin_per_lot_usd']
            lot_size = round(lot_size / lot_step) * lot_step
        
        return lot_size
    
    def simulate_entry(self, 
                       bar_close: float, 
                       direction: int) -> float:
        """
        Simulate entry price with spread and slippage.
        
        Args:
            bar_close: Close price of signal bar
            direction: 1 for buy, -1 for sell
            
        Returns:
            Simulated entry price
        """
        spread = self.symbol['spread_avg_points']
        slippage = np.random.uniform(0, 3)  # 0-3 points random slippage
        
        if direction == 1:  # Buy at ask
            return bar_close + spread/2 + slippage
        else:  # Sell at bid
            return bar_close - spread/2 - slippage
    
    def calculate_swap(self, 
                       direction: int, 
                       lot_size: float, 
                       nights: int) -> float:
        """
        Calculate swap cost for holding position overnight.
        
        Args:
            direction: 1 for buy, -1 for sell
            lot_size: Position size
            nights: Number of nights held
            
        Returns:
            Total swap cost (negative = cost, positive = earn)
        """
        if direction == 1:
            swap_rate = self.symbol['swap_long_points']
        else:
            swap_rate = self.symbol['swap_short_points']
        
        # Swap is in points, convert to USD
        return swap_rate * lot_size * self.symbol['point_size'] * nights
    
    def run(self, 
            signals_df: pd.DataFrame, 
            m15_data: pd.DataFrame,
            params: dict = None,
            initial_balance: float = None) -> BacktestResult:
        """
        Run backtest on signal data.
        
        Args:
            signals_df: DataFrame with signal column and SL/TP info
            m15_data: Full M15 data for exit simulation
            params: Strategy parameters
            initial_balance: Starting balance (default: from account config)
            
        Returns:
            BacktestResult with all trades and metrics
        """
        if params is None:
            params = DEFAULT_PARAMS
            
        if initial_balance is None:
            initial_balance = self.account['balance']
        
        trades = []
        equity = initial_balance
        equity_curve = [equity]
        
        # Get signal bars
        signal_bars = signals_df[signals_df['signal'] != 0].copy()
        
        # Track active position
        active_trade: Optional[Trade] = None
        trailing_sl = None
        
        for idx, signal_row in signal_bars.iterrows():
            # Skip if position already open
            if active_trade is not None:
                continue
            
            # Calculate entry
            direction = int(signal_row['signal'])
            entry_price = self.simulate_entry(signal_row['close'], direction)
            
            # Get SL distance in price and points
            sl_distance = signal_row.get('sl_distance', signal_row['sl_points'] * self.symbol['point_size'])
            sl_points = signal_row['sl_points']  # MT5 points for lot calculation
            
            # Calculate lot size based on SL in points
            risk_pct = params.get('risk_percent', 1.0)
            lot_size = self.calculate_lot_size(sl_points, risk_pct, equity)
            
            if lot_size < self.symbol['min_lot']:
                continue  # Skip if can't afford minimum position
            
            # Use SL/TP prices from signal (already calculated in price units)
            # Adjust for entry price difference from signal close
            price_diff = entry_price - signal_row['close']
            sl_price = signal_row['sl_price'] + price_diff
            tp_price = signal_row['tp_price'] + price_diff
            
            # Create trade
            active_trade = Trade(
                entry_bar=idx,
                entry_time=signal_row['datetime'],
                entry_price=entry_price,
                direction=direction,
                lot_size=lot_size,
                sl_price=sl_price,
                tp_price=tp_price
            )
            
            trailing_sl = sl_price if params.get('use_trailing_stop', True) else None
            
            # Simulate exit
            exit_found = False
            
            # Get bars after entry
            future_bars = m15_data[m15_data['datetime'] > signal_row['datetime']]
            
            for exit_idx, bar in future_bars.iterrows():
                if exit_found:
                    break
                
                high = bar['high']
                low = bar['low']
                close = bar['close']
                bar_time = bar['datetime']
                
                # Check session end
                if bar_time.hour >= 23 and bar_time.minute >= 50:
                    if params.get('close_end_of_session', True):
                        active_trade.exit_bar = exit_idx
                        active_trade.exit_time = bar_time
                        active_trade.exit_price = close
                        active_trade.exit_reason = 'session'
                        exit_found = True
                        continue
                
                # Update trailing stop
                if params.get('use_trailing_stop', True) and trailing_sl is not None:
                    trail_start = params.get('trailing_start_points', 5000)
                    trail_step = params.get('trailing_step_points', 500)
                    
                    if direction == 1:  # Long
                        profit_pts = close - entry_price
                        if profit_pts >= trail_start:
                            new_sl = close - trail_step
                            trailing_sl = max(trailing_sl, new_sl)
                    else:  # Short
                        profit_pts = entry_price - close
                        if profit_pts >= trail_start:
                            new_sl = close + trail_step
                            trailing_sl = min(trailing_sl, new_sl)
                
                # Check breakeven
                if params.get('use_breakeven', True):
                    be_trigger = params.get('breakeven_trigger_points', 3000)
                    be_offset = params.get('breakeven_offset_points', 500)
                    
                    if direction == 1:
                        if close - entry_price >= be_trigger:
                            be_sl = entry_price + be_offset
                            if trailing_sl is None or be_sl > trailing_sl:
                                trailing_sl = be_sl
                    else:
                        if entry_price - close >= be_trigger:
                            be_sl = entry_price - be_offset
                            if trailing_sl is None or be_sl < trailing_sl:
                                trailing_sl = be_sl
                
                # Use trailing SL if active
                current_sl = trailing_sl if trailing_sl is not None else active_trade.sl_price
                
                # Check SL hit
                if direction == 1:
                    if low <= current_sl:
                        active_trade.exit_bar = exit_idx
                        active_trade.exit_time = bar_time
                        active_trade.exit_price = current_sl
                        active_trade.exit_reason = 'trailing' if trailing_sl else 'sl'
                        exit_found = True
                        continue
                else:
                    if high >= current_sl:
                        active_trade.exit_bar = exit_idx
                        active_trade.exit_time = bar_time
                        active_trade.exit_price = current_sl
                        active_trade.exit_reason = 'trailing' if trailing_sl else 'sl'
                        exit_found = True
                        continue
                
                # Check TP hit
                if direction == 1:
                    if high >= active_trade.tp_price:
                        active_trade.exit_bar = exit_idx
                        active_trade.exit_time = bar_time
                        active_trade.exit_price = active_trade.tp_price
                        active_trade.exit_reason = 'tp'
                        exit_found = True
                        continue
                else:
                    if low <= active_trade.tp_price:
                        active_trade.exit_bar = exit_idx
                        active_trade.exit_time = bar_time
                        active_trade.exit_price = active_trade.tp_price
                        active_trade.exit_reason = 'tp'
                        exit_found = True
                        continue
                
                # Track MAE/MFE
                if direction == 1:
                    active_trade.max_favorable = max(active_trade.max_favorable, high - entry_price)
                    active_trade.max_adverse = max(active_trade.max_adverse, entry_price - low)
                else:
                    active_trade.max_favorable = max(active_trade.max_favorable, entry_price - low)
                    active_trade.max_adverse = max(active_trade.max_adverse, high - entry_price)
            
            # If no exit found (end of data), close at last bar
            if not exit_found and active_trade is not None:
                last_bar = m15_data.iloc[-1]
                active_trade.exit_bar = len(m15_data) - 1
                active_trade.exit_time = last_bar['datetime']
                active_trade.exit_price = last_bar['close']
                active_trade.exit_reason = 'end_of_data'
            
            # Calculate P&L
            if active_trade.exit_price is not None:
                if direction == 1:
                    active_trade.profit_points = active_trade.exit_price - entry_price
                else:
                    active_trade.profit_points = entry_price - active_trade.exit_price
                
                # profit_points is actually in PRICE (not MT5 points)
                # For US100: profit_usd = price_movement * contract_size * lots
                # Contract size = 1, so profit = price_move * lots
                active_trade.profit_usd = (
                    active_trade.profit_points * 
                    lot_size * 
                    self.symbol.get('contract_size', 1.0)
                )
                
                # Calculate swap (if held overnight)
                entry_date = active_trade.entry_time.date()
                exit_date = active_trade.exit_time.date()
                nights = (exit_date - entry_date).days
                if nights > 0:
                    active_trade.swap_cost = self.calculate_swap(direction, lot_size, nights)
                
                active_trade.net_profit = active_trade.profit_usd + active_trade.swap_cost
                active_trade.duration_bars = active_trade.exit_bar - active_trade.entry_bar
                
                # Update equity
                equity += active_trade.net_profit
                equity_curve.append(equity)
                
                trades.append(active_trade)
                active_trade = None
                trailing_sl = None
        
        # Calculate summary metrics
        result = self._calculate_metrics(trades, equity_curve, params, initial_balance)
        
        return result
    
    def _calculate_metrics(self, 
                           trades: List[Trade], 
                           equity_curve: List[float],
                           params: dict,
                           initial_balance: float) -> BacktestResult:
        """Calculate summary statistics from trades."""
        
        result = BacktestResult(
            trades=trades,
            equity_curve=equity_curve,
            params=params
        )
        
        if not trades:
            return result
        
        profits = [t.net_profit for t in trades]
        
        result.total_trades = len(trades)
        result.winning_trades = sum(1 for p in profits if p > 0)
        result.losing_trades = sum(1 for p in profits if p < 0)
        result.win_rate = result.winning_trades / result.total_trades if result.total_trades > 0 else 0
        
        result.gross_profit = sum(p for p in profits if p > 0)
        result.gross_loss = abs(sum(p for p in profits if p < 0))
        result.net_profit = sum(profits)
        result.profit_factor = result.gross_profit / result.gross_loss if result.gross_loss > 0 else float('inf')
        
        # Drawdown
        peak = initial_balance
        max_dd = 0
        for eq in equity_curve:
            if eq > peak:
                peak = eq
            dd = peak - eq
            if dd > max_dd:
                max_dd = dd
        result.max_drawdown = max_dd
        result.max_drawdown_pct = (max_dd / initial_balance) * 100
        
        # Average trades
        result.avg_trade = np.mean(profits) if profits else 0
        winning_trades = [p for p in profits if p > 0]
        losing_trades = [p for p in profits if p < 0]
        result.avg_win = np.mean(winning_trades) if winning_trades else 0
        result.avg_loss = np.mean(losing_trades) if losing_trades else 0
        
        # Sharpe ratio (assuming daily returns)
        if len(equity_curve) > 1:
            returns = np.diff(equity_curve) / equity_curve[:-1]
            if len(returns) > 0 and np.std(returns) > 0:
                result.sharpe_ratio = (np.mean(returns) / np.std(returns)) * np.sqrt(252)
        
        # Consecutive wins/losses
        streak = 0
        max_win_streak = 0
        max_loss_streak = 0
        
        for p in profits:
            if p > 0:
                if streak > 0:
                    streak += 1
                else:
                    streak = 1
                max_win_streak = max(max_win_streak, streak)
            else:
                if streak < 0:
                    streak -= 1
                else:
                    streak = -1
                max_loss_streak = max(max_loss_streak, abs(streak))
        
        result.max_consecutive_wins = max_win_streak
        result.max_consecutive_losses = max_loss_streak
        
        return result


def print_backtest_summary(result: BacktestResult):
    """Print a formatted summary of backtest results."""
    print("\n" + "="*60)
    print("BACKTEST RESULTS")
    print("="*60)
    
    print(f"\n--- Trade Statistics ---")
    print(f"Total Trades:       {result.total_trades}")
    print(f"Winning Trades:     {result.winning_trades}")
    print(f"Losing Trades:      {result.losing_trades}")
    print(f"Win Rate:           {result.win_rate:.1%}")
    
    print(f"\n--- Profit/Loss ---")
    print(f"Gross Profit:       ${result.gross_profit:,.2f}")
    print(f"Gross Loss:         ${result.gross_loss:,.2f}")
    print(f"Net Profit:         ${result.net_profit:,.2f}")
    print(f"Profit Factor:      {result.profit_factor:.2f}")
    
    print(f"\n--- Risk Metrics ---")
    print(f"Max Drawdown:       ${result.max_drawdown:,.2f} ({result.max_drawdown_pct:.1f}%)")
    print(f"Sharpe Ratio:       {result.sharpe_ratio:.2f}")
    
    print(f"\n--- Trade Averages ---")
    print(f"Avg Win:            ${result.avg_win:,.2f}")
    print(f"Avg Loss:           ${result.avg_loss:,.2f}")
    print(f"Avg Trade:          ${result.avg_trade:,.2f}")
    
    print(f"\n--- Streaks ---")
    print(f"Max Consecutive Wins:   {result.max_consecutive_wins}")
    print(f"Max Consecutive Losses: {result.max_consecutive_losses}")
    
    print("="*60)


# Test
if __name__ == "__main__":
    print("Backtester module loaded successfully!")
    print(f"Symbol config: {FTMO_US100['symbol']}")
    print(f"Account balance: ${FTMO_ACCOUNT['balance']:,}")
