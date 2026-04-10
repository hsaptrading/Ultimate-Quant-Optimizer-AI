import MetaTrader5 as mt5

if not mt5.initialize(r"C:\Program Files\FTMO MetaTrader 5\terminal64.exe"):
    print("Failed to initialize MT5")
else:
    info = mt5.terminal_info()
    print("Terminal Data folder:", info.data_path)
    symbols = mt5.symbols_get()
    print("Total symbols:", len(symbols) if symbols else 0)
    for s in symbols[:20]:
        print("-", s.name)
    
    eurusd = mt5.symbol_info("EURUSD")
    print("\nEURUSD exists?", bool(eurusd))
    
    macd = mt5.symbol_info("US100.cash")
    print("US100.cash exists?", bool(macd))
    
    mt5.shutdown()
