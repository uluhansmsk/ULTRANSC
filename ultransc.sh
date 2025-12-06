#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────
#  ULTRANSC v0.3.2 — UNIVERSAL TIMEOUT EDITION
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
DEFAULT_MODEL="ggml-medium.en.bin"     # small.en is MORE stable for lectures

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

# Global crash-safe handler
trap 'log_error "ULTRANSC crashed inside a job. Continuing…"' ERR

# ─────────────────────────────────────────
# UNIVERSAL TIMEOUT (NO DEPENDENCIES)
# ─────────────────────────────────────────
timeout_cmd() {
    # $1 = max seconds
    # $2... = command
    local secs="$1"
    shift

    (
        "$@" &
        local cmd_pid=$!

        (
            sleep "$secs"
            kill -0 "$cmd_pid" 2>/dev/null && kill -9 "$cmd_pid" 2>/dev/null
        ) &
        local watcher=$!

        wait "$cmd_pid"
        local status=$?

        kill -0 "$watcher" 2>/dev/null && kill -9 "$watcher" 2>/dev/null

        return $status
    )
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

OS=$(uname -s)
if [[ "$OS" != "Darwin" && "$OS" != "Linux" ]]; then
    log_error "Unsupported OS: $OS"
    exit 1
fi

ARCH=$(uname -m)
log "Detected architecture: $ARCH"

RAM_GB=$(($(sysctl -n hw.memsize 2>/dev/null || grep MemTotal /proc/meminfo | awk '{print $2 * 1024}') / 1024 / 1024 / 1024))
log "System RAM: ${RAM_GB}GB"

FREE_GB=$(df -Pk "$ROOT_DIR" | awk 'NR==2 {print int($4/1024/1024)}')
if (( FREE_GB < 2 )); then
    log_error "Less than 2GB free disk space — aborting."
    exit 1
fi

if ! touch "$ROOT_DIR/.ultransc_write_test" 2>/dev/null; then
    log_error "Cannot write to ULTRANSC directory ($ROOT_DIR)"
    exit 1
fi
rm -f "$ROOT_DIR/.ultransc_write_test"

# yt-dlp local copy bootstrap
if [ ! -f "$BIN_DIR/yt-dlp" ]; then
    log "yt-dlp missing — downloading local copy…"
    curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
         -o "$BIN_DIR/yt-dlp"
    chmod +x "$BIN_DIR/yt-dlp"
else
    log "yt-dlp OK"
fi

if ! command -v ffmpeg &>/dev/null; then
    log_error "FFmpeg not found. Install it (brew install ffmpeg)."
    exit 1
fi
log "FFmpeg OK"

if ! command -v whisper-cli &>/dev/null; then
    log_error "whisper-cli not found. Install whisper-cpp (brew install whisper-cpp)."
    exit 1
fi
log "whisper-cli OK"

# Ensure model.json exists
if [ ! -f "$MODEL_JSON" ]; then
    echo '{"installed":{}, "default":"ggml-medium.en.bin"}' > "$MODEL_JSON"
fi

update_model_list() {
    {
        echo '{ "installed": {'
        first=true
        for f in "$MODELS_DIR"/*.bin; do
            [ -e "$f" ] || continue
            m=$(basename "$f")
            if $first; then
                echo "  \"$m\": true"
                first=false
            else
                echo " ,\"$m\": true"
            fi
        done
        echo '},'
        echo "\"default\": \"${DEFAULT_MODEL}\""
        echo "}"
    } > "$MODEL_JSON"
}

update_model_list
log "Model list updated"

choose_model() {
    if (( RAM_GB >= 6 )) && [ -f "$MODELS_DIR/ggml-medium.en.bin" ]; then
        echo "ggml-medium.en.bin"
    else
        echo "ggml-small.en.bin"
    fi
}
MODEL=$(choose_model)
log "Using transcription model: $MODEL"

# ─────────────────────────────────────────
#  NIGHT MODE SAFETY UTILITIES
# ─────────────────────────────────────────

retry_ffmpeg() {
    local input="$1"
    local output="$2"

    for attempt in {1..3}; do
        log "FFmpeg attempt $attempt for $input"

        if timeout_cmd 240 ffmpeg -i "$input" \
            -af "highpass=f=200, lowpass=f=3000" \
            -ar 16000 -ac 1 -c:a pcm_s16le "$output" -y; then
            return 0
        fi

        log_error "FFmpeg conversion failed (attempt $attempt)"
        sleep 2
    done

    log_error "FFmpeg failed after 3 attempts. Skipping file."
    return 1
}

retry_whisper() {
    local wav="$1"
    local out="$2"

    for attempt in {1..3}; do
        log "Whisper attempt $attempt"

        if timeout_cmd 7200 whisper-cli "$wav" \
            --language en \
            --model "$MODELS_DIR/$MODEL" \
            --output-txt \
            --output-srt \
            --output-json \
            --output-file "$out"; then
            return 0
        fi

        log_error "Whisper failed at attempt $attempt"
        sleep 3
    done

    log_error "Whisper failed after 3 attempts. Skipping."
    return 1
}

# ─────────────────────────────────────────
#  CLEAN UP INCOMPLETE JOBS
# ─────────────────────────────────────────
for job in "$WORKSPACE"/*; do
    [ -d "$job" ] || continue

    if [ ! -f "$job/transcript.txt" ]; then
        log "Cleaning incomplete job: $job"
        rm -rf "$job"
    fi
done

# ─────────────────────────────────────────
#  PROCESSING FUNCTION
# ─────────────────────────────────────────
process_file() {
    local file="$1"
    local job_id
    job_id=$(date +%Y%m%d_%H%M%S)
    local job_dir="$WORKSPACE/job_$job_id"

    mkdir -p "$job_dir"
    log "Starting job $job_id for $file"

    mv "$file" "$PROCESSING/"
    local base=$(basename "$file")
    local proc_file="$PROCESSING/$base"
    cp "$proc_file" "$job_dir/raw_input"

    # Duration guard
    DURATION=$(ffprobe -v error -show_entries format=duration \
               -of default=noprint_wrappers=1:nokey=1 "$proc_file" | awk '{print int($1)}')
    if (( DURATION > 10800 )); then
        log_error "File > 3 hours. Skipping for safety."
        return 0
    fi

    # Disk space guard
    SPACE_LEFT=$(df -Pk "$ROOT_DIR" | awk 'NR==2 {print int($4/1024)}')
    if (( SPACE_LEFT < 500 )); then
        log_error "Low disk (<500MB). Aborting batch."
        exit 1
    fi

    # Convert to normalized WAV
    if ! retry_ffmpeg "$proc_file" "$job_dir/audio.wav"; then
        return 0
    fi

    if [ ! -s "$job_dir/audio.wav" ]; then
        log_error "WAV output is empty. Skipping."
        return 0
    fi

    # Transcription
    if ! retry_whisper "$job_dir/audio.wav" "$job_dir/transcript"; then
        return 0
    fi

    mv "$proc_file" "$DONE/$base"
    log "Job $job_id completed."
}

# ─────────────────────────────────────────
#  QUEUE HANDLING
# ─────────────────────────────────────────
log "Processing queue…"

for f in "$INCOMING"/*; do
    [ -e "$f" ] || continue
    process_file "$f" || log_error "Job failed, continuing."
done

while IFS= read -r url; do
    [[ -z "$url" ]] && continue

    log "Downloading URL: $url"
    out="$INCOMING/download_$(date +%s).mp4"

    if ! "$BIN_DIR/yt-dlp" -o "$out" "$url"; then
        log_error "Failed to download $url"
        continue
    fi

    process_file "$out" || log_error "Job failed, continuing."
done < "$LINKS"

log "Queue empty. ULTRANSC completed all tasks."