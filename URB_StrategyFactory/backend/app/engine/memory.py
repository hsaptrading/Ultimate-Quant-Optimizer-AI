import multiprocessing
from multiprocessing import shared_memory
import numpy as np
import polars as pl
import pickle

class SharedMemoryManager:
    """
    Manages shared memory blocks for large DataFrames to be accessed by worker processes
    without duplication.
    """
    def __init__(self):
        self._shm_blocks = {} # name -> SharedMemory
        self._metadata = {}   # name -> dict (shape, dtype, column_names)

    def load_dataframe(self, name: str, df: pl.DataFrame):
        """
        Loads a Polars DataFrame into shared memory.
        Stores each column as a separate numpy array in shared memory.
        """
        if name in self._metadata:
            self.free_memory(name)
            
        print(f"[MemoryManager] Loading '{name}' into shared memory...")
        
        meta = {
            'columns': {},
            'row_count': df.height
        }
        
        # Iterate over columns
        for col_name in df.columns:
            # Convert to numpy (zero copy if possible, but for shm we need copy usually)
            series = df[col_name]
            np_arr = series.to_numpy()
            
            # Create Shared Memory Block
            shm = shared_memory.SharedMemory(create=True, size=np_arr.nbytes)
            
            # Create a numpy array backed by shared memory
            shm_arr = np.ndarray(np_arr.shape, dtype=np_arr.dtype, buffer=shm.buf)
            
            # Copy data
            shm_arr[:] = np_arr[:]
            
            # Store references
            block_id = f"{name}__{col_name}"
            self._shm_blocks[block_id] = shm
            
            # Store Metadata needed to reconstruct
            meta['columns'][col_name] = {
                'shm_name': shm.name,
                'shape': np_arr.shape,
                'dtype': str(np_arr.dtype),
                'block_id': block_id
            }
            
        self._metadata[name] = meta
        print(f"[MemoryManager] '{name}' loaded. Columns: {list(meta['columns'].keys())}")
        return meta

    def get_metadata(self, name: str):
        return self._metadata.get(name)

    def free_memory(self, name: str):
        """Unlinks and releases shared memory for a dataset."""
        if name not in self._metadata:
            return
            
        meta = self._metadata[name]
        for col_name, info in meta['columns'].items():
            block_id = info['block_id']
            if block_id in self._shm_blocks:
                shm = self._shm_blocks[block_id]
                shm.close()
                shm.unlink() # Destroy from OS
                del self._shm_blocks[block_id]
        
        del self._metadata[name]
        print(f"[MemoryManager] Freed '{name}'")

    def cleanup(self):
        """Free all memory."""
        keys = list(self._metadata.keys())
        for k in keys:
            self.free_memory(k)

class MemoryClient:
    """
    Used by Worker processes to attach to existing shared memory.
    """
    def __init__(self, metadata):
        self.metadata = metadata
        self._shm_objects = [] # Keep refs to close later
        
    def get_data(self):
        """
        Reconstructs the Dictionary of Numpy Arrays (Lightweight)
        Does NOT rebuild Polars DataFrame to save RAM, unless needed.
        Returns: dict {col_name: np.array}
        """
        data = {}
        row_count = self.metadata['row_count']
        
        for col_name, info in self.metadata['columns'].items():
            shm_name = info['shm_name']
            dtype = info['dtype']
            shape = info['shape']
            
            # Attach to existing SHM
            try:
                shm = shared_memory.SharedMemory(name=shm_name)
                self._shm_objects.append(shm)
                
                # Create numpy view
                arr = np.ndarray(shape, dtype=dtype, buffer=shm.buf)
                data[col_name] = arr
            except FileNotFoundError:
                print(f"[Error] Shared Memory {shm_name} not found.")
                
        return data

    def close(self):
        """Close connections (do not unlink!)."""
        for shm in self._shm_objects:
            shm.close()
        self._shm_objects = []
