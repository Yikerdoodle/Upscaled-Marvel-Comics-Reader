@echo off
title Comic upscaling
cd /d "%~dp0"

echo.
echo  =====================================================
echo    Marvel Unlimited  -  APISR 2x upscaling
echo  =====================================================
echo.

if not exist "..\Magpie\Magpie.exe" (
  echo  ERROR: Magpie not found at ..\Magpie\Magpie.exe
  echo  Is the E: drive plugged in?
  echo.
  pause
  exit /b 1
)

echo  Starting Magpie...
start "" "..\Magpie\Magpie.exe"
echo.
echo  -----------------------------------------------------
echo   NOW:
echo     1. Put Firefox in FULLSCREEN  (press F11)
echo     2. Click on the Firefox window
echo     3. Press  Win + Shift + A     to turn upscaling ON
echo        Press it again             to turn it OFF
echo  -----------------------------------------------------
echo.
echo   Expect a short pause on each panel turn - that is
echo   the AI model running. Coil whine is normal.
echo.
echo   Do NOT shrink the window. Fullscreen is correct:
echo   Marvel's image arrives at full size, the model
echo   doubles it, then it is fitted back to your screen.
echo.
pause
