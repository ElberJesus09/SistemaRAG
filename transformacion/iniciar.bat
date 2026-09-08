@echo off
setlocal
cd /d "%~dp0"
if exist "..\plataforma_rag\.venv\Scripts\python.exe" (
  "..\plataforma_rag\.venv\Scripts\python.exe" "%~dp0app.py"
  exit /b
)
echo Falta el entorno virtual compartido. Ejecuta instalar.bat en la raiz del proyecto.
exit /b 1
