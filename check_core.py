import sys
import os
import numpy as np
import polars as pl
import time

# Ajustar path
sys.path.append(os.path.join(os.getcwd(), 'URB_StrategyFactory'))

from backend.app.core.backtester import FastBacktester

def test_core():
    print("--- Probando Core Numba Logic ---")
    
    # 1. Crear Dummy Data (1 dia de ticks/barras)
    # 1440 mins
    rows = 1440
    data = {
        'time': np.arange(1000000000000, 1000000000000 + (rows * 60000), 60000),
        'open': np.random.uniform(15000, 15100, rows),
        'high': np.array([]),
        'low': np.array([]),
        'close': np.array([]),
        'spread_est': np.ones(rows) * 2.0
    }
    
    # Generar HLC consistentes
    data['high'] = data['open'] + 5.0
    data['low'] = data['open'] - 5.0
    data['close'] = data['open'] + 1.0
    
    df = pl.DataFrame(data)
    print(f"[INFO] DataFrame creado: {df.shape}")
    
    # 2. Inicializar Backtester (Dispara JIT de indicadores)
    t0 = time.time()
    bt = FastBacktester(df)
    t1 = time.time()
    print(f"[OK] Backtester inicializado en {t1-t0:.4f}s (JIT Indicators Warmup)")
    
    # 3. Correr Backtest Dummy (Dispara JIT de Logic)
    params = {
        'RangeStartHour': 2, 'RangeStartMin': 0,
        'RangeEndHour': 10, 'RangeEndMin': 0,
        'TradingStartHour': 10, 'TradingStartMin': 0,
        'TradingEndHour': 20, 'TradingEndMin': 0,
        'BufferPoints': 5.0,
        'SLPoints': 50.0,
        'TPPoints': 100.0,
        'UseADX': True,
        'AdxThreshold': 20.0,
        'UseRSI': False,
        'Commission': 7.0,
        'SwapLong': -5.0,
        'SwapShort': 2.0
    }
    
    t2 = time.time()
    res = bt.run(params)
    t3 = time.time()
    
    print(f"[OK] Backtest ejecutado en {t3-t2:.4f}s (JIT Core Warmup)")
    print("Resultados:", res)
    
    # 4. Segunda corrida (Hot)
    t4 = time.time()
    res2 = bt.run(params)
    t5 = time.time()
    print(f"[OK] Backtest Hot ejecutado en {t5-t4:.4f}s")
    
if __name__ == "__main__":
    test_core()
