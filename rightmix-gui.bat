@echo off
rem Opens the graphical front end of rightmix.py (double-click this file).
where py >nul 2>nul
if not errorlevel 1 goto usepy
where python >nul 2>nul
if not errorlevel 1 goto usepython
echo Python 3.9 or newer is required: https://www.python.org/downloads/
pause
exit /b 1
:usepy
py -3 "%~dp0rightmix.py" gui
exit /b %errorlevel%
:usepython
python "%~dp0rightmix.py" gui
exit /b %errorlevel%
