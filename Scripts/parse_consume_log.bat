@echo off
REM OG-RaidHelper Consume Log Parser
REM Quick launcher for Windows

echo ========================================
echo OG-RaidHelper Consume Log Parser
echo ========================================
echo.

REM Check if Python is installed
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python is not installed or not in PATH
    echo.
    echo Please install Python 3.6+ from: https://www.python.org/downloads/
    echo Make sure to check "Add Python to PATH" during installation
    pause
    exit /b 1
)

echo Python found. Running parser...
echo.

REM Run the parser in interactive mode (default)
REM User will be prompted to select output mode, encounter, and player count
python "%~dp0parse_consume_log.py"

echo.
echo ========================================
echo Parsing complete!
echo Check the current directory for output CSV files.
echo ========================================
echo.
pause
