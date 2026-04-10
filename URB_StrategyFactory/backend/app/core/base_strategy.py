from typing import Dict, Any, List
import numpy as np
import polars as pl

class BaseStrategy:
    """
    Clase base para todas las estrategias en el Motor Universal.
    Define la interfaz estándar que el optimizador espera.
    """
    
    # Metadatos de la Estrategia (Sobreescribir en hijos)
    NAME: str = "Base Strategy"
    VERSION: str = "1.0"
    AUTHOR: str = "Unknown"
    
    # Definición de Parámetros (Inputs de MT5)
    # Formato: { "NombreInput": { "type": float, "default": 1.0, "min": 0.1, "max": 10.0, "group": "Risk" } }
    PARAMETERS: Dict[str, Any] = {}

    def __init__(self):
        pass

    def calculate_signals(self, data: pl.DataFrame, params: Dict[str, Any]) -> np.array:
        """
        Calcula las señales de trading para todo el dataset vectorizado.
        Args:
            data: DataFrame con OHLCV (Polars por velocidad)
            params: Diccionario con los valores de los inputs para esta instancia
        Returns:
            np.array: Array de enteros donde:
                1 = Buy Signal
                -1 = Sell Signal
                0 = Hold/No Signal
                2 = Close Buy
                -2 = Close Sell
        """
        raise NotImplementedError("Cada estrategia debe implementar su lógica de señales.")

    def on_init(self):
        """Pre-cálculos opcionales al cargar la estrategia."""
        pass
        
    @classmethod
    def get_default_params(cls) -> Dict[str, Any]:
        """Devuelve los parámetros por defecto extraídos del código fuente."""
        return {k: v.get("default") for k, v in cls.PARAMETERS.items()}
