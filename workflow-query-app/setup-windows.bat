@echo off
cd /d "%~dp0"
echo === Workflow Query App - Windows Setup ===
echo.

echo Checking prerequisites...
if not exist ".env.local" (
    echo ERROR: .env.local not found!
    echo.
    echo Please create a .env.local file in this folder with your database credentials:
    echo.
    echo   DB_SERVER=your-sql-server
    echo   DB_DATABASE=your-database
    echo   DB_USER=your-username
    echo   DB_PASSWORD=your-password
    echo   DB_PORT=1433
    echo.
    echo See README.md for details.
    pause
    exit /b 1
)
echo   .env.local found.
echo.

echo Step 1: Installing dependencies...
call npm install
if %errorlevel% neq 0 (echo ERROR: npm install failed & pause & exit /b 1)

echo.
echo Step 2: Building the app...
call npm run build
if %errorlevel% neq 0 (echo ERROR: Build failed & pause & exit /b 1)

echo.
echo Step 3: Installing PM2 globally...
call npm install -g pm2
if %errorlevel% neq 0 (echo ERROR: PM2 install failed & pause & exit /b 1)

echo.
echo Step 4: Installing PM2 Windows startup manager...
call npm install -g pm2-windows-startup
if %errorlevel% neq 0 (echo ERROR: pm2-windows-startup install failed & pause & exit /b 1)

echo.
echo Step 5: Starting app with PM2...
call pm2 start ecosystem.config.js
if %errorlevel% neq 0 (echo ERROR: PM2 start failed & pause & exit /b 1)

echo.
echo Step 6: Saving PM2 process list...
call pm2 save
if %errorlevel% neq 0 (echo ERROR: PM2 save failed & pause & exit /b 1)

echo.
echo Step 7: Configuring PM2 to start on Windows boot...
call npx pm2-windows-startup install
if %errorlevel% neq 0 (echo ERROR: Startup config failed & pause & exit /b 1)

echo.
echo === Setup complete! ===
echo App is running at http://localhost:3000
echo It will restart automatically if it crashes and start on Windows boot.
echo.
echo Useful PM2 commands:
echo   pm2 status                         - check if app is running
echo   pm2 logs workflow-query-app        - view app logs
echo   pm2 restart workflow-query-app     - restart the app
echo   pm2 stop workflow-query-app        - stop the app
echo.
pause
