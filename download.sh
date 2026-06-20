#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

FORMAT="${1:-mp3}"
RESOLUTION="${2:-best}"
OUTPUT_DIR="${3:-${YOUTUBE_DOWNLOADER_OUTPUT_DIR:-$HOME/Downloads/YouTube Downloader}}"
BATCH_FILE="video.txt"
TMP_BATCH_FILE="$(mktemp /tmp/youtube-downloader-batch.XXXXXX)"
OUTPUT_TEMPLATE="%(title).200B [%(id)s].%(ext)s"
BRACKETED_TITLE_TEXT_REGEX='\s*\[[^]]*\]'

trap 'rm -f "$TMP_BATCH_FILE"' EXIT

find_binary() {
  local name="$1"
  shift

  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi

  local candidate
  for candidate in "$@"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

YT_DLP_BIN="$(find_binary yt-dlp /opt/homebrew/bin/yt-dlp /usr/local/bin/yt-dlp)" || {
  cat >&2 <<'MESSAGE'
yt-dlp was not found.

Install the required tools with Homebrew:
  brew install yt-dlp ffmpeg

If Homebrew is not installed yet:
  https://brew.sh
MESSAGE
  exit 1
}

FFMPEG_BIN="$(find_binary ffmpeg /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg)" || {
  cat >&2 <<'MESSAGE'
ffmpeg was not found.

Install the required tools with Homebrew:
  brew install yt-dlp ffmpeg

If Homebrew is not installed yet:
  https://brew.sh
MESSAGE
  exit 1
}

# Prefer yt-dlp's maintained client defaults, but drop `web` to avoid SABR-only
# formats and JS challenge noise on YouTube.
YOUTUBE_EXTRACTOR_ARGS='youtube:player_client=default,-web'

# Build the video format selector based on the requested resolution.
# For 4K, YouTube often offers VP9/AV1, so we allow any codec.
build_mp4_format_selector() {
  local res="$1"
  case "$res" in
    2160)
      echo 'bestvideo[height<=2160]+bestaudio[ext=m4a]/bestvideo[height<=2160]+bestaudio/best[height<=2160]'
      ;;
    1080)
      echo 'bestvideo[height<=1080][ext=mp4][vcodec^=avc1]+bestaudio[ext=m4a]/bestvideo[height<=1080]+bestaudio/best[height<=1080]'
      ;;
    720)
      echo 'bestvideo[height<=720][ext=mp4][vcodec^=avc1]+bestaudio[ext=m4a]/bestvideo[height<=720]+bestaudio/best[height<=720]'
      ;;
    480)
      echo 'bestvideo[height<=480][ext=mp4][vcodec^=avc1]+bestaudio[ext=m4a]/bestvideo[height<=480]+bestaudio/best[height<=480]'
      ;;
    *)
      # "best" — no cap, prefer H.264 where available but allow any codec
      echo 'bestvideo[ext=mp4][vcodec^=avc1]+bestaudio[ext=m4a]/bestvideo+bestaudio/best'
      ;;
  esac
}

MP4_FORMAT_SELECTOR="$(build_mp4_format_selector "$RESOLUTION")"

if [[ ! -f "$BATCH_FILE" ]]; then
  echo "Missing $BATCH_FILE" >&2
  exit 1
fi

sed -E 's/\r$//; /^[[:space:]]*$/d; /^[[:space:]]*#/d' "$BATCH_FILE" >"$TMP_BATCH_FILE"

if [[ ! -s "$TMP_BATCH_FILE" ]]; then
  echo "Add at least one link to $BATCH_FILE" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

case "$FORMAT" in
  mp3)
    "$YT_DLP_BIN" --batch-file "$TMP_BATCH_FILE" \
                  --newline \
                  --ffmpeg-location "$FFMPEG_BIN" \
                  --extractor-args "$YOUTUBE_EXTRACTOR_ARGS" \
                  --no-playlist \
                  --replace-in-metadata title "$BRACKETED_TITLE_TEXT_REGEX" "" \
                  -P "$OUTPUT_DIR" \
                  -o "$OUTPUT_TEMPLATE" \
                  -f "bestaudio/best" \
                  --extract-audio \
                  --audio-format mp3 \
                  --audio-quality 0
    echo "Saved files in $OUTPUT_DIR"
    ;;
  mp4)
    echo "Resolution: ${RESOLUTION} | Format selector: ${MP4_FORMAT_SELECTOR}"
    "$YT_DLP_BIN" --batch-file "$TMP_BATCH_FILE" \
                  --newline \
                  --ffmpeg-location "$FFMPEG_BIN" \
                  --extractor-args "$YOUTUBE_EXTRACTOR_ARGS" \
                  --no-playlist \
                  --replace-in-metadata title "$BRACKETED_TITLE_TEXT_REGEX" "" \
                  -f "$MP4_FORMAT_SELECTOR" \
                  -P "$OUTPUT_DIR" \
                  -o "$OUTPUT_TEMPLATE" \
                  --merge-output-format mp4
    echo "Saved files in $OUTPUT_DIR"
    ;;
  *)
    echo "Usage: $0 [mp3|mp4] [resolution] [output-directory]" >&2
    exit 1
    ;;
esac
