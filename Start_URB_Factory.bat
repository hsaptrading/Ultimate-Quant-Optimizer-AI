@echo off
title URB Factory Launcher
color 0A
echo ==================================================
echo       URB STRATEGY FACTORY - ONE CLICK START
echo ==================================================
echo.

:: 1. Start Backend (The Brain)
echo [1/2] Launching Backend Server (Python)...
:: Corrected Path: Run from backend directory so 'app' imports work
start "URB Backend" cmd /k "cd URB_StrategyFactory\backend && uvicorn main:app --reload"

:: Wait 3 seconds for backend to initialize
timeout /t 3 /nobreak >nul

:: 2. Start Frontend (The Face)
echo [2/2] Launching Frontend Interface (Electron)...
cd URB_StrategyFactory\frontend
start "URB Frontend" cmd /c "npm run dev"

echo.
echo ==================================================
echo       SYSTEM STARTED SUCCESSFULLY
echo ==================================================
echo You can minimize the command windows, but do NOT close them.
echo The App window should appear shortly.
echo.
pause
