import os
import sys
import MetaTrader5 as mt5
from app.engine.mt5_farm import MT5FarmController

def test_engine():
    print("--------------------------------------------------")
    print("INICIANDO MOTOR DE PRUEBA PURA (Aislado de UI)")
    print("--------------------------------------------------")

    # 1. Conectar a MetaTrader 5 base para obtener las rutas reales del Broker
    if not mt5.initialize():
        print("FAIL: No se pudo conectar a MetaTrader 5. Error:", mt5.last_error())
        return

    info = mt5.terminal_info()
    term_path = info.path
    data_path = info.data_path
    mt5.shutdown() # Cerramos conexión base
    
    print(f"MetaTrader Encontrado: {term_path}")
    print(f"Carpeta de Datos del Broker: {data_path}")
    
    # 2. Buscar nuestro Robot (EA) dentro de la carpeta Experts
    experts_dir = os.path.join(data_path, "MQL5", "Experts")
    robot_file = None
    
    robot_file = r"Ultimate H4 Sweep\Ultimate H4 LSweep.ex5"
    full_robot_path = os.path.join(experts_dir, robot_file)
    if not os.path.exists(full_robot_path):
        print(f"FAIL: No se encontro el archivo: {full_robot_path}")
        robot_file = None
            
    if not robot_file:
        print(f"FAIL: No se encontro ningun Robot compilado (.ex5) en {experts_dir}")
        return
        
    print(f"Robot (EA) Seleccionado para la prueba: {robot_file}")
    
    # 3. Inicializar nuestra Granja "Clonadora" con 1 solo nodo
    print("\n--- PASO 3: Construyendo Nodo de Clonacion ---")
    farm = MT5FarmController(
        terminal_path=term_path,
        expert_name=robot_file,
        symbol="EURUSD", 
        timeframe="M15",
        max_nodes=1
    )
    
    farm.clone_nodes(data_path)
    node_exe = farm.nodes[0]
    print(f"Nodo de Prueba construido con exito en: {node_exe}")

    # 4. Lanzar Simulación (Backtest)
    print("\n--- PASO 4: Inyectando Parametros y Ejecutando ---")
    print("Por favor espera (esto tomara lo que tarde el robot en testear todo el año)...")
    
    # Inventamos algunos parámetros dummy
    test_params = {
        "id": "PRUEBA_PURA_001",
        "InpSignalTF": 15,
        "InpLots": 1.0,
        "InpTakeProfit": 500,
        "InpStopLoss": 250
    }
    
    # Fechas de inicio y fin (si no tienes barras para 2024, arrojará 0)
    # Sugerencia: Si tu MT5 tiene solo datos recientes de US100, cambiemos las fechas.
    res = farm.execute_worker_test(
        params=test_params,
        exe_path=node_exe,
        start_date="2024.01.01",  # 6 meses
        end_date="2024.06.30"
    )
    
    print("\n================ RESULTADOS FINALES ================")
    print("Raw Result:", res)
    if res.get("NetProfit", -999999) == -999999:
        print("EL TEST ABORTO O FALLO LOGICAMENTE.")
        print(f"Diagnostico Forense de Logs de MT5:\n{res.get('error_log', 'Ninguno')}")
    elif res.get("Trades", 0) == 0:
        print("EL TEST TERMINO PERO TUVO 0 TRADES $0.00.")
        print("Significa que el EA se ejecutó perfecto, pero nunca encontro condiciones o los datos M15 faltaban.")
        print(f"Diagnostico Forense de Logs de MT5:\n{res.get('error_log', 'Ninguno')}")
    else:
        print(f"EXITO ROTUNDO! El motor funciona perfecto.")
        print(f"Beneficio Neto : ${res.get('NetProfit', 0)}")
        print(f"Total de Trades: {res.get('Trades', 0)}")
        print(f"WinRate        : {res.get('WinRate', 0)}%")
        
    print("====================================================")

if __name__ == "__main__":
    test_engine()
