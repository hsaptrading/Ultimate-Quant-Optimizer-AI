import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '.')))

from app.api.generation import run_real_generation
from app.core.state import data_state, strat_state, memory_manager

data_state.loaded = True
data_state.filename = "US100_M15.csv"
data_state.start_date = "2024.01.01"
data_state.end_date = "2024.01.07"

# Apuntar directo a la clase en Numba generada (slug)
strat_state.active_name = "Ultimate H4 LSweep.mq5"
strat_state.active_strategy_slug = "ultimate_h4_lsweep"

import polars as pl
import numpy as np

# Generar 10,000 barras falsas para probar (Close, Open, High, Low)
n_bars = 10000
base = 1.1000
closes = base + np.random.randn(n_bars).cumsum() * 0.001
highs = closes + np.abs(np.random.randn(n_bars) * 0.002)
lows = closes - np.abs(np.random.randn(n_bars) * 0.002)
opens = closes - np.random.randn(n_bars) * 0.001

dummy_df = pl.DataFrame({
    "time": np.arange(1000, 1000 + n_bars),
    "open": opens,
    "high": highs,
    "low": lows,
    "close": closes
})

memory_manager.load_dataframe("main_data", dummy_df)

config_params = {
    "InpRiskReward": {"start": 1.0, "stop": 3.0, "step": 0.5, "opt": True, "value": 2.0, "type": "float"},
    "InpStopLossPoints": {"start": 100, "stop": 1000, "step": 100, "opt": True, "value": 500, "type": "int"},
    "InpATRMultiplier": {"start": 0.1, "stop": 2.0, "step": 0.1, "opt": True, "value": 0.5, "type": "float"},
}

if __name__ == '__main__':
    print("Iniciando prueba de Optimizacion Genetica Nativa en Ultimate H4 Sweep...")
    run_real_generation(population=4, generations=2, cores=2, params=config_params)
