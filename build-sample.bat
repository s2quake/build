@echo off
powershell -executionpolicy remotesigned -File %~dp0\build-sample.ps1 "%*"