from fastapi import APIRouter, UploadFile, File, HTTPException
from pydantic import BaseModel
import polars as pl
import os
import numpy as np
import re
from datetime import datetime

# Import Shared State
from ..core.state import data_state, memory_manager

router = APIRouter()
# memory_manager is now imported from state

# DataState is now in core.state

# --- Models ---
class DataInfo(BaseModel):
    loaded: bool
    filename: str
    total_rows: int
    min_date: str
    max_date: str
    active_start: str
    active_end: str
    oos_pct: float

class DateRangeConfig(BaseModel):
    start_date: str
    end_date: str
    oos_pct: float

# --- Endpoints ---

@router.get("/status", response_model=DataInfo)
def get_data_status():
    return {
        "loaded": data_state.loaded,
        "filename": data_state.filename,
        "total_rows": data_state.total_rows,
        "min_date": data_state.min_date,
        "max_date": data_state.max_date,
        "active_start": data_state.active_start,
        "active_end": data_state.active_end,
        "oos_pct": data_state.oos_split_pct
    }

@router.post("/config/range")
def set_data_range(config: DateRangeConfig):
    """Update active date range and IS/OOS split."""
    # Validation logic would go here (check bounds)
    data_state.start_date = config.start_date
    data_state.end_date = config.end_date
    data_state.oos_split_pct = config.oos_pct
    
    # TODO: Trigger re-slicing of indices in SharedMemory if optimized
    return {"status": "ok", "message": "Range updated", "config": config}

@router.post("/load_dummy")
def load_dummy_data():
    """Generates dummy data for testing without file upload."""
    try:
        # Create 1 Year of M1 Data (approx 100k rows for test)
        rows = 100_000
        # TIMESTAMPS MUST BE MILLISECONDS for the Engine logic
        base_time = datetime(2023, 1, 1).timestamp() * 1000 
        
        # RANDOM WALK GENERATION (To allow Breakouts)
        # 1. Generate Returns
        returns = np.random.normal(0, 2, rows) # Mean 0, Std 2 points per minute
        price_curve = 14000 + np.cumsum(returns)
        
        # 2. Derive OHLC
        # Add noise for bar volatility
        noise_high = np.abs(np.random.normal(0, 3, rows))
        noise_low = np.abs(np.random.normal(0, 3, rows))
        
        df = pl.DataFrame({
            "time": np.arange(base_time, base_time + (rows * 60000), 60000),
            "open": price_curve,
            "high": price_curve + noise_high,
            "low": price_curve - noise_low,
            "close": price_curve + np.random.normal(0, 1, rows), # Close near Open/Path
            "spread": np.ones(rows) * 1.5
        })
        
        # Update State
        data_state.loaded = True
        data_state.filename = "Dummy_Data_Synthetic"
        data_state.total_rows = rows
        data_state.min_date = "2023-01-01"
        data_state.max_date = "2023-04-01" # Approx
        
        # Default Active Range
        data_state.active_start = data_state.min_date
        data_state.active_end = data_state.max_date
        
        # Load into Shared Memory
        # In real app, we use unique ID. For now 'main_data'
        memory_manager.load_dataframe('main_data', df)
        
        return {"status": "ok", "rows": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    """
    Real file upload handler (Parquet/CSV).
    Allows user to select a file from UI.
    """
    temp_path = f"temp_{file.filename}"
    
    try:
        # Save uploaded file
        with open(temp_path, "wb") as buffer:
            content = await file.read()
            buffer.write(content)
            
        print(f"DEBUG: File saved to {temp_path}, Size: {len(content)} bytes")
            
        # Try Loading with Polars
        df = None
        if temp_path.endswith('.parquet'):
            df = pl.read_parquet(temp_path)
        elif temp_path.endswith('.csv'):
            # Try reading with typical MT5 export settings
            # MT5 Exports often DO NOT have headers. format: <DATE> <TIME> <OPEN> <HIGH> <LOW> <CLOSE> <TICKVOL> <VOL> <SPREAD>
            
            # 1. First, try reading optimistically
            try:
                df = pl.read_csv(temp_path, ignore_errors=True, n_rows=10) # Read small chunk to sniff
                
                # HEURISTIC: Check if column names look like data (dates/floats)
                # If column 0 name contains digits and dots like '2023.01.01', it's seemingly a headerless file.
                first_col = df.columns[0]
                has_header = True
                if re.search(r'\d{4}[\./-]\d{2}[\./-]\d{2}', first_col): # Matches YYYY.MM.DD
                    has_header = False
                elif re.match(r'^\d+(\.\d+)?$', first_col): # Matches pure numbers
                    has_header = False
                
                # Reload based on heuristic
                if not has_header:
                    df = pl.read_csv(
                        temp_path, 
                        has_header=False,
                        new_columns=["date", "time", "open", "high", "low", "close", "tick_vol", "vol", "spread"]
                    )
                else:
                    # Reread full file with inferred header
                    df = pl.read_csv(temp_path, ignore_errors=True)
                    # Normalize common variants
                    df = df.rename({c: c.lower() for c in df.columns})

            except Exception as e:
                # Fallback to fixed column structure if sniffing fails
                print(f"CSV Sniffing Failed ({e}), forcing MT5 structure.")
                df = pl.read_csv(
                    temp_path, 
                    has_header=False,
                    new_columns=["date", "time", "open", "high", "low", "close", "tick_vol", "vol", "spread"]
                )

        else:
            raise HTTPException(400, "Unsupported file format. Use CSV or Parquet.")
            
        if df is None or len(df) == 0:
             raise HTTPException(400, "Empty Data File")

        print(f"DEBUG: Loaded DataFrame with {len(df)} rows. Columns: {df.columns}")

        # --- Date Parsing Logic ---
        # Goal: Create a 'time' column in Milliseconds (Int64)
        
        # Case A: Separate "date" and "time" columns (MT5 Standard)
        if "date" in df.columns and "time" in df.columns and df["date"].dtype == pl.Utf8:
             # Merge and Parse: "2023.01.01" + " " + "12:00"
             # Detect separator (. or - or /)
             sample_date = df["date"][0]
             fmt = "%Y.%m.%d"
             if "-" in sample_date: fmt = "%Y-%m-%d"
             elif "/" in sample_date: fmt = "%Y/%m/%d"
             
             df = df.with_columns(
                (pl.col("date") + " " + pl.col("time")).str.to_datetime(f"{fmt} %H:%M").cast(pl.Int64).alias("ts_micro")
             )
             # Convert Microseconds to Milliseconds
             df = df.with_columns((pl.col("ts_micro") / 1000).cast(pl.Int64).alias("time_ms"))
             
        # Case B: Single "time" or "datetime" column (Standard CSV)
        elif "time" in df.columns:
            # Check if already int (Unix timestamp)
            if df["time"].dtype in [pl.Int64, pl.Float64]:
                 # Assume it's seconds if small, ms if large? 
                 # Heuristic: Unix for 2000 is 946684800 (9 digits)
                 # Unix ms for 2000 is 946684800000 (12 digits)
                 sample = df["time"][0]
                 if sample < 10000000000: # Seconds
                      df = df.with_columns((pl.col("time") * 1000).cast(pl.Int64).alias("time_ms"))
                 else: # Already MS
                      df = df.with_columns(pl.col("time").cast(pl.Int64).alias("time_ms"))
            elif df["time"].dtype == pl.Utf8:
                 # Try parse ISO format
                 try:
                    df = df.with_columns(pl.col("time").str.to_datetime().cast(pl.Int64).alias("ts_micro"))
                    df = df.with_columns((pl.col("ts_micro") / 1000).cast(pl.Int64).alias("time_ms"))
                 except:
                    print("ERROR: Could not parse time string column")
        
        # Finalize DataFrame (keep only needed columns)
        # Rename 'time_ms' to 'time'
        if "time_ms" in df.columns:
            df = df.drop("time").rename({"time_ms": "time"})
            
        # Ensure we have required columns
        req_cols = ["time", "open", "high", "low", "close"]
        for c in req_cols:
            if c not in df.columns:
                 raise HTTPException(400, f"Missing required column: {c}. Found: {df.columns}")

        # Update State
        data_state.loaded = True
        data_state.filename = file.filename
        data_state.total_rows = len(df)
        
        # Calculate Min/Max Dates from the Data
        # timestamp(ms) -> datetime -> string
        min_ts = df["time"].min()
        max_ts = df["time"].max()
        
        data_state.min_date = datetime.fromtimestamp(min_ts / 1000.0).strftime("%Y-%m-%d")
        data_state.max_date = datetime.fromtimestamp(max_ts / 1000.0).strftime("%Y-%m-%d")
        
        # Set Default Active Range to Full Range
        data_state.active_start = data_state.min_date
        data_state.active_end = data_state.max_date
        
        print(f"DEBUG: State Updated. Range: {data_state.min_date} - {data_state.max_date}")
        
        # Load Shared Memory
        # In real app, we use unique ID. For now 'main_data'
        # memory_manager.load_dataframe('main_data', df) # Assuming this exists or mocked
        
        return {
            "status": "ok", 
            "rows": len(df),
            "range_start": data_state.min_date,
            "range_end": data_state.max_date
        }
        
    except Exception as e:
        print(f"UPLOAD ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(500, detail=f"Processing Error: {str(e)}")
    finally:
        if os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except: pass

@router.post("/load_local")
def load_local_file():
    """
    Loads the specific US100.M1.utc2.csv file from the URB_Optimizer/data folder.
    This is a shortcut for the user's test case.
    """
    # Hardcoded path as requested for the test
    file_path = r"C:\Users\Shakti Ayala\AppData\Roaming\MetaQuotes\Terminal\A04693C82B55C771297FDD766AEA5652\MQL5\Experts\Ultimate Range Breaker - copia\URB_Optimizer\data\US100.M1.utc2.csv"
    
    if not os.path.exists(file_path):
        raise HTTPException(404, f"File not found at {file_path}")
        
    try:
        # MT5 Export Format usually: Date, Time, Open, High, Low, Close, TickVol, Vol, Spread
        # No Header based on checks
        
        # 1. Read CSV
        df = pl.read_csv(
            file_path,
            has_header=False,
            new_columns=["date", "time", "open", "high", "low", "close", "tick_vol", "vol", "spread"]
        )
        
        # 2. Parse Date and Time into Timestamp (Milliseconds)
        # Combine Date and Time strings: "2012.01.19" + " " + "18:15" -> "2012.01.19 18:15"
        # Format: %Y.%m.%d %H:%M
        
        df = df.with_columns(
            (pl.col("date") + " " + pl.col("time")).alias("datetime_str")
        )
        
        # Convert to Timestamp (Easiest way in Polars: strptime to Datetime, then check unit)
        df = df.with_columns(
            pl.col("datetime_str").str.to_datetime("%Y.%m.%d %H:%M").cast(pl.Int64).alias("time") 
        )
        # Note: Polars cast(pl.Int64) on Datetime defaults to Microseconds usually? 
        # Check: datetime[us] -> cast(pl.Int64) gives microseconds.
        # We need Milliseconds.
        # Polars default is Microseconds.
        # So we divide by 1000.
        
        df = df.with_columns(
            (pl.col("time") / 1000).cast(pl.Int64).alias("time")
        )

        # 3. Select columns needed
        df = df.select(["time", "open", "high", "low", "close", "spread"])
        
        # 4. Update State
        data_state.loaded = True
        data_state.filename = "US100.M1.Real"
        data_state.total_rows = len(df)
        
        # Get Min/Max Dates for UI
        # We can just take first and last timestamp
        min_ts = df["time"][0] / 1000 # back to seconds for datetime.fromtimestamp
        max_ts = df["time"][-1] / 1000
        
        data_state.min_date = datetime.fromtimestamp(min_ts).strftime("%Y-%m-%d")
        data_state.max_date = datetime.fromtimestamp(max_ts).strftime("%Y-%m-%d")
        
        data_state.active_start = data_state.min_date
        data_state.active_end = data_state.max_date
        
        # 5. Load Shared Memory
        memory_manager.load_dataframe('main_data', df)
        
        return {"status": "ok", "rows": len(df), "range": f"{data_state.min_date} to {data_state.max_date}"}

    except Exception as e:
        print(f"Error loading local: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(500, detail=str(e))
