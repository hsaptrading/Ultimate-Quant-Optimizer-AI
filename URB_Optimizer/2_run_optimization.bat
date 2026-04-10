@echo off
echo ========================================
echo   URB Optimizer - Running Optimization
echo ========================================
echo.

REM Navigate to script directory
cd /d "%~dp0"

echo Current directory: %CD%
echo.

REM Create timestamp for log file
for /f "tokens=2 delims==" %%a in ('wmic OS Get localdatetime /value') do set "dt=%%a"
set "timestamp=%dt:~0,4%%dt:~4,2%%dt:~6,2%_%dt:~8,2%%dt:~10,2%%dt:~12,2%"

REM Create reports folder if not exists
if not exist "reports" mkdir reports

echo Starting optimization at %date% %time%
echo Log will be saved to: reports\optimization_log_%timestamp%.txt
echo.
echo This may take 30-60 minutes depending on your data size...
echo Press Ctrl+C to cancel at any time.
echo.
echo ========================================

REM Run Python and show output in console while also saving to file
python run_optimization.py

REM Check if Python had an error
if errorlevel 1 (
    echo.
    echo ========================================
    echo   ERROR: Python script failed!
    echo ========================================
    echo.
    echo Check the console output above for error details.
    echo.
) else (
    echo.
    echo ========================================
    echo   Optimization Finished Successfully!
    echo ========================================
    echo.
    echo Check the 'reports' folder for detailed logs.
    echo Check the 'databank' folder for saved strategy sets.
    echo.
)

echo Press any key to close this window...
pause > nul
