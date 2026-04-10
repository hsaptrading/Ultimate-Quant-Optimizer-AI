"""
Data Loader Module for SQX Tick Data

Loads CSV tick data from StrategyQuant X format:
DateTime,Bid,Ask,Volume
20250623 01:08:47.793,21510.9,21512.6,1
"""

import pandas as pd
import numpy as np
from pathlib import Path
from datetime import datetime, timedelta
import pyarrow.parquet as pq
import pyarrow as pa
from tqdm import tqdm
import os

# Add parent directory to path for config import
import sys
sys.path.append(str(Path(__file__).parent.parent))
from config.broker_config import FTMO_US100, SERVER_TIMEZONE


def parse_sqx_datetime(dt_str: str) -> datetime:
    """
    Parse SQX datetime formats:
    - Format 1: YYYYMMDD HH:MM:SS.mmm (e.g., 20250623 01:08:47.793)
    - Format 2: YYYY.MM.DD HH:MM:SS.mmm (e.g., 2025.06.23 01:08:47.943)
    """
    # List of formats to try
    formats = [
        "%Y.%m.%d %H:%M:%S.%f",  # 2025.06.23 01:08:47.943
        "%Y.%m.%d %H:%M:%S",     # 2025.06.23 01:08:47
        "%Y%m%d %H:%M:%S.%f",    # 20250623 01:08:47.793
        "%Y%m%d %H:%M:%S",       # 20250623 01:08:47
    ]
    
    for fmt in formats:
        try:
            return datetime.strptime(dt_str.strip(), fmt)
        except ValueError:
            continue
    
    raise ValueError(f"Unable to parse datetime: {dt_str}")


def load_tick_data(filepath: str, 
                   start_date: str = None, 
                   end_date: str = None,
                   use_cache: bool = True,
                   chunk_size: int = 1_000_000) -> pd.DataFrame:
    """
    Load SQX tick data from CSV file with optional caching.
    
    Args:
        filepath: Path to CSV file
        start_date: Optional start date filter (YYYY-MM-DD)
        end_date: Optional end date filter (YYYY-MM-DD)
        use_cache: Whether to use/create Parquet cache
        chunk_size: Rows per chunk for memory-efficient loading
        
    Returns:
        DataFrame with columns: datetime, bid, ask, spread
    """
    filepath = Path(filepath)
    cache_path = filepath.with_suffix('.parquet')
    
    # Try to load from cache if available and use_cache enabled
    if use_cache and cache_path.exists():
        cache_mtime = cache_path.stat().st_mtime
        csv_mtime = filepath.stat().st_mtime
        
        if cache_mtime > csv_mtime:
            print(f"Loading from cache: {cache_path}")
            df = pd.read_parquet(cache_path)
            return _filter_dates(df, start_date, end_date)
    
    print(f"Loading tick data from: {filepath}")
    print("This may take a few minutes for large files...")
    
    # Read CSV in chunks for memory efficiency
    chunks = []
    total_rows = 0
    
    # Count total rows for progress bar (fast line count)
    with open(filepath, 'r') as f:
        total_lines = sum(1 for _ in f)  # No header to subtract
    
    # Read and process in chunks
    # File has no header and 3 columns: datetime, bid, ask
    reader = pd.read_csv(
        filepath,
        chunksize=chunk_size,
        header=None,  # No header in file
        names=['datetime_str', 'bid', 'ask'],  # 3 columns only
        parse_dates=False  # We'll parse manually for speed
    )
    
    with tqdm(total=total_lines, desc="Loading ticks") as pbar:
        for chunk in reader:
            # Try multiple datetime formats
            # Format 1: YYYY.MM.DD HH:MM:SS.mmm (e.g., 2025.06.23 01:08:47.943)
            chunk['datetime'] = pd.to_datetime(
                chunk['datetime_str'], 
                format='%Y.%m.%d %H:%M:%S.%f',
                errors='coerce'
            )
            
            # Format 2: Without milliseconds
            mask = chunk['datetime'].isna()
            if mask.any():
                chunk.loc[mask, 'datetime'] = pd.to_datetime(
                    chunk.loc[mask, 'datetime_str'],
                    format='%Y.%m.%d %H:%M:%S',
                    errors='coerce'
                )
            
            # Format 3: YYYYMMDD HH:MM:SS.mmm (no dots)
            mask = chunk['datetime'].isna()
            if mask.any():
                chunk.loc[mask, 'datetime'] = pd.to_datetime(
                    chunk.loc[mask, 'datetime_str'],
                    format='%Y%m%d %H:%M:%S.%f',
                    errors='coerce'
                )
            
            # Format 4: YYYYMMDD HH:MM:SS (no dots, no ms)
            mask = chunk['datetime'].isna()
            if mask.any():
                chunk.loc[mask, 'datetime'] = pd.to_datetime(
                    chunk.loc[mask, 'datetime_str'],
                    format='%Y%m%d %H:%M:%S',
                    errors='coerce'
                )
            
            # Calculate spread
            chunk['spread'] = chunk['ask'] - chunk['bid']
            
            # Keep only needed columns
            chunk = chunk[['datetime', 'bid', 'ask', 'spread']].dropna()
            
            chunks.append(chunk)
            total_rows += len(chunk)
            pbar.update(len(chunk))
    
    # Combine all chunks
    df = pd.concat(chunks, ignore_index=True)
    df = df.sort_values('datetime').reset_index(drop=True)
    
    print(f"Loaded {len(df):,} ticks from {df['datetime'].min()} to {df['datetime'].max()}")
    
    # Save to cache
    if use_cache:
        print(f"Saving cache to: {cache_path}")
        df.to_parquet(cache_path, index=False)
    
    return _filter_dates(df, start_date, end_date)


def _filter_dates(df: pd.DataFrame, start_date: str, end_date: str) -> pd.DataFrame:
    """Filter DataFrame by date range."""
    if start_date:
        start = pd.Timestamp(start_date)
        df = df[df['datetime'] >= start]
    if end_date:
        end = pd.Timestamp(end_date) + timedelta(days=1)
        df = df[df['datetime'] < end]
    return df.reset_index(drop=True)


def ticks_to_ohlc(ticks: pd.DataFrame, 
                  timeframe: str = '15min',
                  price_col: str = 'bid') -> pd.DataFrame:
    """
    Convert tick data to OHLC bars.
    
    Args:
        ticks: DataFrame with datetime, bid, ask columns
        timeframe: Pandas resample string ('1min', '5min', '15min', '1h', etc.)
        price_col: Which price to use ('bid', 'ask', 'mid')
        
    Returns:
        DataFrame with datetime, open, high, low, close, tick_volume, spread_avg
    """
    if price_col == 'mid':
        ticks = ticks.copy()
        ticks['price'] = (ticks['bid'] + ticks['ask']) / 2
        price_col = 'price'
    
    # Set datetime as index for resampling
    df = ticks.set_index('datetime')
    
    # Resample to OHLC
    ohlc = df[price_col].resample(timeframe).ohlc()
    
    # Add tick volume and average spread
    ohlc['tick_volume'] = df[price_col].resample(timeframe).count()
    ohlc['spread_avg'] = df['spread'].resample(timeframe).mean()
    
    # Drop bars with no data
    ohlc = ohlc.dropna()
    
    # Reset index to make datetime a column
    ohlc = ohlc.reset_index()
    
    # Add bar index for easy reference
    ohlc['bar_index'] = range(len(ohlc))
    
    return ohlc


def create_m15_data(tick_filepath: str,
                    start_date: str = None,
                    end_date: str = None,
                    use_cache: bool = True) -> pd.DataFrame:
    """
    Convenience function to load ticks and convert to M15 bars.
    
    Returns DataFrame with M15 OHLC data ready for backtesting.
    """
    # Check for M15 cache
    tick_path = Path(tick_filepath)
    m15_cache = tick_path.parent / f"{tick_path.stem}_M15.parquet"
    
    if use_cache and m15_cache.exists():
        tick_cache = tick_path.with_suffix('.parquet')
        if tick_cache.exists() and m15_cache.stat().st_mtime > tick_cache.stat().st_mtime:
            print(f"Loading M15 data from cache: {m15_cache}")
            df = pd.read_parquet(m15_cache)
            return _filter_dates(df, start_date, end_date)
    
    # Load ticks
    ticks = load_tick_data(tick_filepath, start_date, end_date, use_cache)
    
    # Convert to M15
    print("Converting to M15 bars...")
    m15 = ticks_to_ohlc(ticks, '15min', 'bid')
    
    # Save cache
    if use_cache:
        print(f"Saving M15 cache: {m15_cache}")
        m15.to_parquet(m15_cache, index=False)
    
    print(f"Created {len(m15):,} M15 bars")
    return m15


def get_data_info(filepath: str) -> dict:
    """Get basic info about a tick data file without loading all data."""
    filepath = Path(filepath)
    
    # Read just first line (no header in file)
    with open(filepath, 'r') as f:
        first_line = f.readline().strip()
    
    # Count lines efficiently
    with open(filepath, 'r') as f:
        line_count = sum(1 for _ in f)  # No header to subtract
    
    # Read last line
    with open(filepath, 'rb') as f:
        f.seek(-1000, 2)  # Go to near end
        last_lines = f.read().decode('utf-8', errors='ignore').split('\n')
        last_line = [l for l in last_lines if l.strip()][-1]
    
    # Parse dates
    first_parts = first_line.split(',')
    last_parts = last_line.split(',')
    
    first_dt = parse_sqx_datetime(first_parts[0])
    last_dt = parse_sqx_datetime(last_parts[0])
    
    return {
        'filepath': str(filepath),
        'file_size_mb': filepath.stat().st_size / (1024 * 1024),
        'total_ticks': line_count,
        'first_date': first_dt,
        'last_date': last_dt,
        'date_range_days': (last_dt - first_dt).days
    }


# Test function
if __name__ == "__main__":
    import sys
    
    if len(sys.argv) > 1:
        filepath = sys.argv[1]
        
        print("=== Data File Info ===")
        info = get_data_info(filepath)
        for k, v in info.items():
            print(f"  {k}: {v}")
        
        print("\n=== Loading Sample Data ===")
        # Load just 1 day of data for testing
        ticks = load_tick_data(filepath, use_cache=False)
        print(f"\nTick data sample:\n{ticks.head(10)}")
        
        print("\n=== Converting to M15 ===")
        m15 = ticks_to_ohlc(ticks.head(100000), '15min')
        print(f"\nM15 data sample:\n{m15.head(20)}")
    else:
        print("Usage: python data_loader.py <path_to_tick_csv>")
