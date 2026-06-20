#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
RES_FILE="$ROOT_DIR/YouTubeDownloader.res"

x86_64-w64-mingw32-windres \
  "$ROOT_DIR/YouTubeDownloader.rc" \
  -O coff \
  -o "$RES_FILE"

x86_64-w64-mingw32-g++ \
  -std=c++17 \
  -O2 \
  -municode \
  -mwindows \
  -static \
  -static-libgcc \
  -static-libstdc++ \
  "$ROOT_DIR/YouTubeDownloaderWin.cpp" \
  "$RES_FILE" \
  -o "$ROOT_DIR/YouTubeDownloader.exe" \
  -lcomctl32 \
  -lole32 \
  -lshell32 \
  -luuid

echo "Built: $ROOT_DIR/YouTubeDownloader.exe"
