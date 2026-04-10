from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import sys
import os

# Import modules
from ..bridges.mt5_bridge import MT5Bridge
from ..core.state import strat_state

router = APIRouter()

# Instantiate Single Bridge
bridge = MT5Bridge()

# --- Data Models ---
class ConnectionResponse(BaseModel):
    status: bool
    message: str
    account: Optional[dict] = None

# --- Endpoints ---

@router.get("/bridge/connect", response_model=ConnectionResponse)
def connect_mt5(path: Optional[str] = None):
    """Connects to MT5 and returns status + account info."""
    result = bridge.connect_to_mt5(path=path)
    return result

@router.get("/bridge/terminals", response_model=List[str])
def get_terminals():
    """Returns list of detected MT5 terminal paths."""
    return bridge.get_terminals()

@router.get("/bridge/symbol/{symbol_name}")
def get_symbol_details(symbol_name: str):
    """Returns details for a specific symbol."""
    # Logic is now encapsulated in bridge.get_symbol_info
    # which calls find_matching_symbol internally
    data = bridge.get_symbol_info(symbol_name)
    
    if "error" in data:
         # Check if it was a connection error or not found
         if "Connected" in data.get("error", ""):
              raise HTTPException(status_code=503, detail=data["error"])
         return {"error": data["error"]}
    
    return data

@router.get("/config/schema")
def get_strategy_schema():
    """
    Returns the parameter structure for the Active Strategy.
    If a custom strategy is loaded (via StrategyState), returns that.
    Otherwise returns default Ultimate Range Breaker schema.
    """
    # 1. Custom Strategy Loaded?
    if strat_state.active_schema:
        raw_inputs = strat_state.active_schema.inputs
        
        # Group by Category
        categories = {}
        for inp in raw_inputs:
            cat_name = inp.category or "General"
            if cat_name not in categories:
                categories[cat_name] = []
            
            # Estimate intelligent defaults for Min/Max based on type/value
            # This is a heuristic until we have a proper config editor
            p_min = 0
            p_max = 100
            
            if inp.type == "int":
                p_min = 0
                val = inp.default if isinstance(inp.default, (int, float)) else 0
                p_max = val * 5 if val > 0 else 100
            elif inp.type == "float":
                p_min = 0.0
                val = inp.default if isinstance(inp.default, (int, float)) else 0.0
                p_max = val * 3.0 if val > 0 else 10.0
            
            categories[cat_name].append({
                "name": inp.name,
                "type": inp.type,
                "default": inp.default,
                "label": inp.label,
                "min": p_min,
                "max": p_max,
                "options": getattr(inp, "options", None),
                "original_type": getattr(inp, "original_type", getattr(inp, "type", None))
            })
            
        # Convert to List format
        result = []
        for cat, params in categories.items():
            result.append({
                "category": cat,
                "params": params
            })
        return result

    # 2. Default URB Schema
    return [
        {
            "category": "General Settings",
            "params": [
                {"name": "InpSignalTF", "type": "int", "default": 15, "options": [5, 15, 30], "label": "Timeframe (M5/15/30)"}, 
                {"name": "InpTradeDirection", "type": "int", "min": 0, "max": 2, "default": 2, "label": "Direction (0=Buy,1=Sell,2=Both)"},
                {"name": "InpExecutionMode", "type": "int", "min": 0, "max": 1, "default": 0, "label": "Exec Mode (0=Stop, 1=Market)"},
                {"name": "InpBreakoutBuffer", "type": "float", "min": 0, "max": 100, "default": 20.0, "label": "Breakout Buffer (Points)"},
            ]
        },
        {
            "category": "Range Schedule",
            "params": [
                {"name": "InpRangeStartHour", "type": "int", "min": 0, "max": 23, "default": 12},
                {"name": "InpRangeStartMin", "type": "int", "min": 0, "max": 59, "default": 15},
                {"name": "InpRangeEndHour", "type": "int", "min": 0, "max": 23, "default": 16},
                {"name": "InpRangeEndMin", "type": "int", "min": 0, "max": 59, "default": 0}
            ]
        },
        {
            "category": "Trading Window",
            "params": [
                {"name": "InpTradingStartHour", "type": "int", "min": 0, "max": 23, "default": 16},
                {"name": "InpTradingStartMin", "type": "int", "min": 0, "max": 59, "default": 30},
                {"name": "InpTradingEndHour", "type": "int", "min": 0, "max": 23, "default": 17},
                {"name": "InpTradingEndMin", "type": "int", "min": 0, "max": 59, "default": 30}
            ]
        },
        {
            "category": "Risk Management",
            "params": [
                {"name": "InpFixedLot", "type": "float", "min": 0.01, "max": 100, "default": 0.01},
                {"name": "InpRiskPerTradePct", "type": "float", "min": 0.1, "max": 10, "default": 1.0},
                {"name": "InpSlMethod", "type": "int", "min": 0, "max": 1, "default": 0, "label": "SL Mode (0=Fixed, 1=ATR)"},
                {"name": "InpFixedSL_In_Points", "type": "float", "min": 10, "max": 2000, "default": 500.0},
                {"name": "InpAtrSlPeriod", "type": "int", "min": 1, "max": 50, "default": 14},
                {"name": "InpAtrSlMultiplier", "type": "float", "min": 0.1, "max": 10, "default": 1.5},
                {"name": "InpRiskRewardRatio", "type": "float", "min": 0.1, "max": 20, "default": 2.0}
            ]
        },
        {
            "category": "Exit Strategy (Trailing)",
            "params": [
                {"name": "InpExitStrategyMode", "type": "int", "min": 0, "max": 3, "default": 2, "label": "Mode (0=Off, 1=BE, 2=TrlPts, 3=TrlATR)"},
                {"name": "InpBreakevenTriggerPoints", "type": "float", "min": 10, "max": 2000, "default": 300.0},
                {"name": "InpBreakevenOffsetPoints", "type": "float", "min": 1, "max": 500, "default": 50.0},
                {"name": "InpTrailingStartPoints", "type": "float", "min": 10, "max": 2000, "default": 500.0},
                {"name": "InpTrailingStepPoints", "type": "float", "min": 10, "max": 2000, "default": 500.0},
                {"name": "InpAtrTrailingMultiplier", "type": "float", "min": 0.1, "max": 10, "default": 1.0}
            ]
        },
        {
            "category": "Filters",
            "params": [
                {"name": "InpUseAdx", "type": "bool", "default": False},
                {"name": "InpAdxThreshold", "type": "float", "min": 10, "max": 60, "default": 25.0},
                {"name": "InpUseRsi", "type": "bool", "default": False},
                {"name": "InpRsiConfirm", "type": "float", "min": 40, "max": 60, "default": 50.0}
            ]
        },
        {
            "category": "Daily Limits (Prop Firm)",
            "params": [
                {"name": "InpDailyLossMode", "type": "int", "min": 0, "max": 2, "default": 1, "label": "Mode (0=Off, 1=%, 2=$)"},
                {"name": "InpDailyLossValue", "type": "float", "min": 0, "max": 20, "default": 4.5},
                {"name": "InpTotalLossValue", "type": "float", "min": 0, "max": 20, "default": 9.5}
            ]
        }
    ]
