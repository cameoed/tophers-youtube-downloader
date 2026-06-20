#!/bin/zsh
set -e

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

echo "YouTube Downloader setup"
echo

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is not installed yet."
  echo "Opening https://brew.sh ..."
  open "https://brew.sh"
  echo
  echo "Install Homebrew first, then run this file again."
  echo
  read -r "?Press Return to close."
  exit 1
fi

echo "Installing/updating yt-dlp and ffmpeg..."
brew install yt-dlp ffmpeg

echo
echo "Done. You can open YouTube Downloader now."
echo
read -r "?Press Return to close."
