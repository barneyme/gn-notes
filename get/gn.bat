@echo off
REM gn.bat - wrapper for gn.ps1 so you can just type "gn" in CMD or PowerShell
REM Put this file in the same folder as gn.ps1

setlocal
set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%gn.ps1" %*
endlocal