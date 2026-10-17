@echo off
rem Runs rightmix.py with the first Python it finds (py launcher, then python).
rem   rightmix.bat doctor | setup | build --swf bartender.swf | gui
where py >nul 2>nul
if not errorlevel 1 goto usepy
where python >nul 2>nul
if not errorlevel 1 goto usepython
echo Python 3.9 or newer is required: https://www.python.org/downloads/
exit /b 1
:usepy
py -3 "%~dp0rightmix.py" %*
exit /b %errorlevel%
:usepython
python "%~dp0rightmix.py" %*
exit /b %errorlevel%
