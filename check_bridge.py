import sys
import os

# Ajustar path para importar módulos backend
sys.path.append(os.path.join(os.getcwd(), 'URB_StrategyFactory'))

from backend.app.bridges.mt5_bridge import MT5Bridge

def test_bridge():
    print("--- Probando MT5 Bridge ---")
    
    # 1. Buscar Instalaciones
    paths = MT5Bridge.find_mt5_installations()
    if paths:
        print(f"[OK] Se encontraron {len(paths)} terminales:")
        for p in paths:
            print(f"  - {p}")
    else:
        print("[WARN] No se encontraron terminales en rutas por defecto.")

    # 2. Inicializar (Sin cuenta, solo para ver si carga la librería)
    ok, msg = MT5Bridge.initialize()
    if ok:
        print(f"[OK] Inicializacion MT5 exitosa: {msg}")
        
        # Info de terminal
        try:
            ver = MT5Bridge.mt5.version()
            print(f"[INFO] MT5 Version: {ver}")
        except:
            print("[INFO] Version MT5 no disponible en objeto wrapper, pero conectado.")
        
        # Cerrar
        MT5Bridge.shutdown()
        print("[OK] Shutdown correcto.")
    else:
        print(f"[FAIL] Error inicializando: {msg}")

if __name__ == "__main__":
    test_bridge()
