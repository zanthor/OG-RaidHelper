@echo off
setlocal enabledelayedexpansion

:: Backup OG-RaidHelper SavedVariables for all accounts
:: This script should be run from the OG-RaidHelper\Scripts folder

echo ==========================================
echo OG-RaidHelper SavedVariables Backup Tool
echo ==========================================
echo.

:: Prompt for environment
:prompt
set "ENV_TYPE="
set /p "ENV_TYPE=Enter environment (Prod/Dev): "

if /i "%ENV_TYPE%"=="Prod" (
    set "ENV_PREFIX=prod"
    goto :continue
)
if /i "%ENV_TYPE%"=="Dev" (
    set "ENV_PREFIX=dev"
    goto :continue
)

echo Invalid input. Please enter "Prod" or "Dev"
echo.
goto :prompt

:continue
echo.
echo Selected environment: %ENV_TYPE%
echo.

:: Create timestamp (format: YYYYMMDD_HHMMSS)
for /f "tokens=2 delims==" %%a in ('wmic OS Get localdatetime /value') do set "dt=%%a"
set "TIMESTAMP=%dt:~0,4%%dt:~4,2%%dt:~6,2%_%dt:~8,2%%dt:~10,2%%dt:~12,2%"

:: Create backup directory if it doesn't exist
if not exist "backup" mkdir backup

:: Path to WTF\Account folder (relative from Scripts folder)
set "ACCOUNT_PATH=..\..\..\..\WTF\Account"

:: Check if the Account path exists
if not exist "%ACCOUNT_PATH%" (
    echo ERROR: Could not find WTF\Account folder at: %ACCOUNT_PATH%
    echo Please ensure you're running this from the OG-RaidHelper\Scripts folder
    pause
    exit /b 1
)

:: Counter for backed up files
set "COUNT=0"

:: Loop through all account folders
echo Scanning for accounts...
echo.
for /d %%A in ("%ACCOUNT_PATH%\*") do (
    set "ACCOUNT_NAME=%%~nxA"
    set "SAVEDVAR_FILE=%%A\SavedVariables\OG-RaidHelper.lua"
    
    if exist "!SAVEDVAR_FILE!" (
        set /a COUNT+=1
        set "BACKUP_FILE=backup\OG-RaidHelper_!ACCOUNT_NAME!_%ENV_PREFIX%_%TIMESTAMP%.lua"
        
        echo [!COUNT!] Backing up: !ACCOUNT_NAME!
        copy "!SAVEDVAR_FILE!" "!BACKUP_FILE!" >nul
        
        if !errorlevel! equ 0 (
            echo     Success: !BACKUP_FILE!
        ) else (
            echo     ERROR: Failed to backup !ACCOUNT_NAME!
        )
        echo.
    )
)

echo ==========================================
if %COUNT% gtr 0 (
    echo Backup complete! %COUNT% account(s) backed up.
) else (
    echo No OG-RaidHelper SavedVariables found.
)
echo ==========================================
echo.
pause
