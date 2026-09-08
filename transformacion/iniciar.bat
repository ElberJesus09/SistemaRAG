@echo off
cd /d "%~dp0"
where py >nul 2>&1
if not errorlevel 1 (
  py app.py
  goto :check
)
where python >nul 2>&1
if not errorlevel 1 (
  python app.py
  goto :check
)
echo No se encontro Python. Instala Python 3.10 o posterior.
pause
exit /b 1

:check
if errorlevel 1 echo Instala las dependencias con: py -m pip install -r requirements.txt
if errorlevel 1 pause
