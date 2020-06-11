@echo off
cls

echo WARNING: Existing models will be overwritten!
echo.

pause
echo.

echo Copying models...
xcopy /i/e/y/q models ..\..\..\models
echo.

pause