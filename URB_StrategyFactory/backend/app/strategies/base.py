from abc import ABC, abstractmethod
from typing import Dict, List, Any

class BaseStrategy(ABC):
    """
    Abstract Base Class for all strategies in the Factory.
    Enforces a standard structure for Parameters and Logic.
    """
    
    @property
    @abstractmethod
    def name(self) -> str:
        """Unique identifier for the strategy (slug)."""
        pass

    @property
    @abstractmethod
    def display_name(self) -> str:
        """Human readable name for the UI."""
        pass

    @property
    @abstractmethod
    def description(self) -> str:
        """Brief description of the strategy logic."""
        pass

    @abstractmethod
    def get_params_schema(self) -> List[Dict[str, Any]]:
        """
        Returns the list of inputs for the UI Builder.
        Format:
        [
            {
                "category": "Main Settings",
                "params": [
                    {"name": "InpPeriod", "type": "int", "default": 14, "min": 2, "max": 50, ...},
                    ...
                ]
            },
            ...
        ]
        """
        pass

    @abstractmethod
    def calculate_signals(self, data_arrays: Dict[str, Any], params: Dict[str, Any]):
        """
        Core Numba-compatible logic to calculate signals and backtest.
        
        Args:
            data_arrays: Dictionary of numpy arrays (Time, Open, High, Low, Close...)
            params: Dictionary of optimization parameters (key: value)
            
        Returns:
             tuple: (NetProfit, Wins, Losses, EquityCurveArray)
        """
        pass
