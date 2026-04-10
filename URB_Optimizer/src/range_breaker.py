"""
Range Breaker Strategy Logic (Updated to match EA logic)

Implements the core logic of the Ultimate Range Breaker strategy:
1. Calculate support/resistance from Range Period (e.g., 12:15-16:00)
2. Wait for Trading Window (Kill Zone) to open (e.g., 16:30-17:30)
3. Detect breakouts above resistance or below support during Trading Window
4. Generate trade signals with proper direction

IMPORTANT: All "_points" parameters from MT5 are in points (0.01 for US100).
Use points_to_price() to convert to actual price units.
"""

import pandas as pd
import numpy as np
from typing import Tuple, Optional
from datetime import datetime, time, timedelta

# Add parent directory to path for config import
import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))
from config.broker_config import DEFAULT_PARAMS, points_to_price, FTMO_US100


def calculate_daily_range(m15_data: pd.DataFrame, params: dict) -> pd.DataFrame:
    """
    Calculate the daily range (support/resistance).
    
    Range Period: When the EA measures high/low to create S/R levels.
    For example, 12:15 to 16:00 server time.
    
    Args:
        m15_data: DataFrame with datetime, open, high, low, close columns
        params: Strategy parameters with range_start_hour, range_start_min, etc.
        
    Returns:
        DataFrame with added columns: range_high, range_low, range_size
    """
    df = m15_data.copy()
    
    # Get range timing from params
    range_start_hour = params.get('range_start_hour', 12)
    range_start_min = params.get('range_start_min', 15)
    range_end_hour = params.get('range_end_hour', 16)
    range_end_min = params.get('range_end_min', 0)
    
    # Convert range times to time objects
    range_start = time(range_start_hour, range_start_min)
    range_end = time(range_end_hour, range_end_min)
    
    # Extract date and time components
    df['date'] = df['datetime'].dt.date
    df['time'] = df['datetime'].dt.time
    df['hour'] = df['datetime'].dt.hour
    df['minute'] = df['datetime'].dt.minute
    
    # Mark bars that are within the range period
    df['in_range'] = (df['time'] >= range_start) & (df['time'] < range_end)
    
    # Calculate range high/low for each day
    range_data = df[df['in_range']].groupby('date').agg(
        range_high=('high', 'max'),
        range_low=('low', 'min'),
        range_open=('open', 'first'),
        range_close=('close', 'last')
    ).reset_index()
    
    # Calculate range size
    range_data['range_size'] = range_data['range_high'] - range_data['range_low']
    
    # Merge back to main dataframe
    df = df.merge(range_data, on='date', how='left')
    
    # Range is complete only AFTER range_end
    df['range_complete'] = df['time'] >= range_end
    
    # Clear range values before range is complete
    for col in ['range_high', 'range_low', 'range_size', 'range_open', 'range_close']:
        df.loc[~df['range_complete'], col] = np.nan
    
    return df


def apply_trading_window(df: pd.DataFrame, params: dict) -> pd.DataFrame:
    """
    Mark bars that are within the Trading Window (Kill Zone).
    
    Trades can ONLY be taken during this window, even if a breakout occurs.
    
    Args:
        df: DataFrame with datetime column
        params: Strategy parameters with trading_start_hour, trading_end_hour, etc.
        
    Returns:
        DataFrame with 'in_trading_window' column
    """
    df = df.copy()
    
    # Get trading window timing from params
    trading_start_hour = params.get('trading_start_hour', 16)
    trading_start_min = params.get('trading_start_min', 30)
    trading_end_hour = params.get('trading_end_hour', 17)
    trading_end_min = params.get('trading_end_min', 30)
    
    trading_start = time(trading_start_hour, trading_start_min)
    trading_end = time(trading_end_hour, trading_end_min)
    
    # Mark bars in trading window
    df['in_trading_window'] = (df['time'] >= trading_start) & (df['time'] < trading_end)
    
    return df


def detect_breakouts(df: pd.DataFrame, params: dict) -> pd.DataFrame:
    """
    Detect breakout signals when price breaks above resistance or below support.
    
    A valid breakout requires:
    1. Range is complete (range period has ended)
    2. Current bar is within Trading Window
    3. HIGH touches range_high+buffer (BUY) or LOW touches range_low-buffer (SELL)
    
    This simulates how the EA uses pending orders (Buy Stop / Sell Stop)
    that trigger when price touches the level, not when bar closes.
    
    Args:
        df: DataFrame with range_high, range_low, in_trading_window columns
        params: Strategy parameters
        
    Returns:
        DataFrame with added columns: signal (1=buy, -1=sell, 0=none)
    """
    df = df.copy()
    
    # Get buffer in MT5 points and convert to price units
    # 200 points in MT5 = 200 * 0.01 = 2.0 in price for US100
    buffer_points_mt5 = params.get('breakout_buffer_points', 200)
    buffer_price = points_to_price(buffer_points_mt5)
    
    # Initialize signal column
    df['signal'] = 0
    
    # Calculate breakout levels (in price units)
    df['buy_level'] = df['range_high'] + buffer_price
    df['sell_level'] = df['range_low'] - buffer_price
    
    # Track if we already had a breakout today (for debugging)
    df['prev_high'] = df['high'].shift(1)
    df['prev_low'] = df['low'].shift(1)
    
    # Buy signal: HIGH touches or exceeds buy_level (range_high + buffer)
    # This is how a Buy Stop pending order would trigger
    # Previous bar's high was below the level (first touch)
    buy_condition = (
        df['range_complete'] &
        df['in_trading_window'] &
        (df['high'] >= df['buy_level']) &
        (df['prev_high'] < df['buy_level'])
    )
    df.loc[buy_condition, 'signal'] = 1
    
    # Sell signal: LOW touches or drops below sell_level (range_low - buffer)
    # This is how a Sell Stop pending order would trigger
    sell_condition = (
        df['range_complete'] &
        df['in_trading_window'] &
        (df['low'] <= df['sell_level']) &
        (df['prev_low'] > df['sell_level'])
    )
    df.loc[sell_condition, 'signal'] = -1
    
    # Mark the breakout entry price (simulating pending order fill)
    # For BUY: entry at buy_level (pending order price)
    # For SELL: entry at sell_level
    df['entry_price'] = np.where(
        df['signal'] == 1, df['buy_level'],
        np.where(df['signal'] == -1, df['sell_level'], np.nan)
    )
    
    # Mark the breakout level for SL calculation
    df['breakout_level'] = np.where(
        df['signal'] == 1, df['range_high'],
        np.where(df['signal'] == -1, df['range_low'], np.nan)
    )
    
    return df


def apply_one_trade_per_day(df: pd.DataFrame) -> pd.DataFrame:
    """
    Ensure only one trade signal per day (first signal wins).
    """
    df = df.copy()
    
    # Mark first signal of each day
    df['signal_cumcount'] = df.groupby('date')['signal'].transform(
        lambda x: (x != 0).cumsum()
    )
    
    # Keep only first signal
    df.loc[(df['signal'] != 0) & (df['signal_cumcount'] > 1), 'signal'] = 0
    
    return df


def generate_signals(m15_data: pd.DataFrame, params: dict = None) -> pd.DataFrame:
    """
    Main function to generate trade signals from M15 data.
    
    Pipeline:
    1. Calculate daily range (support/resistance)
    2. Apply trading window filter
    3. Detect breakouts within trading window
    4. Limit to one trade per day
    
    Args:
        m15_data: M15 OHLC DataFrame
        params: Strategy parameters (uses DEFAULT_PARAMS if None)
        
    Returns:
        DataFrame with signals and all necessary trading info
    """
    if params is None:
        params = DEFAULT_PARAMS
    
    # Step 1: Calculate daily range
    df = calculate_daily_range(m15_data, params)
    
    # Step 2: Apply trading window
    df = apply_trading_window(df, params)
    
    # Step 3: Detect breakouts
    df = detect_breakouts(df, params)
    
    # Step 4: One trade per day
    df = apply_one_trade_per_day(df)
    
    return df


def calculate_sl_tp(df: pd.DataFrame, params: dict = None) -> pd.DataFrame:
    """
    Calculate Stop Loss and Take Profit levels for signals.
    
    IMPORTANT: Input parameters are in MT5 points (e.g., 5000 points = 50.0 price for US100)
    This function converts to PRICE units for actual trade management.
    
    SL Methods:
    - 'fixed': Fixed points (converted to price)
    - 'range_based': Based on range size with multiplier and min/max limits
    
    TP is always based on Risk:Reward ratio
    """
    if params is None:
        params = DEFAULT_PARAMS
    
    df = df.copy()
    
    # Initialize columns
    # sl_points/tp_points store MT5 POINTS (for reference)
    # sl_distance/tp_distance store PRICE distance (for calculations)
    # sl_price/tp_price store actual PRICE levels
    df['sl_points'] = np.nan      # MT5 points
    df['tp_points'] = np.nan      # MT5 points  
    df['sl_distance'] = np.nan    # Price distance
    df['tp_distance'] = np.nan    # Price distance
    df['sl_price'] = np.nan       # Actual price
    df['tp_price'] = np.nan       # Actual price
    
    # Only calculate for signals
    signal_mask = df['signal'] != 0
    
    sl_method = params.get('sl_method', 'fixed')
    
    if sl_method == 'fixed':
        # SL in MT5 points, convert to price
        sl_mt5_points = params.get('sl_fixed_points', 5000)
        sl_price_distance = points_to_price(sl_mt5_points)
        df.loc[signal_mask, 'sl_points'] = sl_mt5_points
        df.loc[signal_mask, 'sl_distance'] = sl_price_distance
        
    elif sl_method == 'range_based':
        # Range size is already in PRICE, use directly but respect min/max in MT5 points
        multiplier = params.get('sl_range_multiplier', 0.5)
        sl_price_distance = df['range_size'] * multiplier
        
        # Convert min/max from MT5 points to price
        sl_min_price = points_to_price(params.get('sl_min_points', 1000))
        sl_max_price = points_to_price(params.get('sl_max_points', 10000))
        sl_price_distance = sl_price_distance.clip(lower=sl_min_price, upper=sl_max_price)
        
        df.loc[signal_mask, 'sl_distance'] = sl_price_distance[signal_mask]
        # Store equivalent MT5 points for reference
        df.loc[signal_mask, 'sl_points'] = sl_price_distance[signal_mask] / FTMO_US100['point_size']
    
    # Calculate TP based on Risk:Reward
    rr = params.get('tp_risk_reward', 2.0)
    df.loc[signal_mask, 'tp_distance'] = df.loc[signal_mask, 'sl_distance'] * rr
    df.loc[signal_mask, 'tp_points'] = df.loc[signal_mask, 'sl_points'] * rr
    
    # Calculate actual price levels
    for idx in df[signal_mask].index:
        signal = df.loc[idx, 'signal']
        entry_price = df.loc[idx, 'close']  # Entry at close of signal bar
        sl_dist = df.loc[idx, 'sl_distance']
        tp_dist = df.loc[idx, 'tp_distance']
        
        if signal == 1:  # Buy
            df.loc[idx, 'sl_price'] = entry_price - sl_dist
            df.loc[idx, 'tp_price'] = entry_price + tp_dist
        else:  # Sell
            df.loc[idx, 'sl_price'] = entry_price + sl_dist
            df.loc[idx, 'tp_price'] = entry_price - tp_dist
    
    return df


# Test function
if __name__ == "__main__":
    # Create sample data for testing (multiple days with proper hours)
    import pandas as pd
    np.random.seed(42)
    
    # Create 5 days of M15 data
    dates = pd.date_range('2024-01-02 00:00', periods=5*24*4, freq='15min')
    price = 21000 + np.cumsum(np.random.randn(len(dates)) * 10)
    
    sample_data = pd.DataFrame({
        'datetime': dates,
        'open': price,
        'high': price + np.random.rand(len(dates)) * 50,
        'low': price - np.random.rand(len(dates)) * 50,
        'close': price + np.random.randn(len(dates)) * 20,
        'tick_volume': np.random.randint(100, 1000, len(dates))
    })
    
    print("=== Testing Range Breaker Logic ===")
    print(f"Total bars: {len(sample_data)}")
    print(f"Date range: {sample_data['datetime'].min()} to {sample_data['datetime'].max()}")
    
    # Test with default params
    test_params = {
        'range_start_hour': 12,
        'range_start_min': 0,
        'range_end_hour': 14,
        'range_end_min': 0,
        'trading_start_hour': 14,
        'trading_start_min': 30,
        'trading_end_hour': 17,
        'trading_end_min': 0,
        'breakout_buffer_points': 20,
        'sl_method': 'fixed',
        'sl_fixed_points': 5000,
        'tp_risk_reward': 2.0
    }
    
    # Generate signals
    signals = generate_signals(sample_data, test_params)
    signals = calculate_sl_tp(signals, test_params)
    
    signal_count = (signals['signal'] != 0).sum()
    print(f"\nSignals generated: {signal_count}")
    
    # Show signal bars
    signal_bars = signals[signals['signal'] != 0]
    if len(signal_bars) > 0:
        print("\nSignal bars:")
        print(signal_bars[['datetime', 'close', 'range_high', 'range_low', 'signal', 'sl_points']].head(10))
    else:
        print("\nNo signals generated.")
        
        # Debug: show trading window bars
        tw_bars = signals[signals['in_trading_window'] == True]
        print(f"\nBars in trading window: {len(tw_bars)}")
        
        # Show range info for a few days
        print("\nRange data sample:")
        range_bars = signals[signals['range_complete'] == True].groupby('date').first()
        print(range_bars[['range_high', 'range_low', 'range_size']].head())
