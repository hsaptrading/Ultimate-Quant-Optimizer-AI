import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '.')))

from app.core.resource_manager import ResourceManager

def run_tests():
    print("Iniciando Pruebas de Diagnostico del Gestor de Recursos (Hardware)...")
    
    manager = ResourceManager(safety_buffer_mb=1024) # Dejamos 1GB para Windows por defecto
    
    # Supongamos escenarios de datasets de prueba
    escenario_1_bytes = 10 * 1024 * 1024 # 10 MB CSV pequeno
    escenario_2_bytes = 200 * 1024 * 1024 # 200 MB CSV normal 1-minute data 2 anos
    escenario_3_bytes = 5 * 1024 * 1024 * 1024 # 5 GB CSV masivo tick data
    
    print("\n--- DIAGNOSTICO DEL SISTEMA ---")
    diag = manager.get_diagnostics()
    print(f"Nucleos Logicos Totales: {diag['total_cores']}")
    print(f"RAM Total Instalada: {diag['total_ram_mb']} MB")
    print(f"RAM Libre Actual: {diag['free_ram_mb']} MB")
    
    print("\n--- SIMULACION DE ESCENARIOS ---")
    workers_small = manager.calculate_optimal_workers(escenario_1_bytes)
    print(f"Escenario 1 (10 MB Data): Motores optmales calculados = {workers_small}")

    workers_med = manager.calculate_optimal_workers(escenario_2_bytes)
    print(f"Escenario 2 (200 MB Data): Motores optmales calculados = {workers_med}")

    workers_large = manager.calculate_optimal_workers(escenario_3_bytes)
    print(f"Escenario 3 (5 GB Data): Motores optmales calculados = {workers_large}")

if __name__ == '__main__':
    run_tests()
