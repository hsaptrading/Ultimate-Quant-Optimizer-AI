import random
import multiprocessing
import time
import uuid
import numpy as np
from ..core.state import data_state, strat_state
from .worker import init_worker, run_batch_backtest
from ..core.resource_manager import ResourceManager

class GeneticManager:
    def __init__(self, data_shm_name: str, data_info: dict):
        self.data_shm = data_shm_name
        self.data_shape = data_info if data_info is not None else {}
        self.pool = None
        self.is_running = False
        self.best_strategies = []
        self.farm_controller = None # Holds MT5FarmController if using MQ5
        
        # SQX Recommended Defaults
        self.crossover_prob = 0.70
        self.mutation_prob = 0.20 
        self.tournament_k = 3
        self.elitism_pct = 0.10
        
        # Schema definition (Will be set before evolution)
        self.param_ranges = {} 

    def set_config(self, param_config: dict):
        """
        Receives the parameter configuration from the UI/Backend (Builder ParamState).
        Format: { "ParamName": { "min": 10, "max": 50, "step": 5, "opt": True/False, "value": 20 } }
        """
        self.param_ranges = param_config

    def start_pool(self, cpu_cores: int = None, terminal_path: str = None, data_path: str = None, symbol: str = "EURUSD", timeframe: str = "M15"):
        # Calculate safe CPU Cores using Resource Manager if not specified
        if cpu_cores is None:
            res_manager = ResourceManager()
            # Try to get dataset size from memory dict if populated via metadata
            dataset_size = self.data_shape.get('bytes', 10 * 1024 * 1024) # Fallback 10MB
            cpu_cores = res_manager.calculate_optimal_workers(dataset_size_bytes=dataset_size)
            print(f"[GeneticManager] Auto-Detected Safe Resources -> Splitting into {cpu_cores} Workers (Dataset: ~{dataset_size//1024//1024} MB)")
            
        else:
            print(f"[GeneticManager] Starting Pool with forced {cpu_cores} workers...")
            
        worker_init_data = self.data_shape.copy()
        
        # Pull active strategy slug from state
        active_strat = strat_state.active_strategy_slug
        worker_init_data['active_strategy'] = active_strat 
        
        print(f"[GeneticManager] Python Native Strategy Detected: {active_strat}")
        
        # Fallback to absolute min/max if active selection is blank
        s_date = data_state.start_date if data_state.start_date else data_state.min_date
        e_date = data_state.end_date if data_state.end_date else data_state.max_date
        worker_init_data['start_date'] = s_date.replace('-', '.')
        worker_init_data['end_date'] = e_date.replace('-', '.')
        worker_init_data['symbol'] = symbol
        worker_init_data['timeframe'] = timeframe

        self.pool = multiprocessing.Pool(
            processes=cpu_cores,
            initializer=init_worker,
            initargs=(self.data_shm, worker_init_data)
        )
        self.is_running = True

    def stop_pool(self):
        if self.pool:
            self.pool.terminate()
            self.pool.join()
            self.pool = None
            
        self.is_running = False
        print("[GeneticManager] Pool Stopped.")

    def _random_value(self, name, conf):
        """Generates a random value respecting min/max/step/type."""
        
        # 1. Check Schema for Enum (String Handling)
        is_enum = False
        options = []
        is_virtual = False
        
        if conf.get('type') == 'virtual_enum':
            is_enum = True
            is_virtual = True
            options = conf.get('options', [])
        elif strat_state.active_schema:
            try:
                for inp in strat_state.active_schema.inputs:
                    if inp.name == name:
                        # Check if enum with options
                        # 'options' attribute added recently to StrategyInput
                        ops = getattr(inp, 'options', None) 
                        if (inp.type == 'enum' or getattr(inp, 'original_type', '').startswith('enum')) and ops:
                            is_enum = True
                            options = ops
                        break
            except: pass # Fallback if schema structure mismatch
        
        # 2. Enum Logic
        if is_enum and options:
             if is_virtual:
                 # Purely random choice from list of strings
                 if not conf.get('opt', False):
                     return options[0] if options else ""
                 return random.choice(options)
             else:
                 # Standard EA enum Logic (Return Integer Index)
                 def get_idx(val_str):
                     for i, opt in enumerate(options):
                         # Handle dict or obj access for options if needed (it matches Dict[str, str])
                         val = opt.get('value') if isinstance(opt, dict) else getattr(opt, 'value', '')
                         if str(val) == str(val_str): return i
                     return 0 # Default to 0 if not found
                 
                 # If NOT optimized, return fixed index
                 if not conf.get('opt', False):
                     return get_idx(conf.get('value'))
                 
                 # Optimization
                 start_idx = get_idx(conf.get('start'))
                 stop_idx = get_idx(conf.get('stop'))
                 step = int(float(conf.get('step', 1)))
                 if step < 1: step = 1
                 
                 if start_idx > stop_idx: start_idx, stop_idx = stop_idx, start_idx
                 
                 # Random choice from steps
                 # range(stop) is exclusive, so +1
                 possible_indices = list(range(start_idx, stop_idx + 1, step))
                 if not possible_indices: return start_idx
                 return random.choice(possible_indices)

        # 3. Standard Numeric/Bool Logic
        # If 'opt' is false, return fixed value
        if not conf.get('opt', False):
            val = conf.get('value', 0)
            if str(val).lower() == 'true': return True
            if str(val).lower() == 'false': return False
            return val

        # Optimization Enabled for Numbers
        try:
            min_v = float(conf.get('start', 0))
            max_v = float(conf.get('stop', 0))
            step = float(conf.get('step', 1))
        except ValueError:
            # Fallback if string passed but not identified as enum
            return conf.get('value', 0)
        
        if min_v >= max_v: return min_v
        
        # Calculate discrete steps
        if step <= 0: step = 1
        steps = int((max_v - min_v) / step)
        random_step = random.randint(0, steps)
        val = min_v + (random_step * step)
        
        # Infer Int vs Float
        # If step is int (1, 5) -> return int
        # If step is 0.1 -> return float logic
        # Also check if original type was int? 
        # For now, heuristic:
        if step == int(step) and min_v == int(min_v):
             return int(round(val))
        else:
             return float(round(val, 5))

    def generate_random_population(self, size: int):
        pop = []
        for _ in range(size):
            ind = {"id": str(uuid.uuid4())[:8]}
            # Iterate through configured params
            if self.param_ranges:
                for name, conf in self.param_ranges.items():
                    ind[name] = self._random_value(name, conf)
            else:
                 # Fallback if no config (Testing mostly)
                 pass
            pop.append(ind)
        return pop

    def evolve(self, population_size: int, generations: int, progress_callback=None):
        if not self.pool: raise Exception("Pool not started")
        
        population = self.generate_random_population(population_size)
        
        for g in range(generations):
            if not self.is_running: break
            
            # --- EVALUATION ---
            if not population: break
            
            chunk_size = max(1, len(population) // (self.pool._processes * 2))
            chunks = [population[i:i + chunk_size] for i in range(0, len(population), chunk_size)]
            
            results_nested = self.pool.map(run_batch_backtest, chunks)
            
            generation_results = []
            for sublist in results_nested: generation_results.extend(sublist)
            
            # Valid & Sort (Primary Fitness: NetProfit)
            valid_results = [r for r in generation_results if 'error' not in r and 'NetProfit' in r]
            valid_results.sort(key=lambda x: x['NetProfit'], reverse=True)
            
            # --- DATAMINING STORAGE ---
            self.best_strategies.extend(valid_results)
            self.best_strategies.sort(key=lambda x: x['NetProfit'], reverse=True)
            
            # Deduplicate
            seen_ids = set()
            unique_best = []
            for s in self.best_strategies:
                if s['id'] not in seen_ids:
                    unique_best.append(s)
                    seen_ids.add(s['id'])
            self.best_strategies = unique_best[:50]
            
            # Reports
            top_profit = self.best_strategies[0]['NetProfit'] if self.best_strategies else 0.0
            if progress_callback:
                progress_callback(g+1, generations, top_profit, self.best_strategies)
                
            # --- SELECTION & REPRODUCTION (SQX Logic) ---
            if g < generations - 1:
                res_map = {r['id']: r['NetProfit'] for r in valid_results}
                parents_pool = []
                for ind in population:
                    if ind['id'] in res_map:
                        ind['fitness'] = res_map[ind['id']]
                        parents_pool.append(ind)
                
                if not parents_pool: 
                    population = self.generate_random_population(population_size)
                    continue

                parents_pool.sort(key=lambda x: x['fitness'], reverse=True)
                
                # Elitism
                elite_count = max(1, int(population_size * self.elitism_pct))
                next_pop = [self.clone_ind(p) for p in parents_pool[:elite_count]]
                
                while len(next_pop) < population_size:
                    p1 = self.tournament(parents_pool, k=self.tournament_k)
                    p2 = self.tournament(parents_pool, k=self.tournament_k)
                    
                    if random.random() < self.crossover_prob:
                        child = self.crossover(p1, p2)
                    else:
                        child = self.clone_ind(p1)
                    
                    if random.random() < self.mutation_prob:
                        self.mutate(child)
                        
                    next_pop.append(child)
                
                population = next_pop

        self.stop_pool()

    def clone_ind(self, ind):
        return ind.copy()

    def tournament(self, pop, k=3):
        candidates = random.sample(pop, min(k, len(pop)))
        return max(candidates, key=lambda x: x['fitness'])

    def crossover(self, p1, p2):
        child = p1.copy()
        child['id'] = str(uuid.uuid4())[:8]
        if not self.param_ranges: 
            keys = list(p1.keys())
        else:
            keys = list(self.param_ranges.keys())
            
        for key in keys:
            if key not in p1 or key not in p2 or key in ['id', 'fitness']: continue
            if random.random() > 0.5:
                child[key] = p2[key]
        return child

    def mutate(self, ind):
        if not self.param_ranges: return
        mutation_keys = random.sample(list(self.param_ranges.keys()), k=max(1, int(len(self.param_ranges)*0.1)))
        
        for key in mutation_keys:
            conf = self.param_ranges[key]
            if conf.get('opt', False):
                ind[key] = self._random_value(key, conf)
