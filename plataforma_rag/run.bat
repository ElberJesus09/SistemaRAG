@echo off
cd /d "%~dp0"
if not exist .env (
  echo Falta el archivo .env. Copia .env.example a .env y completa las credenciales.
  pause
  exit /b 1
)
if exist .venv\Scripts\python.exe (
  .venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
  goto :end
)
where py >nul 2>&1
if not errorlevel 1 (
  py -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
  goto :end
)
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
:end
if errorlevel 1 pause
