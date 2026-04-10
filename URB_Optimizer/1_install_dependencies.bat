@echo off
echo ========================================
echo   URB Optimizer - Installation Script
echo ========================================
echo.

REM Check if Python is installed
python --version > nul 2>&1
if errorlevel 1 (
    echo ERROR: Python is not installed or not in PATH
    echo.
    echo Please install Python from https://www.python.org/downloads/
    echo Make sure to check "Add Python to PATH" during installation
    pause
    exit /b 1
)

echo Python found:
python --version
echo.

REM Navigate to script directory
cd /d "%~dp0"

echo Installing required packages...
echo.

REM Upgrade pip first
python -m pip install --upgrade pip

REM Install all requirements
python -m pip install pandas numpy pyarrow joblib tqdm plotly scipy

echo.
echo ========================================
echo   Installation Complete!
echo ========================================
echo.
echo Next steps:
echo 1. Place your tick data CSV file in the 'data' folder
echo 2. Run '2_run_optimization.bat' to start optimization
echo.
pause
