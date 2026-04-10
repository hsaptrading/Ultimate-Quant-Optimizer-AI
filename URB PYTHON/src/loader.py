
import polars as pl
import os
import sys

class DataLoader:
    def __init__(self, csv_path: str):
        self.csv_path = csv_path
        self.parquet_path = csv_path.replace('.csv', '_M1.parquet')

    def convert_ticks_to_m1(self, force_rebuild=False):
        if os.path.exists(self.parquet_path) and not force_rebuild:
            print(f"[Loader] Loading cached M1 data from {self.parquet_path}")
            return pl.read_parquet(self.parquet_path)

        print(f"[Loader] Processing raw tick data from {self.csv_path} with BATCHED reader...")
        
        try:
            reader = pl.read_csv_batched(
                self.csv_path,
                has_header=False,
                new_columns=['datetime_str', 'bid', 'ask'],
                separator=',',
                batch_size=5_000_000, # 5 million rows per batch
                infer_schema_length=0
            )

            partial_aggs = []
            
            batch_count = 0
            while True:
                batch = reader.next_batches(1)
                if not batch:
                    break
                
                df_batch = batch[0]
                batch_count += 1
                print(f"Processing batch {batch_count}...")
                
                # Process this batch to M1
                # Format: "2025.06.23 01:08:47.793" -> "%Y.%m.%d %H:%M:%S.%f"
                
                m1_chunk = (
                    df_batch.with_columns(
                        pl.col('datetime_str').str.to_datetime('%Y.%m.%d %H:%M:%S.%3f').alias('time'),
                        pl.col('bid').cast(pl.Float64),
                        pl.col('ask').cast(pl.Float64)
                    )
                    .sort('time')
                    .group_by_dynamic('time', every='1m')
                    .agg([
                        pl.col('bid').first().alias('open'),
                        pl.col('bid').max().alias('high'),
                        pl.col('bid').min().alias('low'),
                        pl.col('bid').last().alias('close'),
                        pl.col('ask').mean().alias('ask_mean'),
                        pl.len().alias('tick_volume')
                    ])
                )
                
                partial_aggs.append(m1_chunk)
                
            print(f"[Loader] Merging {len(partial_aggs)} chunks...")
            
            if not partial_aggs:
                print("No data read.")
                return None
                
            # Concatenate all partial M1 chunks
            full_df = pl.concat(partial_aggs)
            
            # Re-aggregate to merge boundaries (if a minute was split across batches)
            final_m1 = (
                full_df.sort('time')
                .group_by('time')
                .agg([
                    pl.col('open').first(), # First of the first
                    pl.col('high').max(),
                    pl.col('low').min(),
                    pl.col('close').last(), # Last of the last
                    # Weighted mean for ask? Or just mean of means (approx)
                    pl.col('ask_mean').mean(), 
                    pl.col('tick_volume').sum()
                ])
                .sort('time')
                .with_columns(
                    (pl.col('ask_mean') - pl.col('close')).alias('spread_est')
                )
            )

            print(f"[Loader] Saving {final_m1.height} M1 bars to {self.parquet_path}")
            final_m1.write_parquet(self.parquet_path)
            return final_m1
            
        except Exception as e:
            print(f"[Loader] ERROR: {e}")
            import traceback
            traceback.print_exc()
            sys.exit(1)

if __name__ == "__main__":
    csv_file = "USATECHIDXUSD.tick.utc2.csv"
    if os.path.exists(csv_file):
        loader = DataLoader(csv_file)
        loader.convert_ticks_to_m1()
