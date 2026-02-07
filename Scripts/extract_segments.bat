@echo off
REM OG-RaidHelper Segment Recovery - Combat Log Extractor
REM Quick launcher for Windows

echo ========================================
echo OG-RaidHelper Segment Recovery
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

echo Python found. Running segment extractor...
echo.

REM Check if a file was dragged onto the batch file
if not "%~1"=="" (
    if exist "%~1" (
        echo Using provided file: %~1
        python "%~dp0extract_segments.py" "%~1"
        goto :end
    ) else (
        echo ERROR: File not found: %~1
        goto :end
    )
)

REM Check if WoWCombatLog.txt exists in the batch file's directory
if exist "%~dp0WoWCombatLog.txt" (
    echo Found WoWCombatLog.txt in script directory
    python "%~dp0extract_segments.py" "%~dp0WoWCombatLog.txt"
) else if exist "WoWCombatLog.txt" (
    REM Check current working directory as fallback
    echo Found WoWCombatLog.txt in current directory
    python "%~dp0extract_segments.py" "WoWCombatLog.txt"
) else (
    REM Try default Turtle WoW location
    set "DEFAULT_LOG=D:\games\TurtleWow\Logs\WoWCombatLog.txt"
    if exist "%DEFAULT_LOG%" (
        echo Found WoWCombatLog.txt at: %DEFAULT_LOG%
        python "%~dp0extract_segments.py" "%DEFAULT_LOG%"
    ) else (
        echo.
        echo ERROR: Could not find WoWCombatLog.txt
        echo.
        echo Please do one of the following:
        echo   1. Drag and drop WoWCombatLog.txt onto this .bat file
        echo   2. Copy this .bat file to the same folder as your WoWCombatLog.txt
        echo   3. Copy WoWCombatLog.txt to this directory
        echo   4. Run manually: python extract_segments.py "path\to\WoWCombatLog.txt"
        echo.
        echo Batch file directory: %~dp0
        echo Current directory: %CD%
        echo Default location checked: %DEFAULT_LOG%
    )
)

:end

echo.
echo ========================================
echo.
pause
