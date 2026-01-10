@echo off
setlocal

echo ======================================================
echo          Touhou Isekai Izakaya - Starter
echo ======================================================
echo.

rem 1. Check Node.js
echo [1/3] Checking Node.js environment...
node -v >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Node.js not found!
    echo Please install it from https://nodejs.org/
    echo.
    pause
    exit /b 1
)

echo Node.js version: 
node -v
echo.

rem 2. Check node_modules
if not exist "node_modules\" (
    echo [2/3] node_modules not found. Installing dependencies...
    echo This may take a few minutes...
    echo.
    call npm install
    if %errorlevel% neq 0 (
        echo.
        echo [ERROR] npm install failed!
        pause
        exit /b 1
    )
    echo Installation complete.
) else (
    echo [2/3] node_modules exists. Skipping install.
)
echo.

rem 3. Start Dev Server
echo [3/3] Starting dev server (npm run dev)...
echo Once started, visit the URL in your browser: http://localhost:14791
echo.

call npm run dev

if %errorlevel% neq 0 (
    echo.
    echo [INFO] Server stopped.
    pause
)
