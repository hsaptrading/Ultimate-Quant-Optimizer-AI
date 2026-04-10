import sys
import os
import multiprocessing
import numpy as np
import polars as pl
import time

# Adjust path
sys.path.append(os.path.join(os.getcwd(), 'URB_StrategyFactory'))

from backend.app.engine.memory import SharedMemoryManager, MemoryClient

def worker_process(metadata):
    """
    Simulates a worker process reading data from shared memory.
    """
    print(f"[Worker {os.getpid()}] Started. Attaching to Shared Memory...")
    try:
        client = MemoryClient(metadata)
        data = client.get_data()
        
        # Verify data
        closes = data['close']
        print(f"[Worker] Read 'close' array. Shape: {closes.shape}, First val: {closes[0]}, Sample Mean: {np.mean(closes)}")
        
        client.close()
        print(f"[Worker] Detached and finished.")
    except Exception as e:
        print(f"[Worker] Error: {e}")

def main():
    print("--- Probando Shared Memory Manager ---")
    
    # 1. Crear Fake Big Data (5 millones de filas ~ 1 año M1 ticks full history)
    rows = 1_000_000 
    print(f"[Main] Generando DataFrame de prueba ({rows} filas)...")
    
    df = pl.DataFrame({
        'time': np.arange(rows, dtype=np.int64),
        'open': np.random.rand(rows),
        'high': np.random.rand(rows),
        'low': np.random.rand(rows),
        'close': np.random.rand(rows)
    })
    
    print(f"[Main] DataFrame en RAM (Main Process).")
    
    # 2. Cargar en Shared Memory
    manager = SharedMemoryManager()
    t0 = time.time()
    metadata = manager.load_dataframe('test_data_1M', df)
    t1 = time.time()
    print(f"[Main] Cargado en Shared Memory en {t1-t0:.4f}s")
    
    # 3. Lanzar Proceso Hijo
    p = multiprocessing.Process(target=worker_process, args=(metadata,))
    p.start()
    p.join()
    
    # 4. Limpiar
    manager.cleanup()
    print("[Main] Memoria liberada. Test completado.")

if __name__ == "__main__":
    multiprocessing.freeze_support() # Windows support
    main()
