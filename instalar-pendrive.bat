@ECHO OFF
TITLE Instalador Multi-Agent Portable - Pendrive
SETLOCAL

REM Garante que o script rode a partir da pasta do repositorio
CD /D "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup-pendrive.ps1" %*

IF %ERRORLEVEL% NEQ 0 (
  ECHO.
  ECHO [ERRO] A instalacao foi interrompida ou encontrou um erro.
  IF NOT DEFINED PORTABLE_NONINTERACTIVE PAUSE
  EXIT /B %ERRORLEVEL%
)
