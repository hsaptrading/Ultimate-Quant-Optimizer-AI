
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
    ids: np.ndarray,
    times: np.ndarray,
    opens: np.ndarray,
    highs: np.ndarray,
    lows: np.ndarray,
    closes: np.ndarray,
    range_highs: np.ndarray,
    range_lows: np.ndarray,
    spreads: np.ndarray,
    
    # --- New Indicator Arrays (Pre-Calculated) ---
    adx_arr: np.ndarray,
    rsi_arr: np.ndarray,
    
    # --- Strategy Params ---
    trading_start_h: int,
    trading_start_m: int,
    trading_end_h: int,
    trading_end_m: int,
    buffer_points: float, 
    sl_points: float,
    tp_points: float,
    
    # --- Filters ---
    use_adx: bool,
    adx_threshold: float,
    use_rsi: bool,
    rsi_upper: float,
    rsi_lower: float,
    
    # --- Broker Costs ---
    commission_per_lot: float, # Round trip per lot (e.g. 7.0)
    swap_long: float, # Swap points per day (usually negative)
    swap_short: float
):
    n = len(times)
    equity_curve = np.zeros(n)
    
    trades_count = 0
    wins = 0
    losses = 0
    current_equity = 100000.0 
    
    position = 0 # 0=None, 1=Buy, -1=Sell
    entry_price = 0.0
    sl_price = 0.0
    tp_price = 0.0
    entry_time = 0
    
    ms_per_min = 60000
    ms_per_day = 86400000
    
    trade_start_min = trading_start_h * 60 + trading_start_m
    trade_end_min = trading_end_h * 60 + trading_end_m
    
    fixed_lot = 0.1 # Fixed lot for testing
    
    # Commission Calculation: 
    # Comm = CommPerLot * Lots
    # We apply it on Entry.
    comm_cost = commission_per_lot * fixed_lot
    
    for i in range(n):
        equity_curve[i] = current_equity
        
        t = times[i]
        minutes_of_day = (t % ms_per_day) // ms_per_min
        
        r_high = range_highs[i]
        r_low = range_lows[i]
        
        # --- SWAP LOGIC (Simple Daily Check) ---
        if position != 0:
            # Check if new day started since last bar? 
            # Or just check if time crosses 00:00?
            # Easiest: If (t // ms_per_day) > (prev_t // ms_per_day)
            if i > 0:
                prev_day = times[i-1] // ms_per_day
                curr_day = t // ms_per_day
                if curr_day > prev_day:
                    # Apply Swap
                    # Swap is in POINTS usually or MONEY? 
                    # MT5 swap can be money or points. Let's assume Points.
                    # Points -> Money: Points * PointValue * Lots
                    # Assuming NASDAQ PointValue=1.0 (approx) for simplified test.
                    if position == 1:
                        current_equity += (swap_long * fixed_lot)
                    else:
                        current_equity += (swap_short * fixed_lot)

        # --- EXIT LOGIC ---
        if position != 0:
            if position == 1: # Long
                if lows[i] <= sl_price:
                    loss = (sl_price - entry_price) * fixed_lot # Convert points to money (approx)
                    # Real simulation needs TickValue. Assuming 1.0 per point per 1.0 lot? 
                    # US100: 1 lot, 1 point move = $1 profit? Or $20?
                    # WARNING: Point Value is critical. 
                    # Assuming standard contract: 1.0 point = 1.0 USD per lot? No.
                    # US100 usually: 1.0 lot = $20 per point. Or 1.0 lot = $1 per point (micro).
                    # Since we don't know contract size, we track POINTS PROFIT.
                    # Let's return NET POINTS for robustness.
                    
                    # BUT Equity needs Money for drawdown calc.
                    # Let's ASSUME 1 Point = $1 for simplicity (Normalized)
                    
                    current_equity += (loss * 1.0) 
                    position = 0
                    losses += 1
                elif highs[i] >= tp_price:
                    profit = (tp_price - entry_price) * fixed_lot
                    current_equity += (profit * 1.0)
                    position = 0
                    wins += 1
                    
            elif position == -1: # Short
                if highs[i] >= sl_price:
                    loss_pts = (entry_price - sl_price) # Negative
                    current_equity += (loss_pts * fixed_lot * 1.0)
                    position = 0
                    losses += 1
                elif lows[i] <= tp_price:
                    prof_pts = (entry_price - tp_price)
                    current_equity += (prof_pts * fixed_lot * 1.0)
                    position = 0
                    wins += 1

        # --- ENTRY LOGIC ---
        if position == 0 and r_high > 0 and r_low > 0:
            # Time Window
            is_trading_window = False
            if trade_end_min > trade_start_min:
                if minutes_of_day >= trade_start_min and minutes_of_day < trade_end_min:
                    is_trading_window = True
            else:
                if minutes_of_day >= trade_start_min or minutes_of_day < trade_end_min:
                    is_trading_window = True
            
            # --- FILTERS ---
            if is_trading_window:
                # ADX Filter
                if use_adx:
                    # EA Logic: If ADX > Level -> Trend Follow? Or ADX < 25 -> Ranging?
                    # The EA has "ADX Trend Mode". Usually means "Trade only if ADX > Level".
                    # Access pre-calc array
                    if adx_arr[i] < adx_threshold:
                        is_trading_window = False
                
                # RSI Filter
                if use_rsi and is_trading_window:
                    # EA Logic: "RSI Confirm Mode".
                    # Buy only if RSI < Upper? Or RSI > 50?
                    # Common Range Breakout: 
                    # Buy if RSI > 50 (Trend Confirm) OR RSI < 70 (Not Overbought).
                    # Let's assume standard "Range Breaker":
                    # Buy if RSI > 50. Sell if RSI < 50.
                    # Or simpler: Filter extreme Overbought/Oversold.
                    # Buy: RSI < Upper (70). Sell: RSI > Lower (30).
                    pass # Simplified for now, just checking the logic skeleton
            
            if is_trading_window:
                buy_level = r_high + buffer_points
                sell_level = r_low - buffer_points
                spread = spreads[i]
                
                if highs[i] >= buy_level and lows[i] < buy_level: 
                    position = 1
                    entry_price = buy_level
                    sl_price = buy_level - sl_points
                    tp_price = buy_level + tp_points
                    entry_time = t
                    
                    # Deduct Spread + Commission (Points equivalent)
                    # Comm Cost $7 per lot. On 0.1 lot = $0.70.
                    # If 1 point = $0.10 (0.1 lot * $1), then $0.70 is 7 points.
                    # We need precise Point Value.
                    # For now: Deduct RAW Spread + Fixed Commission Points (e.g. 2 pts)
                    
                    cost_points = spread + (comm_cost / fixed_lot) # approx
                    current_equity -= (cost_points * fixed_lot)
                    
                elif lows[i] <= sell_level and highs[i] > sell_level:
                    position = -1
                    entry_price = sell_level
                    sl_price = sell_level + sl_points
                    tp_price = sell_level - tp_points
                    entry_time = t
                    
                    cost_points = spread + (comm_cost / fixed_lot)
                    current_equity -= (cost_points * fixed_lot)

    return current_equity, wins, losses, equity_curve
