@echo off
setlocal
cd /d "%~dp0"
if exist "plataforma_rag\.venv\Scripts\python.exe" goto instalar
py -3.12 -m venv "plataforma_rag\.venv"
if errorlevel 1 (
  echo No se pudo crear el entorno. Instala Python 3.12 con el lanzador py.
  exit /b 1
)
:instalar
"plataforma_rag\.venv\Scripts\python.exe" -m pip install -r "plataforma_rag\requirements.txt" -r "transformacion\requirements.txt"
if errorlevel 1 exit /b 1
if not exist "plataforma_rag\.env" copy "plataforma_rag\.env.example" "plataforma_rag\.env" >nul
echo Instalacion lista. Completa plataforma_rag\.env y ejecuta iniciar.bat.
