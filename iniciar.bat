@echo off
setlocal
cd /d "%~dp0"
if not exist "plataforma_rag\.env" (
  echo Falta plataforma_rag\.env. Copia .env.example y completa las credenciales.
  exit /b 1
)
if not exist "plataforma_rag\.venv\Scripts\python.exe" (
  echo Falta el entorno virtual. Ejecuta instalar.bat.
  exit /b 1
)
"plataforma_rag\.venv\Scripts\python.exe" "%~dp0iniciar.py" %*
exit /b %errorlevel%
