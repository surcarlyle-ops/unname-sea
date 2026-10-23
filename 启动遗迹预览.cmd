@echo off
setlocal
set "GODOT=%~dp0..\..\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
    echo Godot executable was not found. Open project.godot in Godot 4.7.2.
    pause
    exit /b 1
)
start "" "%GODOT%" --path "%~dp0." res://scenes/portal_ruins_preview.tscn
