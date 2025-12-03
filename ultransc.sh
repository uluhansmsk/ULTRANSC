#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────
#  ULTRANSC v0.3 (Full Environment Check)
# ─────────────────────────────────────────

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

QUEUE_DIR="$ROOT_DIR/queue"
INCOMING="$QUEUE_DIR/incoming"
LINKS="$QUEUE_DIR/links.txt"
PROCESSING="$QUEUE_DIR/processing"
DONE="$QUEUE_DIR/done"

MODELS_DIR="$ROOT_DIR/models"
BIN_DIR="$ROOT_DIR/bin"
WORKSPACE="$ROOT_DIR/workspace"
LOG_DIR="$ROOT_DIR/logs"

MODEL_JSON="$MODELS_DIR/list.json"
DEFAULT_MODEL="ggml-medium.en.bin"

SYSTEM_LOG="$LOG_DIR/system.log"
ERROR_LOG="$LOG_DIR/errors.log"

# ─────────────────────────────────────────
#  UTILITY: log
# ─────────────────────────────────────────
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$SYSTEM_LOG"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$ERROR_LOG"
}

# ─────────────────────────────────────────
#  0. INIT FOLDERS
# ─────────────────────────────────────────
mkdir -p "$INCOMING" "$PROCESSING" "$DONE"
mkdir -p "$MODELS_DIR" "$BIN_DIR" "$WORKSPACE" "$LOG_DIR"

touch "$LINKS" "$SYSTEM_LOG" "$ERROR_LOG"

# ─────────────────────────────────────────
#  1. ENVIRONMENT CHECK
# ─────────────────────────────────────────
log "Running full environment check…"

# OS check
OS=$(uname -s)
if [[ "$OS" != "Darwin" && "$OS" != "Linux" ]]; then
    log_error "Unsupported OS: $OS"
    exit 1
fi

# CPU arch
ARCH=$(uname -m)
log "Detected architecture: $ARCH"

# RAM check
RAM_GB=$(($(sysctl -n hw.memsize 2>/dev/null || grep MemTotal /proc/meminfo | awk '{print $2 * 1024}') / 1024 / 1024 / 1024))
log "System RAM: ${RAM_GB}GB"

if (( RAM_GB < 4 )); then
    log_error "Insufficient RAM (<4GB). ULTRANSC will struggle."
fi

# Disk space check
FREE_GB=$(df -Pk "$ROOT_DIR" | awk 'NR==2 {print int($4/1024/1024)}')
if (( FREE_GB < 2 )); then
    log_error "Less than 2GB free disk space. Aborting."
    exit 1
fi

# Write permission check
if ! touch "$ROOT_DIR/.ultransc_write_test" 2>/dev/null; then
    log_error "Cannot write to ULTRANSC directory: $ROOT_DIR"
    exit 1
fi
rm -f "$ROOT_DIR/.ultransc_write_test"

# yt-dlp check
if [ ! -f "$BIN_DIR/yt-dlp" ]; then
    log "yt-dlp missing — downloading local copy…"
    curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
        -o "$BIN_DIR/yt-dlp"
    chmod +x "$BIN_DIR/yt-dlp"
else
    log "yt-dlp OK"
fi

# FFmpeg check
if ! command -v ffmpeg &>/dev/null; then
    log_error "FFmpeg not found. Install it:"
    echo "  macOS: brew install ffmpeg"
    echo "  Linux: sudo apt install ffmpeg"
    exit 1
fi
log "FFmpeg OK"

# whisper-cli check
if ! command -v whisper-cli &>/dev/null; then
    log_error "whisper-cli not found. Install whisper-cpp:"
    echo "  brew install whisper-cpp"
    exit 1
fi
log "whisper-cli OK"

# Model list JSON
if [ ! -f "$MODEL_JSON" ]; then
    echo '{"installed":{}, "default":"ggml-medium.en.bin"}' > "$MODEL_JSON"
fi

# Update model list function
update_model_list() {
    {
        echo '{ "installed": {'
        first=true
        for f in "$MODELS_DIR"/*.bin; do
            [ -e "$f" ] || continue
            model=$(basename "$f")
            if $first; then
                echo "  \"$model\": true"
                first=false
            else
                echo " ,\"$model\": true"
            fi
        done
        echo '},'
        echo "\"default\": \"${DEFAULT_MODEL}\""
        echo "}"
    } > "$MODEL_JSON"
}

update_model_list
log "Model list updated"

# Auto-select model
choose_model() {
    if (( RAM_GB >= 8 )) && [ -f "$MODELS_DIR/ggml-medium.en.bin" ]; then
        echo "ggml-medium.en.bin"
    else
        echo "ggml-small.en.bin"
    fi
}

MODEL=$(choose_model)
log "Selected model: $MODEL"

# ─────────────────────────────────────────
#  2. CLEAN UP INCOMPLETE JOBS
# ─────────────────────────────────────────
for job in "$WORKSPACE"/*; do
    [ -d "$job" ] || continue

    if [ ! -f "$job/transcript.txt" ]; then
        log "Found incomplete job: $job"
        log "Cleaning incomplete job (safe)…"
        rm -rf "$job"
    fi
done

# ─────────────────────────────────────────
#  3. PROCESSING FUNCTION
# ─────────────────────────────────────────
process_file() {
    local file="$1"
    local job_id=$(date +%Y%m%d_%H%M%S)
    local job_dir="$WORKSPACE/job_$job_id"

    mkdir -p "$job_dir"
    log "Starting job $job_id for file: $file"

    # Move into processing
    mv "$file" "$PROCESSING/"
    local base=$(basename "$file")
    local proc_file="$PROCESSING/$base"

    cp "$proc_file" "$job_dir/raw_input"

    # Convert to WAV
    ffmpeg -i "$proc_file" -ar 16000 -ac 1 -c:a pcm_s16le "$job_dir/audio.wav" -y

    # Transcribe
    whisper-cli "$job_dir/audio.wav" \
        --model "$MODELS_DIR/$MODEL" \
        --output-txt \
        --output-srt \
        --output-json \
        --output-file "$job_dir/transcript"

    # Move finished
    mv "$proc_file" "$DONE/$base"

    log "Job $job_id completed."
}

# ─────────────────────────────────────────
#  4. QUEUE HANDLING
# ─────────────────────────────────────────
log "Processing queue…"

# Local files first
for f in "$INCOMING"/*; do
    [ -e "$f" ] || continue
    process_file "$f"
done

# Then URLs from links.txt
while IFS= read -r url; do
    [[ -z "$url" ]] && continue

    log "Downloading URL: $url"
    out="$INCOMING/download_$(date +%s).mp4"

    "$BIN_DIR/yt-dlp" -o "$out" "$url" || {
        log_error "Failed to download $url"
        continue
    }

    process_file "$out"
done < "$LINKS"

log "Queue empty. ULTRANSC done."