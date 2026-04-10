import numpy as np
import os
from app.core.ai_translator import AITranslator

# Simple MQL5 code for testing
MQL5_CODE = """
input int InpFastPeriod = 5; // Fast EMA
input int InpSlowPeriod = 20; // Slow EMA

void OnTick() {
    // Dummy logic
    double fast_ema = iMA(_Symbol, _Period, InpFastPeriod, 0, MODE_EMA, PRICE_CLOSE, 0);
    double slow_ema = iMA(_Symbol, _Period, InpSlowPeriod, 0, MODE_EMA, PRICE_CLOSE, 0);
    
    if (fast_ema > slow_ema) {
        // Buy
    } else if (fast_ema < slow_ema) {
        // Sell
    }
}
"""

def test_translation():
    print("[INFO] Levantando AITranslator (Groq API)...")
    # Forzamos API de Groq para que sea rapido en la prueba interna
    translator = AITranslator(mode="api", api_key=os.getenv("GROQ_API_KEY", ""))
    
    print("[INFO] Generando traduccion Numba...")
    # Llamamos a la API
    python_code = translator.translate_code(MQL5_CODE)
    
    print("\n========= CODIGO GENERADO =========")
    print(python_code)
    print("===================================\n")
    
    # Vamos a inyectar el código y ejecutarlo
    print("[TEST] Testeando Compilacion Numba en vivo...")
    
    # Creamos arrays dummy de 200 velas
    N = 200
    times = np.arange(N, dtype=np.float64)
    opens = np.random.normal(1.1, 0.01, N)
    highs = opens + 0.005
    lows = opens - 0.005
    closes = opens + np.random.normal(0, 0.002, N)
    volumes = np.ones(N, dtype=np.float64)
    
    # Ejecutamos el codigo (definiendo la funcion en este scope)
    local_env = {}
    try:
        exec(python_code, globals(), local_env)
        
        if 'mi_estrategia' not in local_env:
            print("[ERROR] La IA no nombro la funcion 'mi_estrategia'")
            return
            
        strat_func = local_env['mi_estrategia']
        
        print("[RUN] Ejecutando funcion compilada con Numpy arrays...")
        # Los parametros extras segun el MQ5 = InpFastPeriod (5), InpSlowPeriod (20)
        net_profit = strat_func(times, opens, highs, lows, closes, volumes, 5, 20)
        
        print(f"[EXITO] Numba compilo y simulo las velas. Net Profit Resultante: ${net_profit:.2f}")
        
    except Exception as e:
        print(f"[ERROR] fatal de compilacion/ejecucion: {e}")

if __name__ == "__main__":
    test_translation()
