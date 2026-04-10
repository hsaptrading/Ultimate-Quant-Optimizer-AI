
import numpy as np
from numba import jit
from .base import BaseStrategy
from ..core.logic import calculate_daily_ranges

# --- JIT Compiled Core Logic ---
# Must be standalone function to be Numba compatible (cannot be class method easily)
@jit(nopython=True)
def urb_backtest_core(
    # Data
    times, opens, highs, lows, closes, spreads,
    # Indicators
    range_highs, range_lows, atr_arr, adx_arr, rsi_arr,
    # Params
    trading_start_h, trading_start_m, trading_end_h, trading_end_m, trade_direction,
    breakout_buffer, fixed_lot, sl_method, fixed_sl_points, atr_sl_multiplier, risk_reward_ratio,
    exit_mode, breakeven_trigger, breakeven_offset, trailing_start, trailing_step, atr_trailing_mult,
    use_adx, adx_threshold, use_rsi,
    commission_per_lot, swap_long, swap_short
):
    n = len(times)
    equity_curve = np.zeros(n)
    current_equity = 100000.0 
    
    pos_type = 0 # 0=None, 1=Buy, -1=Sell
    entry_price = 0.0
    sl_price = 0.0
    tp_price = 0.0
    highest_price = 0.0 
    lowest_price = 0.0
    
    wins = 0
    losses = 0
    
    ms_per_min = 60000
    ms_per_day = 86400000
    
    trade_start_min = trading_start_h * 60 + trading_start_m
    trade_end_min = trading_end_h * 60 + trading_end_m
    
    for i in range(n):
        equity_curve[i] = current_equity
        t = times[i]
        minutes_of_day = (t % ms_per_day) // ms_per_min
        
        # --- SWAP ---
        if pos_type != 0 and i > 0:
            if (t // ms_per_day) > (times[i-1] // ms_per_day):
                s = swap_long if pos_type == 1 else swap_short
                current_equity += (s * fixed_lot)

        # --- EXIT ---
        if pos_type != 0:
            closed = False
            profit = 0.0
            
            # Buy Exit
            if pos_type == 1:
                # SL
                if lows[i] <= sl_price:
                    profit = (sl_price - entry_price) * fixed_lot
                    current_equity += profit
                    losses += 1
                    closed = True
                # TP
                elif highs[i] >= tp_price:
                    profit = (tp_price - entry_price) * fixed_lot
                    current_equity += profit
                    wins += 1
                    closed = True
                else:
                    # Trailing
                    if highs[i] > highest_price: highest_price = highs[i]
                    
                    if exit_mode == 1: # BE
                        if (highest_price - entry_price) >= breakeven_trigger:
                            new_sl = entry_price + breakeven_offset
                            if new_sl > sl_price: sl_price = new_sl
                    elif exit_mode == 2: # Trail Points
                        if (highest_price - entry_price) >= trailing_start:
                            new_sl = highest_price - trailing_step 
                            if new_sl > sl_price: sl_price = new_sl
                    elif exit_mode == 3: # Trail ATR
                         if (highest_price - entry_price) >= (atr_arr[i] * atr_trailing_mult):
                             new_sl = highest_price - (atr_arr[i] * atr_trailing_mult)
                             if new_sl > sl_price: sl_price = new_sl

            # Sell Exit
            elif pos_type == -1:
                # SL
                if highs[i] >= sl_price:
                    profit = (entry_price - sl_price) * fixed_lot
                    current_equity += profit
                    losses += 1
                    closed = True
                # TP
                elif lows[i] <= tp_price:
                    profit = (entry_price - tp_price) * fixed_lot
                    current_equity += profit
                    wins += 1
                    closed = True
                else:
                    # Trailing
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
                continue 

        # --- ENTRY ---
        # Helper for time window
        in_window = False
        if trade_start_min < trade_end_min:
            in_window = (minutes_of_day >= trade_start_min and minutes_of_day < trade_end_min)
        else:
            in_window = (minutes_of_day >= trade_start_min or minutes_of_day < trade_end_min)

        if pos_type == 0 and range_highs[i] > 0 and range_lows[i] < 999999 and in_window:
            
            # Filters
            valid_filter = True
            if use_adx:
                if adx_arr[i] < adx_threshold: valid_filter = False
            
            if valid_filter:
                r_high = range_highs[i]
                r_low = range_lows[i]
                buy_level = r_high + breakout_buffer
                sell_level = r_low - breakout_buffer
                
                can_buy = (trade_direction == 0 or trade_direction == 2)
                can_sell = (trade_direction == 1 or trade_direction == 2)
                
                # Buy
                if can_buy and highs[i] >= buy_level and lows[i] < buy_level:
                    if not (use_rsi and rsi_arr[i] < 50.0):
                        pos_type = 1
                        entry_price = buy_level
                        highest_price = entry_price
                        
                        sl_dist = fixed_sl_points
                        if sl_method == 1: sl_dist = atr_arr[i] * atr_sl_multiplier
                        
                        sl_price = entry_price - sl_dist
                        tp_price = entry_price + (sl_dist * risk_reward_ratio)
                        
                        current_equity -= (spreads[i] * fixed_lot + commission_per_lot * fixed_lot)

                # Sell
                elif can_sell and lows[i] <= sell_level and highs[i] > sell_level:
                    if not (use_rsi and rsi_arr[i] > 50.0):
                        pos_type = -1
                        entry_price = sell_level
                        lowest_price = entry_price
                        
                        sl_dist = fixed_sl_points
                        if sl_method == 1: sl_dist = atr_arr[i] * atr_sl_multiplier
                        
                        sl_price = entry_price + sl_dist
                        tp_price = entry_price - (sl_dist * risk_reward_ratio)
                        
                        current_equity -= (spreads[i] * fixed_lot + commission_per_lot * fixed_lot)

    return current_equity, wins, losses, equity_curve


class URBKillzoneStrategy(BaseStrategy):
    @property
    def name(self) -> str:
        return "urb_killzone"

    @property
    def display_name(self) -> str:
        return "URB Killzone Strategy"

    @property
    def description(self) -> str:
        return "Breakout strategy based on NY Killzone High/Low with ADX/RSI filters."

    def get_params_schema(self):
        # This could be loaded from a JSON or defined here.
        # For this refactor, we rely on the Parser to populate this usually, 
        # but for standalone python strategies, we define it here.
        # HOWEVER, currently the system relies on parsing the .mq5 file to get this.
        # So we return an empty list or the cached schema if available.
        return [] 

    def calculate_signals(self, data, params):
        # unpack params safely
        p = lambda k, d=0: params.get(k, d)
        
        # Calculate Ranges (Specific to URB)
        # We need to map the param names correctly
        # InpTradingStartH vs InpRangeStartHour?
        # Original logic.py used: InpRangeStartHour
        # Let's check what params are passed.
        
        # If parameters for Range are missing, default to 12:00-16:00
        r_start_h = int(p('InpRangeStartHour', 12))
        r_start_m = int(p('InpRangeStartMin', 0))
        r_end_h = int(p('InpRangeEndHour', 16))
        r_end_m = int(p('InpRangeEndMin', 0))
        
        range_highs, range_lows = calculate_daily_ranges(
            data['time'], data['high'], data['low'],
            r_start_h, r_start_m, r_end_h, r_end_m
        )
        
        return urb_backtest_core(
            data['time'], data['open'], data['high'], data['low'], data['close'], data['spread'],
            # Pre-calc arrays
            range_highs, 
            range_lows,
            data.get('atr', np.zeros(len(data['time']))),
            data.get('adx', np.zeros(len(data['time']))),
            data.get('rsi', np.zeros(len(data['time']))),
            
            # Trading Params
            int(p('InpTradingStartHour', 9)), int(p('InpTradingStartMin', 30)),
            int(p('InpTradingEndHour', 11)), int(p('InpTradingEndMin', 0)),
            int(p('InpTradeDirection', 2)),
            float(p('InpBreakoutBuffer', 5.0)),
            float(p('InpFixedLot', 0.1)),
            int(p('InpSlMethod', 0)),
            float(p('InpFixedSL', 200)),
            float(p('InpATRSLMultiplier', 1.5)),
            float(p('InpRiskRewardRatio', 2.0)),
            int(p('InpExitStrategyMode', 0)), # Renamed to match .set usually
            float(p('InpBreakevenTriggerPoints', 100)),
            float(p('InpBreakevenOffsetPoints', 10)),
            float(p('InpTrailingStartPoints', 150)),
            float(p('InpTrailingStepPoints', 50)),
            float(p('InpAtrTrailingMultiplier', 2.0)),
            bool(p('InpUseAdx', False)),
            float(p('InpAdxThreshold', 25)),
            bool(p('InpUseRsi', False)),
            
            float(p('Commission', 7.0)),
            float(p('SwapLong', -5.0)),
            float(p('SwapShort', 2.0))
        )
