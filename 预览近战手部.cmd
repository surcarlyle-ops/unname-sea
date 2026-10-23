@echo off
cd /d "%~dp0"
start "" "..\..\Godot_v4.7.2-stable_win64.exe" --path "%CD%" res://scenes/tests/melee_candidate_preview.tscn
