@echo off
setlocal
set "UNNAME_SEA_ENGINE=%~dp0..\..\Godot_v4.7.2-stable_win64.exe"
if not exist "%UNNAME_SEA_ENGINE%" (
    echo Godot engine was not found. Open project.godot in Godot 4.7.2.
    pause
    exit /b 1
)
start "" "%UNNAME_SEA_ENGINE%" --path "%~dp0."
