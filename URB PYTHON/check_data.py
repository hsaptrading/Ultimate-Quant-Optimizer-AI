
import polars as pl
import sys

try:
    df = pl.read_parquet("USATECHIDXUSD.tick.utc2_M1.parquet")
    print(f"Rows: {df.height}")
    print(f"Start: {df['time'].min()}")
    print(f"End: {df['time'].max()}")
except Exception as e:
    print(f"Error: {e}")
