import os
import subprocess
import uuid
import time
import shutil
from typing import Dict, Any

class MT5FarmController:
    """
    Manages headless MetaTrader 5 instances for executing custom EAs.
    This acts as the bridge for our Hybrid Simulation Architecture.
    """
    
    def __init__(self, terminal_path: str, expert_name: str, symbol: str, timeframe: str = "M15", max_nodes: int = 1):
        self.terminal_path = terminal_path
        self.expert_name = expert_name
        self.symbol = symbol
        self.timeframe = timeframe
        self.max_nodes = max_nodes
        
        # Temp dir for this optimization run's configs and reports
        import tempfile
        self.temp_dir = os.path.abspath(os.path.join(tempfile.gettempdir(), "_mt5_farm_temp"))
        if not os.path.exists(self.temp_dir):
            os.makedirs(self.temp_dir)
            
        self.nodes = [] # Will store paths to the isolated terminal64.exe clones

    def clone_nodes(self, original_data_path: str):
        """
        Creates isolated Portable MT5 instances to bypass the "Single Instance" restriction.
        Uses Windows Directory Junctions (mklink /J) to share the massive History/Bases folder,
        ensuring we don't duplicate gigabytes of broker data but still isolate execution.
        """
        import shutil
        import subprocess
        
        if self.terminal_path.lower().endswith(".exe"):
            base_terminal_dir = os.path.dirname(self.terminal_path)
        else:
            base_terminal_dir = self.terminal_path
        
        print(f"[Farm] Generating {self.max_nodes} isolated MT5 Node(s) from {base_terminal_dir}...")
        for i in range(1, self.max_nodes + 1):
            node_dir = os.path.join(self.temp_dir, f"Node_{i}")
            node_exe = os.path.join(node_dir, "terminal64.exe")
            
            if not os.path.exists(node_dir):
                os.makedirs(node_dir)
                # Copy minimum required structural files
                for f in ["terminal64.exe", "mql564.dll", "metatester64.exe"]:
                    src = os.path.join(base_terminal_dir, f)
                    if os.path.exists(src):
                        shutil.copy2(src, os.path.join(node_dir, f))
                
                # Copy MQL5 folder (This contains the .ex5 expert files, required for testing)
                src_mql5 = os.path.join(original_data_path, "MQL5")
                dst_mql5 = os.path.join(node_dir, "MQL5")
                if os.path.exists(src_mql5) and not os.path.exists(dst_mql5):
                    # Copy tree, ignoring huge files if needed, but MQL5 is usually small
                    shutil.copytree(src_mql5, dst_mql5, dirs_exist_ok=True)
                    
                # Create Junctions for critical MT5 folders securely
                for junction_target in ["config", "bases"]:
                    src_target = os.path.join(original_data_path, junction_target)
                    dst_target = os.path.join(node_dir, junction_target)
                    if os.path.exists(src_target) and not os.path.exists(dst_target):
                        # CMD mklink /J Destination Source
                        cmd = f'mklink /J "{dst_target}" "{src_target}"'
                        subprocess.run(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            
            self.nodes.append(node_exe)
        
        print(f"[Farm] Successfully provisioned {len(self.nodes)} execution nodes.")

    def _generate_set_file(self, params: Dict[str, Any], file_path: str):
        """
        Creates a .set file from the passed parameters.
        Keys are mapped exactly line by line.
        """
        with open(file_path, "w") as f:
            for k, v in params.items():
                if k == "id" or k == "fitness" or k.startswith("__"): continue # Internal UI params & Virtual params
                
                # Format booleans securely
                if isinstance(v, bool):
                    v_str = "true" if v else "false"
                elif isinstance(v, float):
                    v_str = f"{v:.5f}" # Standard MT5 precision
                else:
                    v_str = str(v)
                    
                f.write(f"{k}={v_str}\n")
                
    def _generate_tester_ini(self, ini_path: str, set_path: str, report_name: str, 
                             start_date: str, end_date: str, deposit: float = 100000, override_timeframe: str = None):
        """
        Generates the configuration file that MT5 terminal64.exe consumes.
        Forces the terminal into Headless Tester mode.
        """
        
        # Determine internal timeframe string MT5 expects
        tf_to_use = override_timeframe if override_timeframe else self.timeframe
        period_map = {"M1": "M1", "M5": "M5", "M15": "M15", "M30": "M30", "H1": "H1", "H4": "H4", "D1": "D1"}
        mapped_period = period_map.get(tf_to_use, "M15")

        config = f"""[Common]
Login=
Password=
Server=

[Tester]
Expert={self.expert_name}
ExpertParameters={set_path}
Symbol={self.symbol}
Period={mapped_period}
Optimization=0
Model=1
FromDate={start_date}
ToDate={end_date}
ForwardMode=0
Deposit={int(deposit)}
Currency=USD
ProfitInPips=0
Leverage=100
ExecutionMode=0
Visual=0
Report={report_name}
ReplaceReport=1
ShutdownTerminal=1
"""
        with open(ini_path, "w") as f:
            f.write(config)
            
    def _parse_mt5_xml_report(self, report_xml_path: str) -> Dict[str, float]:
        """
        Parses the output XML generated by MT5 to extract fitness metrics.
        Returns NetProfit, TotalTrades, WinRate.
        """
        metrics = {"NetProfit": -999999.0, "Trades": 0.0, "WinRate": 0.0}
        
        if not os.path.exists(report_xml_path):
            if os.path.exists(report_xml_path + ".htm"):
                report_xml_path += ".htm"
            else:
                return metrics
            
        try:
            with open(report_xml_path, "r", encoding="utf-16", errors="ignore") as f:
                content = f.read()
                
            # If MT5 sometimes drops utf-8 depending on system language:
            if not content or ("<?xml" not in content[:200] and "html" not in content[:200].lower()):
                with open(report_xml_path, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read()

            import re
            
            is_html = report_xml_path.endswith(".htm")
            
            if is_html:
                # MT5 HTML Parser
                profit_c = re.search(r'Total Net Profit:</td>.*?<td[^>]*>(.*?)</td>', content, re.IGNORECASE | re.DOTALL)
                trades_c = re.search(r'Total Trades:</td>.*?<td[^>]*>(.*?)</td>', content, re.IGNORECASE | re.DOTALL)
                winrate_c = re.search(r'Profit Trades.*?%.*?total.*?:</td>.*?<td[^>]*>.*?\((.*?)%\).*?</td>', content, re.IGNORECASE | re.DOTALL)
                
                if profit_c:
                    clean_str = re.sub(r'<[^>]+>', '', profit_c.group(1)) # Strip bold tags
                    if "," in clean_str and "." not in clean_str: clean_str = clean_str.replace(",", ".") # Euro format
                    clean_str = re.sub(r'[^\d\.-]', '', clean_str)
                    if clean_str and clean_str != "-": metrics["NetProfit"] = float(clean_str)
                if trades_c:
                    clean_t = re.sub(r'<[^>]+>', '', trades_c.group(1))
                    clean_t = re.sub(r'[^\d]', '', clean_t)
                    if clean_t: metrics["Trades"] = float(clean_t)
                if winrate_c:
                    clean_w = re.sub(r'<[^>]+>', '', winrate_c.group(1))
                    if "," in clean_w and "." not in clean_w: clean_w = clean_w.replace(",", ".")
                    clean_w = re.sub(r'[^\d\.-]', '', clean_w)
                    if clean_w and clean_w != "-": metrics["WinRate"] = float(clean_w)
            else:
                # MT5 XML Parser
                profit_match = re.search(r'Total net profit.*?<Data ss:Type="Number">([-0-9.]+)</Data>', content, re.IGNORECASE | re.DOTALL)
                trades_match = re.search(r'Total trades.*?<Data ss:Type="Number">([0-9]+)</Data>', content, re.IGNORECASE | re.DOTALL)
                profit_trades_match = re.search(r'Profit trades.*?<Data ss:Type="Number">([0-9]+)</Data>', content, re.IGNORECASE | re.DOTALL)
                
                if profit_match:
                    metrics["NetProfit"] = float(profit_match.group(1))
                if trades_match:
                    metrics["Trades"] = float(trades_match.group(1))
                    total = metrics["Trades"]
                    if total > 0 and profit_trades_match:
                        wins = float(profit_trades_match.group(1))
                        metrics["WinRate"] = (wins / total) * 100.0

        except Exception as e:
            print(f"[MT5Farm] Error parsing report: {e}")
            
        return metrics

    def execute_worker_test(self, params: Dict[str, Any], exe_path: str, start_date: str = "2024.01.01", end_date: str = "2024.12.31", override_timeframe: str = None) -> Dict[str, Any]:
        """
        The main worker loop. Injected by multiprocessing pool.
        1. Writes temp files.
        2. Executes headless terminal.
        3. Waits for completion.
        4. Parses & cleans up.
        """
        worker_id = str(uuid.uuid4())[:8]
        set_path = os.path.join(self.temp_dir, f"worker_{worker_id}.set")
        ini_path = os.path.join(self.temp_dir, f"worker_{worker_id}.ini")
        rep_name = f"report_{worker_id}.xml" # Explicit extension forces MT5 to produce XML
        
        node_dir = os.path.dirname(exe_path)
        # MT5 saves report to terminal data folder root (node_dir) if relative path is given without leading slash
        rep_path = os.path.join(node_dir, rep_name)
        
        virtual_tf = params.get('__EXEC_TIMEFRAME__', override_timeframe)
        
        # 1. Prepare Environment
        self._generate_set_file(params, set_path)
        
        # Note: MT5 needs relative or absolute paths. For safety, absolute:
        self._generate_tester_ini(
            ini_path=ini_path,
            set_path=set_path,
            report_name=rep_name,
            start_date=start_date,
            end_date=end_date,
            override_timeframe=virtual_tf
        )
        
        # 2. Add the .set file path into the ini via CLI override since MT5 [Tester] block doesn't natively accept .set path inside .ini easily.
        # Wait - actually, the CLI command accepts /set: parameter.
        # But wait, we can also just copy the set file to the MetaTrader Terminal/MQL5/Profiles/Tester folder if needed.
        # The best way is to pass `/set:path` via CLI
        
        cmd_str = f'"{exe_path}" /portable /config:"{ini_path}"'
        
        # 3. Execution (MT5 is non-blocking, spawns and returns)
        try:
             subprocess.run(cmd_str, shell=True, cwd=os.path.dirname(exe_path), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
             return {"id": params.get("id"), "error": str(e), "NetProfit": -999999}

        # 4. Wait for Report File
        start_wait = time.time()
        timeout_sec = 240 # EA can take long
        report_found = False
        import time as _time
        while _time.time() - start_wait < timeout_sec:
             check_path = rep_path + ".htm"
             if os.path.exists(check_path):
                 try:
                     with open(check_path, 'r', encoding='utf-16', errors='ignore') as check_f:
                         content_check = check_f.read()
                         if "</html>" in content_check.lower() or "</body>" in content_check.lower():
                             _time.sleep(1) # Extra second to ensure file lock is released
                             report_found = True
                             break
                 except Exception:
                     pass
             elif os.path.exists(rep_path):
                 # Fallback if MT5 decides to write raw XML
                 # Usually XML is written all at once but we check size
                 if os.path.getsize(rep_path) > 100:
                     _time.sleep(1)
                     report_found = True
                     break
             _time.sleep(2)
             
        if not report_found:
             return {"id": params.get("id"), "error": "Timeout: No Report generated completely", "NetProfit": -999999}

        # 5. Result Parsing
        metrics = self._parse_mt5_xml_report(rep_path)
        metrics["id"] = params.get("id", "unknown")
        
        # 4.5 Error Diagnostic: if no trades were executed, check the MT5 Logs for the specific node to see why it aborted
        if metrics.get("Trades", 0) == 0:
            # Tester logs usually sit at: C:\Users\xxx\AppData\Roaming\MetaQuotes\Terminal\YYYY\tester\logs\
            # `exe_path` holds the full node path which ends in \terminal64.exe
            # The node data folder IS the node_folder (due to /portable install emulation, or because we cloned it).
            node_dir = os.path.dirname(exe_path)
            logs_dir = os.path.join(node_dir, "tester", "logs")
            log_error_snippet = "No error log found"
            
            if os.path.exists(logs_dir):
                # Find most recently modified .log file
                log_files = [os.path.join(logs_dir, f) for f in os.listdir(logs_dir) if f.endswith('.log')]
                if log_files:
                    latest_log = max(log_files, key=os.path.getmtime)
                    try:
                        with open(latest_log, "r", encoding="utf-16", errors="ignore") as lf:
                            log_content = lf.read()
                            # If utf-16 failed to decipher, try utf-8
                            if not log_content or "ÿþ" in log_content:
                                with open(latest_log, "r", encoding="utf-8", errors="ignore") as lf2:
                                    log_content = lf2.read()
                                    
                        # Look for common MT5 abort triggers
                        critical_errors = []
                        for line in log_content.splitlines():
                            if any(err in line.lower() for err in ["cannot load", "invalid", "not found", "initialization failed", "zero divide", "array out of range", "timeout"]):
                                critical_errors.append(line.strip())
                                
                        if critical_errors:
                           log_error_snippet = " \n".join(critical_errors[-3:]) # Last 3 errors to prevent huge blobs
                        else:
                           log_error_snippet = "Read logs OK, but no explicit ERROR lines found. Strategy might logically not take trades."
                           
                    except Exception as le:
                        log_error_snippet = f"Could not parse log file: {le}"
                        
            metrics["error_log"] = log_error_snippet
            print(f"[MT5 DIAGNOSTIC - Worker {worker_id}]\n" + ("-"*40) + f"\n{log_error_snippet}\n" + ("-"*40))
        
        # 5. Cleanup
        try:
            # Temporarily disabled cleanup for debugging
            # if os.path.exists(set_path): os.remove(set_path)
            # if os.path.exists(ini_path): os.remove(ini_path)
            # if os.path.exists(rep_path): os.remove(rep_path)
            pass
        except: pass
        
        return metrics

def run_farm_batch_backtest(args_tuple):
    """
    Wrapper for multiprocessing Pool.map().
    args_tuple = (controller_instance, list_of_params, node_exe_path, start_date, end_date)
    """
    controller, chunks, node_exe_path, start_date, end_date = args_tuple
    results = []
    for params in chunks:
        res = controller.execute_worker_test(params, node_exe_path, start_date, end_date)
        results.append(res)
    return results
