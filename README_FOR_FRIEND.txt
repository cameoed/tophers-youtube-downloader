YouTube Downloader
==================

What it does
------------
Paste one YouTube link per line, choose MP3 or MP4, then click Download.

Files are saved to:
  ~/Downloads/YouTube Downloader/Audio
  ~/Downloads/YouTube Downloader/Video

You can pick a different location with Save to.... The app will create a
YouTube Downloader folder there, with Audio and Video folders inside it.

First-time setup
----------------
This app uses yt-dlp and ffmpeg instead of bundling them, which keeps the app
small and makes updates easier. If either tool is missing, the app will show a
popup. You can also double-click "Install Required Tools.command".

If it says Homebrew is missing, install Homebrew from:
  https://brew.sh

Then run this in Terminal:
  brew install yt-dlp ffmpeg

Opening the app
---------------
Because this is shared directly instead of through the Mac App Store, macOS may
warn that it cannot verify the developer. On first launch, right-click the app,
choose Open, then choose Open again.

Please only download content you have the rights or permission to save.
