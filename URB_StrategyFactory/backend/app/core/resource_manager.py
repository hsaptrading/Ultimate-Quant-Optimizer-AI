import psutil
import multiprocessing
import os

class ResourceManager:
    """
    Gestor Inteligente de Recursos del Sistema.
    Identifica Cores y RAM disponible para evitar colapsos al optimizar.
    """
    def __init__(self, safety_buffer_mb=1024):
        """
        safety_buffer_mb: Memoria mínima (en MB) que se debe dejar siempre libre para el Sistema Operativo (Windows).
        """
        self.safety_buffer_mb = safety_buffer_mb
        
    def get_total_cores(self):
        """Retorna el número total de núcleos lógicos del PC."""
        try:
            return multiprocessing.cpu_count()
        except:
            return os.cpu_count() or 1

    def get_available_ram_mb(self):
        """Retorna la memoria RAM disponible actualmente (en MB)."""
        mem = psutil.virtual_memory()
        return mem.available / (1024 * 1024)
        
    def get_total_ram_mb(self):
        """Retorna la memoria RAM total instalada (en MB)."""
        mem = psutil.virtual_memory()
        return mem.total / (1024 * 1024)

    def calculate_optimal_workers(self, dataset_size_bytes: int, min_workers: int = 1) -> int:
        """
        Calcula el número ideal de Trabajadores (Cores) a utilizar de forma segura,
        basándose en el peso de los datos y la memoria RAM libre.
        """
        total_cores = self.get_total_cores()
        available_ram_mb = self.get_available_ram_mb()
        
        # Memoria segura que podemos usar sin congelar el PC
        usable_ram_mb = max(0, available_ram_mb - self.safety_buffer_mb)
        
        if usable_ram_mb <= 0:
            return min_workers # Peligro extremo de memoria, se recomienda 1
            
        dataset_size_mb = dataset_size_bytes / (1024 * 1024)
        
        # Si bien usamos Memoria Compartida, cada 'Worker' crea vectores temporales al calcular (numpy).
        # Asumimos que cada trabajador necesitará en su memoria interna: 1.5x el peso del dataset + 50MB base.
        overhead_multiplier = 1.5
        baseline_worker_mb = 50.0
        
        ram_per_worker_mb = (dataset_size_mb * overhead_multiplier) + baseline_worker_mb
        
        if ram_per_worker_mb <= 0:
            ram_per_worker_mb = 1.0 
            
        max_workers_by_ram = int(usable_ram_mb // ram_per_worker_mb)
        
        # Por salud del PC, usamos máximo (Cores Totales - 1) para que el ratón y la UI no se traben
        max_workers_by_cpu = max(1, total_cores - 1)
        
        optimal_workers = min(max_workers_by_cpu, max_workers_by_ram)
        
        return max(min_workers, optimal_workers)

    def get_diagnostics(self, dataset_size_bytes: int = 0) -> dict:
        """Retorna un resumen del estado del hardware para logs o UI."""
        return {
            "total_cores": self.get_total_cores(),
            "total_ram_mb": round(self.get_total_ram_mb(), 2),
            "free_ram_mb": round(self.get_available_ram_mb(), 2),
            "safe_workers_recommended": self.calculate_optimal_workers(dataset_size_bytes)
        }
