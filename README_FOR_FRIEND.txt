Topher's YouTube Downloader
===========================

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

macOS will probably block the install helper because it is unsigned.

To run "Install Required Tools.command":
  1. Open the Mac folder.
  2. Control-click "Install Required Tools.command".
  3. Choose Open.
  4. If macOS only shows Move to Trash and Done as options, choose "Done".
  5. Open System Settings > Privacy & Security.
  6. Scroll to Security.
  7. Click Open Anyway for "Install Required Tools.command".
  8. Go back to the Mac folder and Control-click "Install Required Tools.command" again.
  9. Choose Open.

If it says Homebrew is missing, install Homebrew from:
  https://brew.sh

Then run this in Terminal:
  brew install yt-dlp ffmpeg

Opening the app
---------------
This app is not Apple-notarized, so macOS will probably block it the first time.
That is expected for a small app shared directly outside the App Store.

To open "Topher's YouTube Downloader" the first time:
  1. Open the Mac folder.
  2. Control-click "Topher's YouTube Downloader".
  3. Choose Open.
  4. If macOS only shows Move to Trash and Done as options, choose "Done".
  5. Open System Settings > Privacy & Security.
  6. Scroll to Security.
  7. Click Open Anyway for "Topher's YouTube Downloader".
  8. Go back to the Mac folder and Control-click "Topher's YouTube Downloader" again.
  9. Choose Open.

Please only download content you have the rights or permission to save. Topher holds no liability around what you choose to download using this open source tool.
