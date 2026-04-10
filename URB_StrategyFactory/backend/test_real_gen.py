import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '.')))

from app.api.generation import run_real_generation
from app.core.state import data_state, strat_state, memory_manager

data_state.loaded = True
data_state.filename = "US100_M15.csv"
data_state.start_date = "2024.01.01"
data_state.end_date = "2024.01.07"

strat_state.active_name = "DualEA.mq5"
strat_state.active_strategy_slug = "dualea"

import pandas as pd
import polars as pl
dummy_df = pl.DataFrame({
    "time": [1000, 2000, 3000],
    "open": [1.1, 1.2, 1.3],
    "high": [1.2, 1.3, 1.4],
    "low": [1.0, 1.1, 1.2],
    "close": [1.1, 1.2, 1.3]
})
memory_manager.load_dataframe("main_data", dummy_df)

config_params = {
    "InpFastEMA": {"start": 5, "stop": 20, "step": 1, "opt": True, "value": 12, "type": "int"}
}

if __name__ == '__main__':
    run_real_generation(population=4, generations=2, cores=2, params=config_params)
