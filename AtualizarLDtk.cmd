@echo off
setlocal
set "ATUALIZADOR_PYTHON=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
if not exist "%ATUALIZADOR_PYTHON%" (
    echo Python do ambiente Codex nao encontrado. Abra docs\GUIA.md para orientacoes.
    if "%~1"=="" pause
    exit /b 1
)
set "ATUALIZADOR_OPCOES=--summary --open"
if "%~1"=="--refresh-only" set "ATUALIZADOR_OPCOES=--summary"
if "%~1"=="--dry-run" set "ATUALIZADOR_OPCOES=--summary --dry-run"
if not "%~1"=="" if not "%~1"=="--refresh-only" if not "%~1"=="--dry-run" (
    echo Uso: AtualizarLDtk.cmd [--refresh-only ^| --dry-run]
    exit /b 1
)
echo Atualizando o mapa LDtk a partir dos PNGs atuais...
"%ATUALIZADOR_PYTHON%" -X utf8 "%~dp0tools\refresh_ldtk_sources.py" %ATUALIZADOR_OPCOES%
set "ATUALIZADOR_EXIT=%ERRORLEVEL%"
if not "%ATUALIZADOR_EXIT%"=="0" (
    echo.
    echo Nao feche o LDtk a forca. Salve, feche e tente novamente.
    if "%~1"=="" pause
)
exit /b %ATUALIZADOR_EXIT%
