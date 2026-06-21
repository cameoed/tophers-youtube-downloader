@echo off
setlocal

echo Topher's YouTube Downloader setup
echo.

where winget >nul 2>nul
if errorlevel 1 (
  echo Windows Package Manager ^(winget^) was not found.
  echo Install App Installer from the Microsoft Store, then run this file again.
  echo.
  pause
  exit /b 1
)

echo Installing yt-dlp...
winget install --id yt-dlp.yt-dlp --exact --accept-source-agreements --accept-package-agreements

echo.
echo Installing ffmpeg...
winget install --id yt-dlp.FFmpeg --exact --accept-source-agreements --accept-package-agreements

echo.
echo Done. If the app still says yt-dlp or ffmpeg is missing, restart Windows
echo once so Explorer picks up the new PATH entries.
echo.
pause
