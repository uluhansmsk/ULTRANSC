#!/bin/zsh

# ===== CONFIG =====
BASE_DIR="$HOME/Documents/Transcripts"
MODEL="$HOME/Documents/whisper-cpp-bin/ggml-medium.en.bin"
# ==================

URL="$1"

if [[ -z "$URL" ]]; then
    echo "❌ Usage: transcribe <url>"
    exit 1
fi

echo "🔍 Fetching metadata..."

TITLE=$(yt-dlp --get-title "$URL" 2>/dev/null | sed 's/[\/:*?"<>|]/_/g')
CHANNEL=$(yt-dlp --get-filename -o "%(channel)s" "$URL" 2>/dev/null | sed 's/[\/:*?"<>|]/_/g')
PLATFORM=$(echo "$URL" | awk -F[/:] '{print $4}' | sed 's/www\.//')
DATE=$(date +"%Y-%m-%d_%H-%M")

# Build structured path:
OUTPUT_DIR="$BASE_DIR/$PLATFORM/${CHANNEL:-UnknownChannel}/${DATE}_${TITLE:-Untitled}"
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR" || exit

echo "📁 Output directory: $OUTPUT_DIR"

# Download best audio/video
echo "⬇️ Downloading source..."
yt-dlp -f "bestaudio/best" -o "source.%(ext)s" "$URL"

FILE=$(ls source.* | head -n 1)

echo "🎧 Converting to WAV..."
ffmpeg -y -hide_banner -loglevel error \
  -i "$FILE" -ar 16000 -ac 1 -c:a pcm_s16le audio.wav

echo "🧠 Transcribing using whisper..."
whisper-cli audio.wav \
  --model "$MODEL" \
  --output-txt \
  --output-srt \
  --output-json \
  --language auto \
  --print-progress \
  --output-file "transcript"

echo "🧹 Cleaning temporary audio..."
rm audio.wav

echo ""
echo "✨ DONE"
echo "📄 Transcript files created:"
echo "   - transcript.txt"
echo "   - transcript.srt"
echo "   - transcript.json"
echo ""
echo "🚀 Stored in: $OUTPUT_DIR"