# URB Optimizer - Ultimate Range Breaker Optimization System

A Python-based optimization framework for the Ultimate Range Breaker EA.

## Setup

```bash
cd URB_Optimizer
pip install -r requirements.txt
```

## Project Structure

```
URB_Optimizer/
├── config/
│   └── broker_config.py     # FTMO specifications
├── data/
│   └── (place your tick CSV files here)
├── src/
│   ├── data_loader.py       # Load and process tick data
│   ├── range_breaker.py     # Strategy logic
│   ├── backtester.py        # Trade simulation
│   ├── optimizer.py         # Parameter optimization
│   └── stress_tests.py      # Monte Carlo & validation
├── output/
│   └── (generated reports and .set files)
├── requirements.txt
└── run_optimization.py      # Main entry point
```

## Usage

1. Place tick data CSV in `data/` folder (e.g., `US100_ticks.csv`)
2. Run: `python run_optimization.py`
