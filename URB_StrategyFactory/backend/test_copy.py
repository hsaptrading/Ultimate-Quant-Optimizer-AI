import shutil
import traceback
import sys
import os

src = r"C:\Program Files\FTMO MetaTrader 5\terminal64.exe"
dst = r"C:\Users\Shakti Ayala\AppData\Local\Temp\_mt5_farm_temp\Node_1\terminal64.exe"

print("src exists: ", os.path.exists(src))
try:
    shutil.copy2(src, dst)
    print("copied!")
except Exception as e:
    print("copy failed error:")
    traceback.print_exc()
