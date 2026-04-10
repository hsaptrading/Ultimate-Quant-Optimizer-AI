from fastapi import APIRouter, BackgroundTasks
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
import time
import asyncio

# Engine Imports
from ..engine.genetic import GeneticManager
from ..core.state import gen_state as state, data_state, memory_manager

router = APIRouter()
# memory_manager is now imported from state

# GeneratorState definition removed (using core.state.gen_state)

# --- Models ---
class GenConfig(BaseModel):
    symbol: str = "Auto"
    population: int = 100
    generations: int = 10
    cores: Optional[int] = None
    params: Optional[Dict[str, Any]] = None
    timeframe: Optional[str] = "M15"
    optimize_timeframes: Optional[List[str]] = None
    direction: Optional[str] = "Both"
    optimize_directions: Optional[List[str]] = None
    
class GenStatus(BaseModel):
    running: bool
    progress: float
    current_gen: int
    found_count: int
    best_profit: float
    recent_logs: List[str] = []

# --- Real Worker Task ---
def run_real_generation(population: int, generations: int, cores: int = None, params: Dict[str, Any] = None):
    print("[Generator] Starting Real Optimization...")
    state.is_running = True
    state.total_generations = generations
    state.current_generation = 0
    state.progress = 0
    state.strategies_found = []
    
    # 1. Check Data Availability
    # Assuming 'main_data' is the ID used in data_api
    if not data_state.loaded:
        print("[Generator] No data loaded! Aborting.")
        state.is_running = False
        return

    # Data Info for Workers to attach
    # We need the SHM name (usually 'main_data') and the metrics (shape, dtype)
    # The SharedMemoryManager stores this info in _metadata map in main process.
    # Workers need to know how to read it.
    
    # Quick Hack: Pass the metadata explicitly or let Manager handle it via SharedMemoryManager lookups if in same process tree?
    # Since Manager spawns workers, it can pass the info.
    
    # Get Metadata from Manager (Main Process Side)
    try:
        meta = memory_manager.get_metadata('main_data')
        # Structure of meta: {'name': name, 'shape': df.shape, 'columns': cols, 'dtypes': dtypes}
    except Exception as e:
        print(f"[Generator] Error accessing SharedMemory metadata: {e}")
        state.is_running = False
        return

    # 2. Init Genetic Manager
    # Note: We create a NEW manager each run to ensure clean Pool
    state.manager = GeneticManager(data_shm_name='main_data', data_info=meta)
    
    # Set Config parameters for optimization
    if params:
        state.manager.set_config(params)
    
    try:
        from ..api.endpoints import bridge
        import MetaTrader5 as mt5
        
        terminal_path = None
        data_path = None
        
        # If we have an active bridge, get terminal info so workers can clone it
        if bridge.connected:
            info = mt5.terminal_info()
            if info:
                terminal_path = info.path
                data_path = info.data_path
                
        # Advanced Symbol & Timeframe Parsing
        symbol = "EURUSD"
        timeframe = "M15"
        
        # Priority 1: From user params directly
        if params:
            if "InpSymbol" in params: symbol = params["InpSymbol"].get("value", symbol)
            # Find Timeframe logic via InpSignalTF
            if "InpSignalTF" in params: 
                v = params["InpSignalTF"].get("value", 15)
                timeframe = f"M{v}" if v < 60 else f"H{v//60}"
                
        # Priority 2: Guess from dataframe filename
        if data_state.filename:
            parts = data_state.filename.replace('.csv', '').replace('.parquet', '').split('_')
            symbol = parts[0]
            if len(parts) > 1 and (parts[1].startswith('M') or parts[1].startswith('H') or parts[1].startswith('D')):
                timeframe = parts[1]
                
        state.manager.start_pool(
            cpu_cores=cores, 
            terminal_path=terminal_path, 
            data_path=data_path,
            symbol=symbol,
            timeframe=timeframe
        )
        
        # Callback to update API state
        def on_progress(gen, total_gen, best_profit, top_strategies):
            state.current_generation = gen
            # Progress based on Generations (linear)
            state.progress = (gen / total_gen) * 100
            
            state.current_best = best_profit
            # Transform for JSON (Handle NaN/Inf)
            clean_strategies = []
            for s in top_strategies:
                s_clean = s.copy()
                # Ensure JSON serializable numbers
                s_clean['NetProfit'] = float(s['NetProfit']) if s['NetProfit'] == s['NetProfit'] else 0.0
                clean_strategies.append(s_clean)
                
            state.strategies_found = clean_strategies
            print(f"[Generator] Gen {gen}/{total_gen} | Best: ${best_profit:.2f}")

        # Run Evolution (Blocking until done)
        state.manager.evolve(population, generations, progress_callback=on_progress)
        
    except Exception as e:
        import traceback
        print(f"[Generator] Error during evolution: {e}")
        traceback.print_exc()
    finally:
        if state.manager:
            state.manager.stop_pool()
        state.is_running = False
        print("[Generator] Finished.")

# --- Endpoints ---

@router.post("/start")
def start_generation(config: GenConfig, background_tasks: BackgroundTasks):
    if state.is_running:
        return {"status": "error", "message": "Generation already running"}
    
    # Process virtual params for optimization
    if config.params is None:
        config.params = {}
        
    if config.timeframe == "Optimize Multiple" and config.optimize_timeframes:
        config.params['__EXEC_TIMEFRAME__'] = {
            'opt': True, 'type': 'virtual_enum', 'options': config.optimize_timeframes
        }
        
    if config.direction == "Optimize Multiple" and config.optimize_directions:
        config.params['__EXEC_DIRECTION__'] = {
            'opt': True, 'type': 'virtual_enum', 'options': config.optimize_directions
        }

    # Start Background Task
    background_tasks.add_task(run_real_generation, config.population, config.generations, config.cores, config.params)
    
    return {"status": "started", "config": config}

@router.post("/stop")
def stop_generation():
    if not state.is_running:
        return {"status": "ignored", "message": "Not running"}
    
    state.is_running = False
    # Also signal Manager? 
    # The loop inside run_real_generation checks state.is_running, 
    # but the Manager.evolve loop checks manager.is_running.
    # We should update manager too if possible
    if state.manager:
        state.manager.is_running = False 
        
    return {"status": "stopping"}

@router.get("/status", response_model=GenStatus)
def get_status():
    return {
        "running": state.is_running,
        "progress": round(state.progress, 1),
        "current_gen": state.current_generation,
        "found_count": len(state.strategies_found),
        "best_profit": state.current_best if state.current_best > -999999 else 0.0,
        "recent_logs": [f"Gen {state.current_generation}: ${state.current_best:.2f}"] if state.current_generation > 0 else []
    }

@router.get("/strategies")
def get_strategies():
    # Return Top Strategies
    # Map backend keys to frontend expectations if different?
    # Frontend Expects: id, net_profit, trades, win_rate
    # Backend Produces: NetProfit, Trades, WinRate
    formatted = []
    for s in state.strategies_found:
        formatted.append({
            "id": s.get('id', '??'),
            "net_profit": round(s.get('NetProfit', 0), 2),
            "trades": int(s.get('Trades', 0)),
            "win_rate": round(s.get('WinRate', 0), 1)
        })
    return formatted
