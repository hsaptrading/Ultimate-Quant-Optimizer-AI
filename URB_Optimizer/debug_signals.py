"""Quick diagnostic script to analyze signal generation"""
import pandas as pd
import sys
sys.path.insert(0, '.')
from src.data_loader import create_m15_data
from src.range_breaker import calculate_daily_range, apply_trading_window, detect_breakouts
from config.broker_config import DEFAULT_PARAMS

print("Loading data from cache...")
m15 = create_m15_data('data/USATECHIDXUSD.tick.utc2.csv', use_cache=True)
print(f'Total bars: {len(m15)}')
print(f'Date range: {m15["datetime"].min()} to {m15["datetime"].max()}')

# Count unique days
unique_days = m15['datetime'].dt.date.nunique()
print(f'Unique trading days: {unique_days}')

# Test with WIDER trading window
test_params = {
    'range_start_hour': 12,
    'range_start_min': 0,
    'range_end_hour': 16,
    'range_end_min': 0,
    'trading_start_hour': 16,
    'trading_start_min': 0,
    'trading_end_hour': 21,  # Wider window
    'trading_end_min': 0,
    'breakout_buffer_points': 50  # Smaller buffer
}

print("\n--- Testing with WIDER trading window (16:00 - 21:00) ---")
df = calculate_daily_range(m15, test_params)
df = apply_trading_window(df, test_params)

# Count bars in trading window
tw_bars = df[df['in_trading_window'] == True]
print(f'Bars in trading window: {len(tw_bars)}')

# Check range data
range_complete = df[df['range_complete'] == True]
print(f'Bars with range complete: {len(range_complete)}')

# Check how many days have valid ranges
days_with_range = df[df['range_size'].notna()]['date'].nunique()
print(f'Days with valid range: {days_with_range}')

# Detect breakouts
df2 = detect_breakouts(df, test_params)
signals = df2[df2['signal'] != 0]
print(f'\nSignals generated: {len(signals)}')
print(f'  Buy signals: {(signals["signal"] == 1).sum()}')
print(f'  Sell signals: {(signals["signal"] == -1).sum()}')

if len(signals) > 0:
    print("\nSample signals:")
    print(signals[['datetime', 'close', 'range_high', 'range_low', 'signal']].head(10))

# Show a sample day
print("\n--- Sample day data ---")
sample_date = df['date'].dropna().iloc[500]
day_df = df[df['date'] == sample_date]
print(f"Day: {sample_date}")
print(f"  Range period bars: {(day_df['in_range'] == True).sum()}")
print(f"  Trading window bars: {(day_df['in_trading_window'] == True).sum()}")
if day_df['range_high'].notna().any():
    print(f"  Range high: {day_df['range_high'].dropna().iloc[0]:.2f}")
    print(f"  Range low: {day_df['range_low'].dropna().iloc[0]:.2f}")
    print(f"  Range size: {day_df['range_size'].dropna().iloc[0]:.2f}")
