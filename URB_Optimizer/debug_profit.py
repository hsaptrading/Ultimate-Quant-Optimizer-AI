"""Debug profit calculation"""
import sys
sys.path.insert(0, '.')
from src.data_loader import create_m15_data
from src.range_breaker import generate_signals, calculate_sl_tp
from src.backtester import Backtester
from config.broker_config import DEFAULT_PARAMS, FTMO_US100, FTMO_ACCOUNT, points_to_price

print('Testing backtester calculations...')
point_size = FTMO_US100['point_size']
print(f'point_size: {point_size}')

m15 = create_m15_data('data/USATECHIDXUSD.tick.utc2.csv', use_cache=True)
signals = generate_signals(m15, DEFAULT_PARAMS)
signals = calculate_sl_tp(signals, DEFAULT_PARAMS)

# Look at first signal
first_signal = signals[signals['signal'] != 0].iloc[0]
print(f'\nFirst signal:')
print(f'  Direction: {"BUY" if first_signal["signal"] == 1 else "SELL"}')
print(f'  Entry (close): {first_signal["close"]:.2f}')
print(f'  SL points (raw): {first_signal["sl_points"]}')
print(f'  TP points (raw): {first_signal["tp_points"]}')
print(f'  SL price: {first_signal["sl_price"]:.2f}')
print(f'  TP price: {first_signal["tp_price"]:.2f}')

# Calculate what the profit should be
entry = first_signal['close']
sl = first_signal['sl_price']
tp = first_signal['tp_price']
direction = first_signal['signal']

if direction == 1:
    profit_if_tp = tp - entry
    loss_if_sl = entry - sl
else:
    profit_if_tp = entry - tp
    loss_if_sl = sl - entry

print(f'\nProfit/Loss in PRICE units:')
print(f'  If TP hit (profit): {profit_if_tp:.2f}')
print(f'  If SL hit (loss): {loss_if_sl:.2f}')

# What backtester calculates
lot_size = 0.5  # Typical lot size with 1% risk
profit_usd_wrong = profit_if_tp * lot_size * point_size
loss_usd_wrong = loss_if_sl * lot_size * point_size

print(f'\nBacktester current calculation (WRONG):')
print(f'  Profit: {profit_if_tp:.2f} * {lot_size} lot * {point_size} point_size = ${profit_usd_wrong:.2f}')
print(f'  Loss: {loss_if_sl:.2f} * {lot_size} lot * {point_size} = ${loss_usd_wrong:.2f}')

# What it SHOULD be (for US100: $1 per point per lot)
# But wait - the price movement IS in points already (1 point = 0.01 price)
# So a 50 price move = 5000 points
# Profit = 5000 points * 0.01 $/point/lot * lot_size
profit_points = profit_if_tp / point_size  # Convert price to points
loss_points = loss_if_sl / point_size

profit_usd_correct = profit_points * point_size * lot_size
loss_usd_correct = loss_points * point_size * lot_size

print(f'\nCORRECT calculation:')
print(f'  Profit in points: {profit_if_tp:.2f} / {point_size} = {profit_points:.0f} points')
print(f'  Profit USD: {profit_points:.0f} * $0.01/pt * {lot_size} lot = ${profit_usd_correct:.2f}')

# Actually the issue is simpler
# For US100: Contract size = 1, Tick value = $0.01
# For a 50.0 price move with 0.5 lot:
# USD = price_move * contract_size * lot_size = 50 * 1 * 0.5 = $25
profit_usd_simple = profit_if_tp * 1.0 * lot_size
print(f'\nSIMPLE calculation (price * contract_size * lots):')
print(f'  {profit_if_tp:.2f} * 1.0 * {lot_size} = ${profit_usd_simple:.2f}')
