@echo off
powershell -executionpolicy remotesigned -File %~dp0\build-font-generator.ps1 "%*"