import MetaTrader5 as mt5
import pandas as pd
import os

class MT5Bridge:
    def __init__(self):
        self.connected = False
        self._active_terminal_path = None

    def connect_to_mt5(self, path: str = None):
        """
        Initializes MT5 connection.
        If path is provided, tries to initialize that specific terminal.
        """
        try:
            # Logic adapted from reference to handle re-init properly
            if self.connected and path == self._active_terminal_path:
                 # Already connected to same terminal, checking if connection is still alive
                 if not mt5.terminal_info():
                     self.connected = False
                 else:
                     # Just refresh account info
                     pass
            
            if not self.connected or (path and path != self._active_terminal_path):
                # Shutdown if switching or re-connecting
                if self.connected:
                    mt5.shutdown()
                    self.connected = False
                
                init_params = {}
                if path:
                    init_params['path'] = path
                    self._active_terminal_path = path
                
                if not mt5.initialize(**init_params):
                     return {"status": False, "message": f"Failed to init MT5: {mt5.last_error()}"}
                
                self.connected = True
                if not path:
                     # Capture the path if we auto-connected
                     term_info = mt5.terminal_info()
                     if term_info:
                         self._active_terminal_path = term_info.path

            # Fetch Account Info
            account_info = mt5.account_info()
            if account_info:
                return {
                    "status": True, 
                    "message": "Connected",
                    "account": {
                        "login": account_info.login,
                        "server": account_info.server,
                        "balance": account_info.balance,
                        "currency": account_info.currency,
                        "company": account_info.company,
                        "name": account_info.name
                    }
                }
            else:
                 # Initialized but no account (e.g. no login)
                 return {"status": True, "message": "Connected (No Account Info)", "account": None}

        except Exception as e:
            return {"status": False, "message": f"Exception: {str(e)}"}

    def get_terminals(self):
        found_paths = []
        common_dirs = [
             os.environ.get("ProgramFiles", "C:\\Program Files"),
             os.environ.get("ProgramFiles(x86)", "C:\\Program Files (x86)")
        ]
        
        for base_dir in common_dirs:
             if base_dir and os.path.exists(base_dir):
                 try:
                     for folder in os.listdir(base_dir):
                         full_path = os.path.join(base_dir, folder, "terminal64.exe")
                         if os.path.exists(full_path):
                             found_paths.append(full_path)
                 except: continue
                 
        # Add current if running
        try:
            current = mt5.terminal_info()
            if current and current.path not in found_paths:
                found_paths.append(current.path)
        except:
             pass
            
        return found_paths

    def find_matching_symbol(self, target_name: str):
        """
        Robust Symbol Discovery
        """
        if not self.connected:
            self.connect_to_mt5()

        # 0. FAST PATH
        fast_checks = [target_name, f"{target_name}.a", f"{target_name}.pro", f"{target_name}.r", f"{target_name}m", f"{target_name}.c"]
        for fc in fast_checks:
            if mt5.symbol_info(fc):
                return fc

        # 1. Alias Mapping
        aliases = {
            "US100": ["USTEC", "USTECH", "NAS100", "NQ100", "US100", "NQ", "NQ1!", "US100.cash", "USTEZ", "UT100"],
            "US500": ["US500", "SPX500", "SP500", "ES", "US.500", "S&P500"],
            "US30": ["US30", "DJ30", "WALLSTREET", "WS30", "DOW", "YM1!", "US30.cash"],
            "GER40": ["GER40", "DAX40", "DE40", "DAX", "DE30", "GDAXI"],
            "JPN225": ["JPN225", "JP225", "NIKKEI", "NI225", "JAP225"],
            "XAUUSD": ["GOLD", "XAUUSD", "XAU", "Gold"],
            "XAGUSD": ["SILVER", "XAGUSD", "XAG", "Silver"],
        }
        
        candidates = [target_name]
        if target_name in aliases:
            candidates.extend(aliases[target_name])

        # 2. Get All Symbols (Expensive, do only if fast path fails)
        all_symbols = mt5.symbols_get()
        if not all_symbols:
            return None
        
        broker_names = [s.name for s in all_symbols]

        # 3. Hierarchical Search
        for candidate in candidates:
            # A. Exact
            if candidate in broker_names: return candidate
            
            # B. Suffix/Prefix
            for b_name in broker_names:
                # Suffix check (e.g. EURUSD -> EURUSD.r)
                if b_name.startswith(candidate):
                    suffix = b_name[len(candidate):]
                    valid_suffixes = [".", "_", "m", "+", "#", "c", "micro", "pro", "ecn", "stp", "r", "b", "i"]
                    if suffix == "" or any(suffix.startswith(s) or suffix == s for s in valid_suffixes):
                        return b_name
                
                # Prefix check (e.g. mEURUSD)
                if b_name.endswith(candidate):
                    prefix = b_name[:-len(candidate)]
                    if prefix in ["m", "M"]:
                         return b_name
                         
        # 4. Fallback 'Contains'
        for candidate in candidates:
            for b_name in broker_names:
                if candidate in b_name:
                    return b_name
                    
        return None

    def get_symbol_info(self, symbol: str):
        if not self.connected:
             self.connect_to_mt5()
             
        mapped_name = self.find_matching_symbol(symbol)
        
        if not mapped_name:
             return {"error": "Symbol not found in Broker"}
             
        info = mt5.symbol_info(mapped_name)
        if not info:
             return {"error": "Failed to get info"}
             
        # Extract relevant fields
        swap_days = {0: "Sunday", 1: "Monday", 2: "Tuesday", 3: "Wednesday", 4: "Thursday", 5: "Friday", 6: "Saturday"}
        triple_swap = swap_days.get(info.swap_rollover3days, "Unknown")

        return {
            "mapped_name": mapped_name,
            "info": {
                "path": info.path,
                "spread_float": info.spread_float,
                "digits": info.digits,
                "point": info.point,
                "contract_size": info.trade_contract_size,
                "volume_min": info.volume_min,
                "volume_max": info.volume_max,
                "volume_step": info.volume_step,
                "swap_long": info.swap_long,
                "swap_short": info.swap_short,
                "swap_3day": triple_swap,
                "margin_currency": info.currency_margin,
                "profit_currency": info.currency_profit,
                "trade_mode": info.trade_mode,
                "tick_value": info.trade_tick_value,
                "description": info.description
            }
        }
