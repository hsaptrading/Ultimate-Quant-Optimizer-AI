"""
FTMO Broker Configuration for US100.cash

IMPORTANT: Points vs Price
- In MT5, 1 point = smallest price increment = 0.01 for US100
- When EA says "200 points buffer", it means 200 * 0.01 = 2.0 in price
- All "_points" parameters should be converted using points_to_price()
"""

# FTMO US100.cash Specifications
FTMO_US100 = {
    "symbol": "US100.cash",
    "digits": 2,
    "contract_size": 1,
    "point_size": 0.01,                 # 1 point = 0.01 price (CRITICAL!)
    "spread_avg_points": 15,            # ~0.15 in price
    "commission_per_lot": 0,            # 0% built into spread
    "swap_long_points": -509.67,        # Per lot per night
    "swap_short_points": 24.23,         # Per lot per night
    "swap_triple_day": 4,               # Friday = day 4
    "min_lot": 0.01,
    "max_lot": 1000,
    "lot_step": 0.01,
    "margin_per_lot_usd": 1712.34,      # At 1:30 leverage
    "tick_value_usd": 0.01,             # Per tick per lot
    "session_start": "01:05",           # Server time (UTC+2)
    "session_end": "23:50",
    "execution": "Market",
    "stops_level": 0
}


def points_to_price(points: float, symbol_config: dict = None) -> float:
    """Convert MT5 points to price units."""
    if symbol_config is None:
        symbol_config = FTMO_US100
    return points * symbol_config.get('point_size', 0.01)


def price_to_points(price: float, symbol_config: dict = None) -> float:
    """Convert price units to MT5 points."""
    if symbol_config is None:
        symbol_config = FTMO_US100
    return price / symbol_config.get('point_size', 0.01)

# Account Settings
FTMO_ACCOUNT = {
    "balance": 100000,
    "leverage": 30,
    "currency": "USD",
    "max_daily_loss_pct": 5.0,      # FTMO rule
    "max_total_loss_pct": 10.0,     # FTMO rule
    "profit_target_pct": 10.0       # Challenge target
}

# Server Time Settings
SERVER_TIMEZONE = "Etc/GMT-2"  # UTC+2 (FTMO)

# NY Session in Server Time (UTC+2)
# NY Open 8:00 EST = 14:00 UTC = 16:00 UTC+2
# NY Close 17:00 EST = 22:00 UTC = 00:00 UTC+2 (next day)
NY_SESSION = {
    "range_start_hour": 14,   # 8:00 NY = 14:00 UTC+2 (winter) / adjust for DST
    "range_start_min": 0,
    "range_end_hour": 15,     # 9:30 NY = 15:30 UTC+2
    "range_end_min": 30,
    "session_end_hour": 23,   # Close trades before session end
    "session_end_min": 50
}

# Default Strategy Parameters (matching EA defaults from MT5 screenshots)
# NOTE: All "_points" values are in MT5 points (1 point = 0.01 price for US100)
DEFAULT_PARAMS = {
    # === RANGE SCHEDULE ===
    "range_start_hour": 12,
    "range_start_min": 15,
    "range_end_hour": 16,
    "range_end_min": 0,
    
    # === TRADING WINDOW (Kill Zone) - Original 1 hour ===
    "trading_start_hour": 16,
    "trading_start_min": 30,
    "trading_end_hour": 17,
    "trading_end_min": 30,
    
    # === EXECUTION & BREAKOUT ===
    # 200 MT5 points = 2.0 in price for US100
    "breakout_buffer_points": 200,        # InpBreakoutBuffer (in MT5 points)
    "min_body_percent": 50,               # InpMinBodyPercent
    "min_bars_after_loss": 5,
    "min_bars_between_trades": 20,
    
    # === RISK MANAGEMENT ===
    "lot_sizing_mode": "risk_percent",  # Fixed_Lot or Risk_Percent
    "fixed_lot": 0.01,
    "risk_percent": 1.0,
    "sl_method": "fixed",             # fixed, atr_based, range_based
    "sl_fixed_points": 5000,
    "sl_atr_period": 14,
    "sl_atr_multiplier": 1.5,
    "sl_range_multiplier": 0.5,
    "sl_min_points": 1000,
    "sl_max_points": 10000,
    "tp_risk_reward": 2.0,
    "max_trades_per_symbol": 1,
    
    # === BREAKEVEN & TRAILING STOP ===
    "exit_strategy": "trailing_points",  # off, breakeven, trailing_points, trailing_atr
    "breakeven_trigger_points": 3000,
    "breakeven_offset_points": 500,
    "trailing_start_points": 5000,
    "trailing_step_points": 5000,
    "trailing_atr_multiplier": 1.0,
    "trailing_atr_period": 14,
    
    # === PROP FIRM SETTINGS ===
    "daily_loss_limit_pct": 4.5,
    "total_loss_limit_pct": 9.5,
    
    # === WEEKEND FILTER ===
    "use_weekend_management": True,
    "friday_close_hour": 20,
    "friday_block_hour": 18,
    
    # === MARKET ACTIVITY FILTER ===
    "use_activity_filter": False,
    "activity_volume_period": 20,
    "min_activity_multiple": 1.2,
    
    # === ADX TREND FILTER ===
    "adx_mode": "off",               # off, strong_only
    "adx_period": 14,
    "adx_threshold": 25,
    
    # === RSI CONFIRM FILTER ===
    "rsi_mode": "off",               # off, confirm_50
    "rsi_period": 14,
    "rsi_confirm_level": 50,
    
    # === OTHER ===
    "max_spread_points": 50,
    "close_end_of_session": True,
}

