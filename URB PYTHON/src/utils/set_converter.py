
import os

class SetConverter:
    @staticmethod
    def save_set_file(params, strategy_name, output_dir):
        """
        Converts Production params to MT5 .set file.
        """
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)
            
        filename = os.path.join(output_dir, f"{strategy_name}.set")
        
        # Calculate Ratio
        rr_ratio = params['TPPoints'] / params['SLPoints']
        
        with open(filename, 'w') as f:
            f.write("; URB Strategy Factory PROD Set\n")
            f.write(f"; Score: {params.get('score', 'N/A')}\n")
            f.write(f"InpMagicNumber={int(strategy_name.split('_')[-1]) if '_' in strategy_name else 123456}\n")
            f.write(f"InpTradeComment={strategy_name}\n")
            
            # --- Range Schedule ---
            f.write(f"InpRangeStartHour={params['RangeStartHour']}\n")
            f.write(f"InpRangeStartMin={params['RangeStartMin']}\n")
            f.write(f"InpRangeEndHour={params['RangeEndHour']}\n")
            f.write(f"InpRangeEndMin={params['RangeEndMin']}\n")
            
            # --- Trading Window ---
            f.write(f"InpTradingStartHour={params['TradingStartHour']}\n")
            f.write(f"InpTradingStartMin={params['TradingStartMin']}\n")
            f.write(f"InpTradingEndHour={params['TradingEndHour']}\n")
            f.write(f"InpTradingEndMin={params['TradingEndMin']}\n")
            
            # --- Execution ---
            # Prod uses 10 point buffer usually
            f.write(f"InpBreakoutBuffer={int(params['BufferPoints'])}\n")
            
            # --- Risk ---
            f.write("InpLotSizingMode=0\n") 
            f.write("InpFixedLot=0.1\n")
            f.write("InpSlMethod=0\n") 
            f.write(f"InpFixedSL_In_Points={int(params['SLPoints'])}\n")
            f.write(f"InpRiskRewardRatio={rr_ratio:.2f}\n")
            
            # --- Indicators (PROD) ---
            f.write(f"InpUseActivityFilter=0\n")
            
            # ADX
            # Logic: If UseADX is True -> Trend Mode (1). If False -> Off (0).
            adx_mode = 1 if params.get('UseADX', False) else 0
            f.write(f"InpAdxTrendMode={adx_mode}\n")
            f.write(f"InpAdxTrendPeriod=14\n") # Fixed for now
            f.write(f"InpAdxLevel={int(params.get('AdxThreshold', 25))}\n")
            
            # RSI
            # Logic: If UseRSI is True -> Confirm Mode (1). Else 0.
            rsi_mode = 1 if params.get('UseRSI', False) else 0
            f.write(f"InpRsiConfirmMode={rsi_mode}\n")
            f.write("InpRsiPeriod=14\n")
            f.write("InpRsiUpperLevel=70\n")
            f.write("InpRsiLowerLevel=30\n")
            
            f.write(f"InpUseMultiTimeframe=false\n")
            
            # --- Simulations ---
            # These are not inputs in EA, just comments for user
            f.write(f"; Commission={params.get('Commission', 0)}\n")
            f.write(f"; SwapLong={params.get('SwapLong', 0)}\n")
            
        return filename
