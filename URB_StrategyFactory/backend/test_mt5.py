import os
import subprocess

ini_path = os.path.abspath("minimal.ini")
expert_name = "Advisors\\ExpertMACD"
terminal_path = r"C:\Program Files\FTMO MetaTrader 5\terminal64.exe"

ini_content = f"""[Tester]
Expert={expert_name}
Symbol=EURUSD
Period=M15
Model=1
Optimization=0
FromDate=2024.01.01
ToDate=2024.01.31
Report=myreport
ReplaceReport=1
ShutdownTerminal=1
"""
with open(ini_path, "w", encoding="utf-16le") as f:
    f.write(ini_content)

cmd_str = f'"{terminal_path}" /config:"{ini_path}"'
print(f"Running: {cmd_str}")
res = subprocess.run(cmd_str, shell=True, cwd=os.path.dirname(terminal_path), capture_output=True, text=True)

print(f"Exit code: {res.returncode}")
print(f"Stdout: {res.stdout}")
print(f"Stderr: {res.stderr}")
