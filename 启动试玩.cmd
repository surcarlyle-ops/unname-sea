@echo off
setlocal
set "GODOT=%~dp0..\..\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
    echo Godot executable was not found. Open project.godot in Godot 4.7.2.
    pause
    exit /b 1
)

REM Single-instance guard: skip launching if a Godot window is already open.
tasklist /FI "IMAGENAME eq Godot_v4.7.2-stable_win64.exe" 2>nul | find /I "Godot_v4.7.2-stable_win64.exe" >nul
if not errorlevel 1 (
    echo Game is already running. Close the existing window first.
    timeout /t 3 >nul
    exit /b 0
)

start "" "%GODOT%" --path "%~dp0."
