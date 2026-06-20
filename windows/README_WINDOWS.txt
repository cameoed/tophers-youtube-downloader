YouTube Downloader for Windows
==============================

What it does
------------
Paste one YouTube link per line, choose MP3 or MP4, then click Download.

Files are saved to:
  Downloads\YouTube Downloader\Audio
  Downloads\YouTube Downloader\Video

You can pick a different location with Save to.... The app will create a
YouTube Downloader folder there, with Audio and Video folders inside it.

First-time setup
----------------
This app uses yt-dlp and ffmpeg instead of bundling them, which keeps the app
small and makes updates easier. If either tool is missing, the app will show a
popup. You can also double-click "Install Required Tools.bat".

If the app still says yt-dlp or ffmpeg is missing after setup, restart Windows
once so the new PATH entries are available to apps opened from Explorer.

Opening on Windows
------------------
This app is not signed with a paid Windows certificate, so Windows may show a
SmartScreen warning. That is expected for a small app shared directly.

If Windows shows "Windows protected your PC":
  1. Click More info.
  2. Click Run anyway.

If Windows asks for permission to run the install helper, allow it. The helper
installs yt-dlp and ffmpeg, which the app needs for downloads.

Please only download content you have the rights or permission to save.
