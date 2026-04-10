"""
Data Loader Module for M1 OHLC Data (Generic)

Loads M1 CSV data typically exported from MT5 or other sources.
Expected format (standard MT5 export often lacks header):
<DATE>,<TIME>,<OPEN>,<HIGH>,<LOW>,<CLOSE>,<TICKVOL>,<VOL>,<SPREAD>
or
YYYY.MM.DD,HH:MM,OPEN,HIGH,LOW,CLOSE,TICKVOL,VOL,SPREAD
"""

import pandas as pd
import numpy as np
from pathlib import Path
from datetime import datetime, timedelta
import os

def load_m1_data(filepath: str, 
                 start_date: str = None, 
                 end_date: str = None,
                 use_cache: bool = True) -> pd.DataFrame:
    """
    Load M1 OHLC data from CSV file with optional caching/parquet.
    
    Args:
        filepath: Path to CSV file
        start_date: Optional start date filter (YYYY-MM-DD)
        end_date: Optional end date filter (YYYY-MM-DD)
        use_cache: Whether to use/create Parquet cache
        
    Returns:
        DataFrame with columns: datetime, open, high, low, close, tick_volume, spread
    """
    filepath = Path(filepath)
    cache_path = filepath.with_suffix('.parquet')
    
    # Try to load from cache
    if use_cache and cache_path.exists():
        # Check timestamp to ensure cache is fresh
        if cache_path.stat().st_mtime > filepath.stat().st_mtime:
            print(f"Loading M1 data from cache: {cache_path.name}")
            df = pd.read_parquet(cache_path)
            return _filter_dates(df, start_date, end_date)
            
    print(f"Loading M1 data from CSV: {filepath.name}")
    print("This may take a moment...")
    
    # Determine if file has header
    # Simple heuristic: read first line, check if it contains letters
    with open(filepath, 'r') as f:
        header_line = f.readline().strip()
        has_header = any(c.isalpha() for c in header_line.replace(',', '').replace('.', ''))
    
    # Define generic MT5 column names
    col_names = ['date', 'time', 'open', 'high', 'low', 'close', 'tick_volume', 'vol', 'spread']
    use_cols = ['date', 'time', 'open', 'high', 'low', 'close', 'tick_volume', 'spread']
    
    # If file has fewer columns, adjust
    # Typical compact M1: Date, Time, Open, High, Low, Close, Vol
    # Count separators
    sep_count = header_line.count(',') or header_line.count('\t')
    
    # Read CSV
    # Optimized for speed: specify dtypes where possible
    try:
        df = pd.read_csv(
            filepath,
            header=0 if has_header else None,
            names=col_names if not has_header else None,
            engine='c',
            sep=',' if ',' in header_line else '\t'
        )
        
        # Normalize column names to lowercase
        df.columns = [c.lower().strip() for c in df.columns]
        
        # Merge Date and Time columns if they exist separately
        if 'date' in df.columns and 'time' in df.columns:
            # Vectorized string concat is faster
            # Verify format first. MT5 is usually YYYY.MM.DD and HH:MM
            # Pandas to_datetime is smart but faster if we give format
            dt_series = df['date'].astype(str) + ' ' + df['time'].astype(str)
            df['datetime'] = pd.to_datetime(dt_series, format='%Y.%m.%d %H:%M')
            df.drop(columns=['date', 'time'], inplace=True)
            
        elif '<date>' in df.columns and '<time>' in df.columns:
             # Standard MT5 export header
             dt_series = df['<date>'].astype(str) + ' ' + df['<time>'].astype(str)
             df['datetime'] = pd.to_datetime(dt_series, format='%Y.%m.%d %H:%M:%S')
             
             # Rename OHLC
             rename_map = {
                 '<open>': 'open', '<high>': 'high', '<low>': 'low', '<close>': 'close', 
                 '<tickvol>': 'tick_volume', '<vol>': 'vol', '<spread>': 'spread'
             }
             df.rename(columns=rename_map, inplace=True)
             df.drop(columns=['<date>', '<time>'], inplace=True)
             
        # Ensure we have required columns
        req_cols = ['datetime', 'open', 'high', 'low', 'close']
        if not all(c in df.columns for c in req_cols):
             raise ValueError(f"CSV missing required columns. Found: {df.columns}")
             
        # Fill missing spread/volume if not present
        if 'spread' not in df.columns:
            df['spread'] = 10  # Default 10 points/pipettes
        if 'tick_volume' not in df.columns:
             df['tick_volume'] = 1

        # Sort and deduplicate
        df.sort_values('datetime', inplace=True)
        df.drop_duplicates('datetime', inplace=True)
        df.reset_index(drop=True, inplace=True)

        print(f"Loaded {len(df):,} M1 bars.")
        
        # Save cache
        if use_cache:
            print(f"Saving M1 cache to parquet...")
            df.to_parquet(cache_path, index=False)
            
        return _filter_dates(df, start_date, end_date)

    except Exception as e:
        print(f"Error parsing CSV: {e}")
        raise

def resample_m1_to_tf(m1_df: pd.DataFrame, timeframe: str) -> pd.DataFrame:
    """
    Resample M1 Data to a higher timeframe (M5, M15, H1, H4, D1).
    
    Args:
        m1_df: DataFrame with M1 data (must have datetime, open, high, low, close)
        timeframe: target timeframe string (e.g., '5min', '15min', '1h', '4h', '1d')
                   Note: Use standard Pandas offset aliases.
                   
    Returns:
        DataFrame resampled to new timeframe.
    """
    # Create copy to avoid modifying original
    df = m1_df.copy()
    df.set_index('datetime', inplace=True)
    
    # Resample Logic
    # OHLC aggregation
    agg_dict = {
        'open': 'first',
        'high': 'max',
        'low': 'min',
        'close': 'last',
        'tick_volume': 'sum',
        'spread': 'mean'
    }
    
    # Resample
    tf_df = df.resample(timeframe).agg(agg_dict)
    
    # Drop NAs (periods with no trading)
    tf_df.dropna(inplace=True)
    
    # Reset index to make datetime a column again
    tf_df.reset_index(inplace=True)
    
    print(f"Resampled M1 to {timeframe}: {len(tf_df):,} bars.")
    
    return tf_df

def _filter_dates(df: pd.DataFrame, start_date: str, end_date: str) -> pd.DataFrame:
    """Helper to filter by date"""
    if start_date:
        start = pd.Timestamp(start_date)
        df = df[df['datetime'] >= start]
    if end_date:
        end = pd.Timestamp(end_date) + timedelta(days=1)
        df = df[df['datetime'] < end]
    return df.reset_index(drop=True)

# Test execution
if __name__ == "__main__":
    import sys
    # Example usage
    if len(sys.argv) > 1:
        fpath = sys.argv[1]
        try:
            m1_data = load_m1_data(fpath, use_cache=False)
            print(m1_data.head())
            
            # Test Resample to H4
            h4_data = resample_m1_to_tf(m1_data, '4h')
            print("\nH4 Data Sample:")
            print(h4_data.head())
        except Exception as e:
            print(e)
    else:
        print("Drag and drop a CSV file onto this script to test.")
