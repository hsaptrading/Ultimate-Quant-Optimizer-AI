import numpy as np
import importlib
from numba.typed import Dict
from numba import types

from ..core.base_strategy import BaseStrategy
from ..core.state import strat_state

class DynamicAIStrategy(BaseStrategy):
    """
    Wrapper dinámico que inyecta la lógica pura de Numba generada por la IA
    dentro del ecosistema de backtesting (worker) de URB.
    """
    def __init__(self, ai_module_name: str):
        super().__init__()
        self.ai_module_name = ai_module_name
        self.display_name = f"Twin: {ai_module_name}"
        self.description = "Estrategia Numba compilada dinámicamente vía IA"
        self._compiled_func = None

        # Load dynamic logic
        try:
            mod = importlib.import_module(f"...strategies.{self.ai_module_name}", package=__name__)
            # The AI prompt asks to name it "mi_estrategia"
            if hasattr(mod, "mi_estrategia"):
                self._compiled_func = mod.mi_estrategia
            else:
                # Find any njit function
                for fn_name in dir(mod):
                    fn = getattr(mod, fn_name)
                    if hasattr(fn, "py_func"): # check if numba decorated
                        self._compiled_func = fn
                        break
        except Exception as e:
            print(f"[Dynamic Strategy] Error cargando lógica AI: {e}")

    def evaluate(self, params: dict, data_arrays: tuple) -> float:
        times, opens, highs, lows, closes, volumes = data_arrays
        
        if not self._compiled_func:
            return -99999.0

        try:
            # We map dict params to explicit kwargs using the schema if needed,
            # or we just pass the Numba Dict. Since AI generated positional args, 
            # we must unpack them dynamically or adapt the AI prompt to use single Numba Dict.
            
            # Extract values in the same order as schema definition
            # (Assuming strat_state.active_schema.inputs matches the AI's parameter generation)
            args = []
            if strat_state.active_schema and getattr(strat_state.active_schema, "inputs", None):
                for inp in strat_state.active_schema.inputs:
                    val = params.get(inp.name, inp.default)
                    # Convert to appropriate type for numba compatibility
                    if inp.type == 'double' or getattr(inp, 'original_type', '') == 'double':
                        args.append(float(val))
                    elif inp.type in ['int', 'enum', 'bool'] or getattr(inp, 'original_type', '') in ['int', 'enum', 'bool']:
                        args.append(int(val))
                    else:
                        args.append(val)
            else:
                # Fallback purely to values
                args = [params[k] for k in params]

            # Execute the pure Numba logic
            # The AI might not return a fitness score yet, it prints logic. 
            # This wrapper will eventually translate pure trading logic signals to PnL.
            self._compiled_func(times, opens, highs, lows, closes, *args)
            
            # Temporary mock fitness since AI is not outputting signals yet 
            # (we will upgrade the AI prompt to output signals array next)
            return float(np.random.normal(100, 20)) 
            
        except Exception as e:
            print(f"[Dynamic AI Strategy] Falló ejecución compilada: {e}")
            return -99999.0
