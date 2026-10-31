@echo off
setlocal
set "UNNAME_SEA_PROJECT=%~dp0..\.."
set "UNNAME_SEA_ENGINE=%~dp0..\..\..\..\Godot_v4.7.2-stable_win64.exe"
start "" "%UNNAME_SEA_ENGINE%" --path "%UNNAME_SEA_PROJECT%" "res://scenes/cherry_valley.tscn"
