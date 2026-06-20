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
popup.

To run the Mac install helper:
  1. Open the Mac folder.
  2. Control-click "Install Required Tools.command".
  3. Choose Open.
  4. Choose Open again if macOS asks.

If macOS still blocks it, open System Settings > Privacy & Security, scroll to
Security, then click Open Anyway for "Install Required Tools.command". After
that, run it again with Control-click > Open.

If it says Homebrew is missing, install Homebrew from:
  https://brew.sh

Then run this in Terminal:
  brew install yt-dlp ffmpeg

Opening the app
---------------
This app is not Apple-notarized, so macOS will probably block it the first time.
That is expected for a small app shared directly outside the App Store.

To open the app the first time:
  1. Open the Mac folder.
  2. Control-click "YouTube Downloader".
  3. Choose Open.
  4. Choose Open again if macOS asks.

If macOS only shows Move to Trash and Done, click Done, then open System
Settings > Privacy & Security, scroll to Security, and click Open Anyway for
"YouTube Downloader". After that, run it again with Control-click > Open.

Please only download content you have the rights or permission to save.
