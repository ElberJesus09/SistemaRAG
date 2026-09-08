@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo.
echo === 1. Comprobando el Modo de desarrollador de Windows ===
rem Flutter necesita crear enlaces simbolicos para los plugins; sin Modo de
rem desarrollador, Windows no lo permite y la compilacion se detiene.
set DEVMODE=0
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /v AllowDevelopmentWithoutDevLicense 2^>nul ^| find "AllowDevelopmentWithoutDevLicense"') do set DEVMODE=%%A
if "!DEVMODE!"=="0x1" (
  echo   activado
) else (
  echo.
  echo   FALTA: el Modo de desarrollador esta desactivado.
  echo   Voy a abrir la pantalla de ajustes. Activa "Modo de desarrollador",
  echo   cierra los ajustes y vuelve a ejecutar este script.
  echo.
  start ms-settings:developers
  goto :fin
)

echo.
echo === 2. Deteniendo los demonios que bloquean archivos ===
rem Se matan por nombre de proceso: gradlew.bat necesitaria JAVA_HOME y en
rem Git Bash no siempre esta definido.
powershell -NoProfile -Command ^
  "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'KotlinCompileDaemon|GradleDaemon' } | ForEach-Object { Write-Host ('  cerrando ' + $_.ProcessId); Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }" 2>nul
echo   listo

echo.
echo === 3. Borrando caches corruptas ===
call flutter clean
if exist build            rmdir /s /q build
if exist android\.gradle  rmdir /s /q android\.gradle
if exist android\.kotlin  rmdir /s /q android\.kotlin
if exist .dart_tool       rmdir /s /q .dart_tool
echo   listo

echo.
echo === 4. Descargando dependencias ===
call flutter pub get
if errorlevel 1 goto :error

echo.
echo === 5. Analizando el codigo Dart ===
call dart analyze
if errorlevel 1 (
  echo.
  echo   dart analyze encontro problemas. Revisalos antes de continuar.
  goto :fin
)

echo.
echo === 6. Ejecutando en el emulador ===
call flutter run -d emulator-5554
goto :fin

:error
echo.
echo   Fallo la descarga de dependencias.

:fin
endlocal
pause
