@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\.mvp_qa\prompt2rig\open_preview.ps1"
if errorlevel 1 pause
