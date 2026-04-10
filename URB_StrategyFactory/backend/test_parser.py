import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '.')))

from app.core.mql5_parser import MQL5Parser
import json

file_path = "backend/strategies_source/DualEA.mq5"
# Or check the other one
file_path2 = "backend/strategies_source/Ultimate H4 LSweep.mq5"

try:
    print("Trying DualEA")
    parser = MQL5Parser(file_path)
    parser.read_file()
    inputs = parser.parse_inputs()
    for inp in inputs:
        if "RiskType" in inp['name'] or inp['type'] == 'enum':
            print(f"Name: {inp['name']}")
            print(f"Type: {inp['type']}")
            print(f"Options: {json.dumps(inp.get('options', []), indent=2)}")
except Exception as e:
    print(f"DualEA failed: {e}")

try:
    print("\nTrying Ultimate H4 LSweep")
    parser = MQL5Parser(file_path2)
    parser.read_file()
    inputs = parser.parse_inputs()
    for inp in inputs:
        if "RiskType" in inp['name'] or inp['type'] == 'enum':
            print(f"Name: {inp['name']}")
            print(f"Type: {inp['type']}")
            print(f"Options: {json.dumps(inp.get('options', []), indent=2)}")
except Exception as e:
    print(f"Ultimate failed: {e}")
