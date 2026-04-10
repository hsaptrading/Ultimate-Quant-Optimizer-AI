"""Test signal generation with original EA settings"""
import sys
sys.path.insert(0, '.')
from src.data_loader import create_m15_data
from src.range_breaker import generate_signals, calculate_sl_tp

# Original EA settings from screenshots
original_params = {
    'range_start_hour': 12,
    'range_start_min': 15,
    'range_end_hour': 16,
    'range_end_min': 0,
    'trading_start_hour': 16,
    'trading_start_min': 30,
    'trading_end_hour': 17,
    'trading_end_min': 30,
    'breakout_buffer_points': 200,
    'sl_method': 'fixed',
    'sl_fixed_points': 5000,
    'tp_risk_reward': 2.0
}

print('Testing with ORIGINAL EA settings (1-hour window):')
for k in ['trading_start_hour', 'trading_end_hour', 'breakout_buffer_points']:
    print(f'  {k}: {original_params.get(k)}')

m15 = create_m15_data('data/USATECHIDXUSD.tick.utc2.csv', use_cache=True)
trading_days = m15['datetime'].dt.date.nunique()
print(f'\nTotal bars: {len(m15)}')
print(f'Trading days: {trading_days}')

signals = generate_signals(m15, original_params)
signals = calculate_sl_tp(signals, original_params)

signal_count = (signals['signal'] != 0).sum()
buy_count = (signals['signal'] == 1).sum()
sell_count = (signals['signal'] == -1).sum()

print(f'\nSignal Statistics (with HIGH/LOW detection):')
print(f'  Total signals: {signal_count}')
print(f'  Buy signals: {buy_count}')
print(f'  Sell signals: {sell_count}')
print(f'  Signals per day: {signal_count / trading_days:.2f}')

# Also test with wider window for comparison
wide_params = original_params.copy()
wide_params['trading_end_hour'] = 21
wide_params['breakout_buffer_points'] = 50

signals2 = generate_signals(m15, wide_params)
signal_count2 = (signals2['signal'] != 0).sum()
print(f'\nWith WIDER window (16:30-21:00, buffer=50):')
print(f'  Total signals: {signal_count2}')
print(f'  Signals per day: {signal_count2 / trading_days:.2f}')
