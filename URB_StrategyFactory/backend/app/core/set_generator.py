
import os

def generate_mt5_set_content(params: dict) -> str:
    """
    Converts a dictionary of parameters into MT5 .set file format.
    Format:
    InpName=Value
    InpName,F=0
    InpName,1=0
    ...
    """
    lines = []
    lines.append("; Strategy Factory Generated Set File")
    lines.append("; Copyright 2025, URB Optimizer")
    lines.append("")
    
    # Standard mapping based on known inputs from Ultimate Range Breaker
    # We Iterate over the params and format them.
    # The frontend/backend params keys should match the Inp names exactly if possible.
    # If not, we might need a mapping.
    # From previous logic, we use keys like 'InpRangeStartHour', so it matches.
    
    for key, value in params.items():
        # Skip internal metrics keys
        if key in ['id', 'NetProfit', 'Trades', 'WinRate', 'SQN', 'R2', 'fitness', 'Equity']:
            continue
            
        # Format Boolean
        if isinstance(value, bool):
            val_str = "true" if value else "false"
        else:
            val_str = str(value)
            
        lines.append(f"{key}={val_str}")
        # MT5 often adds optimization flags like ,F=0, ,1=0, ,2=0, ,3=0
        # We can omit them for a simple set file, or add defaults (Not optimizing)
        lines.append(f"{key},F=0")
        lines.append(f"{key},1=0")
        lines.append(f"{key},2=0")
        lines.append(f"{key},3=0")
        
    return "\n".join(lines)
