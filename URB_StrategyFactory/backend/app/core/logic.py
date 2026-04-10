
import numpy as np
from numba import jit

@jit(nopython=True)
def calculate_daily_ranges(
    times: np.ndarray,      # timestamps (int64) - MILLISECONDS
    highs: np.ndarray,
    lows: np.ndarray,
    start_hour: int,
    start_min: int,
    end_hour: int,
    end_min: int
):
    """
    Calculates ranges. Assumes timestamps are MILLISECONDS (13 digits).
    """
    n = len(times)
    range_highs = np.zeros(n)
    range_lows = np.zeros(n)
    
    start_minutes_of_day = start_hour * 60 + start_min
    end_minutes_of_day = end_hour * 60 + end_min
    
    ms_per_min = 60000
    ms_per_day = 86400000
    
    last_day_ts = 0
    temp_h = -1.0
    temp_l = 999999.0
    range_established = False
    
    for i in range(n):
        t = times[i]
        day_ts = t - (t % ms_per_day)
        
        if day_ts != last_day_ts:
            last_day_ts = day_ts
            temp_h = -1.0
            temp_l = 999999.0
            range_established = False
            
        minutes_of_day = (t % ms_per_day) // ms_per_min
        
        if minutes_of_day >= start_minutes_of_day and minutes_of_day < end_minutes_of_day:
            if highs[i] > temp_h: temp_h = highs[i]
            if lows[i] < temp_l: temp_l = lows[i]
            
        if minutes_of_day >= end_minutes_of_day and not range_established:
             if temp_h > 0.0 and temp_l < 999999.0:
                 range_established = True
                 
        if range_established:
            range_highs[i] = temp_h
            range_lows[i] = temp_l
            
    return range_highs, range_lows

@jit(nopython=True)
def backtest_core(
    # --- Data Arrays (Aligned) ---
    ids: np.ndarray,
    times: np.ndarray,
    opens: np.ndarray,
    highs: np.ndarray,
    lows: np.ndarray,
    closes: np.ndarray,
    spreads: np.ndarray,
    
    # --- Pre-Calculated Indicators ---
    range_highs: np.ndarray, # 0 if invalid
    range_lows: np.ndarray,  # 999999 if invalid
    atr_arr: np.ndarray,     # ATR for SL/Trailing
    adx_arr: np.ndarray,     # ADX for Filter
    rsi_arr: np.ndarray,     # RSI for Filter
    
    # --- General Settings ---
    trading_start_h: int,
    trading_start_m: int,
    trading_end_h: int,
    trading_end_m: int,
    trade_direction: int,    # 0=BuyOnly, 1=SellOnly, 2=Both
    
    # --- Entry & Breakout ---
    breakout_buffer: float,  # Points
    min_dist_between_trades: float, # Points
    
    # --- Risk Management ---
    fixed_lot: float,
    risk_percent: float,     # NOT IMPLEMENTED FULLY (Complex Balance math), using Fixed Lot for speed optimization or simple calc
    sl_method: int,          # 0=Fixed, 1=ATR
    fixed_sl_points: float,
    atr_sl_period: int,      # (Unused here, assume atr_arr passed is correct period)
    atr_sl_multiplier: float,
    risk_reward_ratio: float, # For TP calculation
    
    # --- Trailing / Exit ---
    exit_mode: int,          # 0=Off, 1=BE, 2=TrailPoints, 3=TrailATR
    breakeven_trigger: float,
    breakeven_offset: float,
    trailing_start: float,
    trailing_step: float,
    atr_trailing_mult: float,
    
    # --- Filters ---
    use_adx: bool,
    adx_threshold: float,    # If ADX > Threshold (Trend) or < Thresh (Range)? URB usually checks Strength.
    use_rsi: bool,
    rsi_lower: float,
    rsi_upper: float,
    
    # --- Broker Costs ---
    commission_per_lot: float, 
    swap_long: float, 
    swap_short: float
):
    n = len(times)
    equity_curve = np.zeros(n)
    
    current_equity = 100000.0 
    
    # Position State
    pos_type = 0 # 0=None, 1=Buy, -1=Sell
    entry_price = 0.0
    sl_price = 0.0
    tp_price = 0.0
    entry_time = 0
    highest_price = 0.0 # For Trailing Buy
    lowest_price = 0.0  # For Trailing Sell
    
    # Metrics
    wins = 0
    losses = 0
    trades_count = 0
    
    ms_per_min = 60000
    ms_per_day = 86400000
    
    trade_start_min = trading_start_h * 60 + trading_start_m
    trade_end_min = trading_end_h * 60 + trading_end_m
    
    # Helper to check if time is within trading window
    # Handles wrapping over midnight
    def is_in_window(mins, start, end):
        if start < end:
            return mins >= start and mins < end
        else: # Wraps midnight
            return mins >= start or mins < end

    for i in range(n):
        equity_curve[i] = current_equity
        t = times[i]
        minutes_of_day = (t % ms_per_day) // ms_per_min
        
        # --- SWAP & OVERNIGHT ---
        # (Simplified: Appyling swap on new day detection)
        if pos_type != 0 and i > 0:
            if (t // ms_per_day) > (times[i-1] // ms_per_day):
                s = swap_long if pos_type == 1 else swap_short
                current_equity += (s * fixed_lot)

        # --- EXIT LOGIC (SL / TP / Trailing) ---
        if pos_type != 0:
            closed = False
            profit = 0.0
            
            # 1. Check SL/TP Hit on current bar High/Low
            if pos_type == 1:
                # Check SL
                if lows[i] <= sl_price:
                    profit = (sl_price - entry_price) * fixed_lot # Loss
                    current_equity += profit
                    losses += 1
                    closed = True
                # Check TP
                elif highs[i] >= tp_price:
                    profit = (tp_price - entry_price) * fixed_lot
                    current_equity += profit
                    wins += 1
                    closed = True
                else:
                    # Update Trailing / Breakeven
                    if highs[i] > highest_price: highest_price = highs[i]
                    
                    # Breakeven
                    if exit_mode == 1: 
                        if (highest_price - entry_price) >= breakeven_trigger:
                            new_sl = entry_price + breakeven_offset
                            if new_sl > sl_price: sl_price = new_sl
                    
                    # Trailing Points
                    elif exit_mode == 2:
                        if (highest_price - entry_price) >= trailing_start:
                            # Start trailing
                            dist_from_max = trailing_step # Simple step logic? Or max - step?
                            # Standard TS: SL = Highest - Step? No, usually SL moves up.
                            # Standard: SL = Highest - TrailingStep (Distance)
                            # URB Logic: "Start" triggers, then maintain distance "Step" (or typical trailing distance)
                            new_sl = highest_price - trailing_step 
                            if new_sl > sl_price: sl_price = new_sl

                    # Trailing ATR
                    elif exit_mode == 3:
                         if (highest_price - entry_price) >= (atr_arr[i] * atr_trailing_mult):
                             new_sl = highest_price - (atr_arr[i] * atr_trailing_mult)
                             if new_sl > sl_price: sl_price = new_sl

            elif pos_type == -1:
                # Check SL
                if highs[i] >= sl_price:
                    profit = (entry_price - sl_price) * fixed_lot # Loss (negative result)
                    current_equity += profit 
                    losses += 1
                    closed = True
                # Check TP
                elif lows[i] <= tp_price:
                    profit = (entry_price - tp_price) * fixed_lot
                    current_equity += profit
                    wins += 1
                    closed = True
                else:
                    if lows[i] < lowest_price: lowest_price = lows[i]
                    
                    if exit_mode == 1:
                         if (entry_price - lowest_price) >= breakeven_trigger:
                             new_sl = entry_price - breakeven_offset
                             if new_sl < sl_price: sl_price = new_sl
                    
                    elif exit_mode == 2:
                        if (entry_price - lowest_price) >= trailing_start:
                            new_sl = lowest_price + trailing_step
                            if new_sl < sl_price: sl_price = new_sl
                            
                    elif exit_mode == 3:
                        if (entry_price - lowest_price) >= (atr_arr[i] * atr_trailing_mult):
                            new_sl = lowest_price + (atr_arr[i] * atr_trailing_mult)
                            if new_sl < sl_price: sl_price = new_sl

            if closed:
                pos_type = 0
                trades_count += 1
                continue # Skip entry on same bar

        # --- ENTRY LOGIC ---
        # Only if no position (Single Trade Mode)
        # Check Trading Window
        if pos_type == 0 and range_highs[i] > 0 and range_lows[i] < 999999:
           
            if is_in_window(minutes_of_day, trade_start_min, trade_end_min):
                
                # Check Filters
                # 1. ADX
                valid_filter = True
                if use_adx:
                    if adx_arr[i] < adx_threshold: valid_filter = False
                
                # 2. RSI
                if use_rsi and valid_filter:
                    # Logic: Confirm Check.
                    # Buy: RSI > 50? Sell: RSI < 50?
                    # URB MQ5: Confirm Mode -> Buy if RSI > Confirm(50).
                    mid_level = 50.0 
                    # If we are looking for Buy, check RSI > 50
                    # If Sell, check RSI < 50
                    # We don't know direction yet, we check on signal?
                    # Let's defer strict check to signal generation.
                    pass 

                if valid_filter:
                    # Breakout Logic
                    r_high = range_highs[i]
                    r_low = range_lows[i]
                    
                    buy_level = r_high + breakout_buffer
                    sell_level = r_low - breakout_buffer
                    
                    # Direction Check
                    can_buy = (trade_direction == 0 or trade_direction == 2)
                    can_sell = (trade_direction == 1 or trade_direction == 2)
                    
                    # BUY SIGNAL
                    if can_buy and highs[i] >= buy_level and lows[i] < buy_level: # Crossed up
                        # Filter Check for BUY
                        if use_rsi and rsi_arr[i] < 50.0: pass # Filtered
                        else:
                            pos_type = 1
                            entry_price = buy_level
                            
                            # SL Calculation
                            sl_dist = 0.0
                            if sl_method == 0: # Fixed
                                sl_dist = fixed_sl_points
                            elif sl_method == 1: # ATR
                                sl_dist = atr_arr[i] * atr_sl_multiplier
                                # Safety fallback logic from EA?
                            
                            sl_price = entry_price - sl_dist
                            
                            # TP Calculation
                            # TP = SL * Ratio
                            tp_dist = sl_dist * risk_reward_ratio
                            tp_price = entry_price + tp_dist
                            
                            current_equity -= (spreads[i] * fixed_lot + commission_per_lot * fixed_lot)
                            entry_time = t
                            highest_price = entry_price

                    # SELL SIGNAL
                    elif can_sell and lows[i] <= sell_level and highs[i] > sell_level: # Crossed down
                        # Filter Check for SELL
                        if use_rsi and rsi_arr[i] > 50.0: pass # Filtered
                        else:
                            pos_type = -1
                            entry_price = sell_level
                            
                            sl_dist = 0.0
                            if sl_method == 0: sl_dist = fixed_sl_points
                            elif sl_method == 1: sl_dist = atr_arr[i] * atr_sl_multiplier
                            
                            sl_price = entry_price + sl_dist
                            tp_dist = sl_dist * risk_reward_ratio
                            tp_price = entry_price - tp_dist
                            
                            current_equity -= (spreads[i] * fixed_lot + commission_per_lot * fixed_lot)
                            entry_time = t
                            lowest_price = entry_price

    return current_equity, wins, losses, equity_curve
