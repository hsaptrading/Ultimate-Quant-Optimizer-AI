"""
Parameter Space Configuration - Based on MT5 Optimizer Settings

This file defines the exact parameters and ranges extracted from the user's
MT5 optimization configuration screenshots.

Format for each parameter:
- 'param_name': [list of values to test]
  OR
- 'param_name': {'start': X, 'step': Y, 'stop': Z}
  which gets converted to a range
"""

import numpy as np

def generate_range(start, stop, step):
    """Generate values from start to stop with given step."""
    if step == 0:
        return [start]
    values = []
    current = start
    while current <= stop:
        values.append(round(current, 4))
        current += step
    return values


# ============================================================
# PARAMETERS TO OPTIMIZE (Based on MT5 Screenshots)
# ============================================================

# --- RANGE SCHEDULE ---
# Range Start Hour: Start=12, Stop=14, Step=1
RANGE_START_HOUR = generate_range(12, 14, 1)  # [12, 13, 14]

# Range End Hour: Start=15, Stop=18, Step=1  
RANGE_END_HOUR = generate_range(15, 18, 1)    # [15, 16, 17, 18]

# --- TRADING WINDOW (KILL ZONE) ---
# Trading Start Hour: Start=15, Stop=17, Step=1
TRADING_START_HOUR = generate_range(15, 17, 1)  # [15, 16, 17]

# Trading Start Minute: Values 0, 30
TRADING_START_MIN = [0, 30]

# Trading End Hour: [17, 18, 19]
TRADING_END_HOUR = generate_range(17, 19, 1)

# --- EXECUTION & BREAKOUT ---
# Breakout Buffer: Start=100, Stop=500, Step=200 (approximated)
BREAKOUT_BUFFER_POINTS = [100, 200, 300, 500]

# Min Body Percent: Start=25, Stop=100, Step=25
MIN_BODY_PERCENT = generate_range(25, 100, 25)  # [25, 50, 75, 100]

# --- RISK MANAGEMENT ---
# Risk Per Trade %: Start=0.5, Stop=2.0, Step=0.5
RISK_PERCENT = generate_range(0.5, 2.0, 0.5)  # [0.5, 1.0, 1.5, 2.0]

# Stop Loss Method: Fixed Points, Range Based
SL_METHOD = ['fixed', 'range_based']

# Fixed SL: Start=2000, Stop=9000, Step=1000 (approximated)
FIXED_SL_POINTS = generate_range(2000, 9000, 1000)

# Range Multiplier for SL: Start=0.2, Stop=1.5, Step=0.3 (approximated)
SL_RANGE_MULTIPLIER = [0.2, 0.5, 0.8, 1.0, 1.2, 1.5]

# Range SL Min: Start=200, Stop=5000, Step varied
SL_RANGE_MIN = [200, 500, 1000, 2000, 3000, 5000]

# Range SL Max: Start=10000, Stop=50000
SL_RANGE_MAX = [10000, 20000, 30000, 50000]

# Risk:Reward Ratio: Start=1, Stop=8, Step=1
TP_RISK_REWARD = generate_range(1.0, 8.0, 1.0)  # [1, 2, 3, 4, 5, 6, 7, 8]

# --- BREAKEVEN & TRAILING STOP ---
# Exit Strategy Mode
EXIT_STRATEGY = ['off', 'breakeven', 'trailing_points', 'trailing_atr']

# Breakeven Trigger: Start=100, Stop=10000, varied
BREAKEVEN_TRIGGER = [100, 500, 1000, 2000, 3000, 5000, 10000]

# Breakeven Offset: Start=50, Stop=1000
BREAKEVEN_OFFSET = [50, 100, 200, 300, 500, 1000]

# Trailing Start: Start=500, Stop=10000
TRAILING_START = [500, 1000, 2000, 3000, 5000, 7000, 10000]

# Trailing Step: Start=500, Stop=5000
TRAILING_STEP = [500, 1000, 1500, 2000, 3000, 5000]

# --- MARKET ACTIVITY FILTER ---
USE_ACTIVITY_FILTER = [True, False]
ACTIVITY_VOLUME_PERIOD = generate_range(10, 30, 5)  # [10, 15, 20, 25, 30]
MIN_ACTIVITY_MULTIPLE = [0.8, 1.0, 1.2, 1.5, 2.0]

# --- ADX TREND FILTER ---
ADX_MODE = ['off', 'strong_only']
ADX_PERIOD = generate_range(5, 20, 5)  # [5, 10, 15, 20]
ADX_THRESHOLD = generate_range(20, 50, 5)  # [20, 25, 30, 35, 40, 45, 50]

# --- RSI CONFIRM FILTER ---
RSI_MODE = ['off', 'confirm_50']
RSI_PERIOD = generate_range(5, 20, 5)  # [5, 10, 15, 20]
RSI_CONFIRM_LEVEL = generate_range(40, 60, 5)  # [40, 45, 50, 55, 60]


# ============================================================
# PARAM_SPACE - The actual optimization space
# ============================================================

PARAM_SPACE = {
    # --- CORE RANGE SETTINGS ---
    'range_start_hour': RANGE_START_HOUR,
    'range_end_hour': RANGE_END_HOUR,
    
    # --- TRADING WINDOW ---
    'trading_start_hour': TRADING_START_HOUR,
    'trading_start_min': TRADING_START_MIN,
    'trading_end_hour': TRADING_END_HOUR,
    
    # --- BREAKOUT ---
    'breakout_buffer_points': BREAKOUT_BUFFER_POINTS,
    
    # --- RISK MANAGEMENT ---
    'risk_percent': RISK_PERCENT,
    'sl_method': SL_METHOD,
    'sl_fixed_points': FIXED_SL_POINTS,
    'sl_range_multiplier': SL_RANGE_MULTIPLIER,
    'sl_min_points': SL_RANGE_MIN,
    'sl_max_points': SL_RANGE_MAX,
    'tp_risk_reward': TP_RISK_REWARD,
    
    # --- EXIT STRATEGY ---
    'exit_strategy': EXIT_STRATEGY,
    'breakeven_trigger_points': BREAKEVEN_TRIGGER,
    'breakeven_offset_points': BREAKEVEN_OFFSET,
    'trailing_start_points': TRAILING_START,
    'trailing_step_points': TRAILING_STEP,
    
    # --- FILTERS ---
    'use_activity_filter': USE_ACTIVITY_FILTER,
    'activity_volume_period': ACTIVITY_VOLUME_PERIOD,
    'min_activity_multiple': MIN_ACTIVITY_MULTIPLE,
    
    'adx_mode': ADX_MODE,
    'adx_period': ADX_PERIOD,
    'adx_threshold': ADX_THRESHOLD,
    
    'rsi_mode': RSI_MODE,
    'rsi_period': RSI_PERIOD,
    'rsi_confirm_level': RSI_CONFIRM_LEVEL,
}


# Calculate total possible combinations (for grid search)
def calc_total_combinations():
    total = 1
    for key, values in PARAM_SPACE.items():
        total *= len(values)
    return total


# ============================================================
# REDUCED PARAM SPACE - For faster initial testing
# Focus on parameters that generate more signals
# ============================================================

PARAM_SPACE_REDUCED = {
    # --- RANGE TIMING (Fixed for now to generate signals) ---
    'range_start_hour': [12],           # Fixed: 12:00-16:00 range
    'range_end_hour': [16],
    
    # --- TRADING WINDOW (Wider = more signals) ---
    'trading_start_hour': [16, 17],     # 16:00 or 17:00
    'trading_end_hour': [20, 21],       # 20:00 or 21:00
    
    # --- BREAKOUT (Smaller = more signals) ---
    'breakout_buffer_points': [30, 50, 100],
    
    # --- RISK MANAGEMENT ---
    'risk_percent': [0.5, 1.0, 1.5],
    'sl_method': ['fixed', 'range_based'],
    'sl_fixed_points': [3000, 5000, 7000],
    'sl_range_multiplier': [0.5, 1.0, 1.5],
    'sl_min_points': [1000, 2000],
    'sl_max_points': [8000, 12000],
    'tp_risk_reward': [1.5, 2.0, 2.5, 3.0],
    
    # --- EXIT STRATEGY ---
    'exit_strategy': ['off', 'trailing_points'],
    'trailing_start_points': [2000, 3000, 5000],
    'trailing_step_points': [1000, 2000],
    
    # --- FILTERS (OFF for initial testing) ---
    'use_activity_filter': [False],
    'adx_mode': ['off'],
    'rsi_mode': ['off'],
}


if __name__ == "__main__":
    print("Parameter Space Configuration")
    print("="*50)
    
    print("\nFull Parameter Space:")
    for key, values in PARAM_SPACE.items():
        print(f"  {key}: {len(values)} values")
    
    total = calc_total_combinations()
    print(f"\nTotal combinations (grid): {total:,}")
    print(f"Estimated time @ 1sec/combo: {total/3600:.1f} hours")
    
    print("\n" + "="*50)
    print("Reduced Parameter Space:")
    reduced_total = 1
    for key, values in PARAM_SPACE_REDUCED.items():
        reduced_total *= len(values)
        print(f"  {key}: {len(values)} values")
    
    print(f"\nReduced combinations: {reduced_total:,}")
    print(f"Estimated time @ 1sec/combo: {reduced_total/60:.1f} minutes")
