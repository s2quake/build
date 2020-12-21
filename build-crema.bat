@echo off
powershell -executionpolicy remotesigned -File %~dp0\build-crema.ps1 "%*"