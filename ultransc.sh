#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────
#  ULTRANSC v0.3.3 — ADAPTIVE SPEECH BOOST EDITION
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
# LOGGING
# ─────────────────────────────────────────
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$SYSTEM_LOG"
}
log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$ERROR_LOG"
}

trap 'log_error "ULTRANSC crashed inside a job. Continuing…"' ERR

# ─────────────────────────────────────────
# UNIVERSAL TIMEOUT (DEPENDENCY-FREE)
# ─────────────────────────────────────────
timeout_cmd() {
    local secs="$1"; shift

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
# INIT FOLDERS
# ─────────────────────────────────────────
mkdir -p "$INCOMING" "$PROCESSING" "$DONE"
mkdir -p "$MODELS_DIR" "$BIN_DIR" "$WORKSPACE" "$LOG_DIR"
touch "$LINKS" "$SYSTEM_LOG" "$ERROR_LOG"

# ─────────────────────────────────────────
# ENVIRONMENT CHECK
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

# yt-dlp bootstrap
if [ ! -f "$BIN_DIR/yt-dlp" ]; then
    log "yt-dlp missing — downloading local copy…"
    curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
         -o "$BIN_DIR/yt-dlp"
    chmod +x "$BIN_DIR/yt-dlp"
else
    log "yt-dlp OK"
fi

if ! command -v ffmpeg &>/dev/null; then
    log_error "FFmpeg not found. Install it."
    exit 1
fi
log "FFmpeg OK"

if ! command -v whisper-cli &>/dev/null; then
    log_error "whisper-cli not found. Install whisper-cpp."
    exit 1
fi
log "whisper-cli OK"

# Ensure model.json exists
if [ ! -f "$MODEL_JSON" ]; then
    echo '{"installed":{}, "default":"ggml-medium.en.bin"}' > "$MODEL_JSON"
fi

# Model listing logic
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
# AUDIO UTILITIES
# ─────────────────────────────────────────
get_mean_volume() {
    ffmpeg -i "$1" -af "volumedetect" -f null /dev/null 2>&1 \
        | grep 'mean_volume' | sed 's/.*mean_volume: //; s/ dB//'
}

convert_with_filter() {
    local input="$1"
    local output="$2"
    local filter="$3"
    local tag="$4"

    log "Running FFmpeg ($tag)…"

    timeout_cmd 300 ffmpeg -i "$input" \
        -af "$filter" \
        -ar 16000 -ac 1 -c:a pcm_s16le "$output" -y
}

run_whisper() {
    local wav="$1"
    local out="$2"

    timeout_cmd 7200 whisper-cli "$wav" \
        --language en \
        --model "$MODELS_DIR/$MODEL" \
        --output-txt \
        --output-json \
        --output-srt \
        --output-file "$out"
}

# ─────────────────────────────────────────
# CLEAN UP OLD INCOMPLETE JOBS
# ─────────────────────────────────────────
for job in "$WORKSPACE"/*; do
    [ -d "$job" ] || continue
    if [ ! -f "$job/transcript.txt" ]; then
        log "Cleaning incomplete job: $job"
        rm -rf "$job"
    fi
done

# ─────────────────────────────────────────
# CORE: PROCESS ONE FILE
# ─────────────────────────────────────────
process_file() {
    local file="$1"

    # Normalize job folder name based on filename
    local fname=$(basename "$file")
    local clean_name="${fname%.*}"
    clean_name="${clean_name// /_}"

    local job_id=$(date +%Y%m%d_%H%M%S)
    local job_dir="$WORKSPACE/${clean_name}_$job_id"

    mkdir -p "$job_dir"

    log "Starting job $job_id for $file"

    mv "$file" "$PROCESSING/"
    local base=$(basename "$file")
    local proc_file="$PROCESSING/$base"
    cp "$proc_file" "$job_dir/raw_input"

    # Check runtime duration
    DURATION=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$proc_file" | awk '{print int($1)}')

    if (( DURATION > 10800 )); then
        log_error "File > 3 hours — skipping."
        return 0
    fi

    # Check disk space
    SPACE_LEFT=$(df -Pk "$ROOT_DIR" | awk 'NR==2 {print int($4/1024)}')
    if (( SPACE_LEFT < 500 )); then
        log_error "Low disk (<500MB). Aborting batch."
        exit 1
    fi

    # ───── Stage 0: Loudness Analysis ─────
    log "Analyzing loudness…"
    MEAN_VOL=$(get_mean_volume "$proc_file")
    log "Mean volume: $MEAN_VOL dB"

    TARGET_DB=-18

    GAIN_STAGE1=$(awk -v m="$MEAN_VOL" -v t="$TARGET_DB" '
        BEGIN {
            g = t - m;
            if (g < 0) g = 0;
            printf "%.1f", g;
        }')

    GAIN_STAGE2=$(awk -v g="$GAIN_STAGE1" '
        BEGIN { printf "%.1f", g + 6.0 }')

    log "Computed gain: Stage1 = ${GAIN_STAGE1} dB, Stage2 = ${GAIN_STAGE2} dB"

    FILTER_STAGE1="highpass=f=120, lowpass=f=3800, dynaudnorm=p=0.8:m=10, volume=${GAIN_STAGE1}dB"
    FILTER_STAGE2="highpass=f=120, lowpass=f=4200, dynaudnorm=p=0.9:m=12, volume=${GAIN_STAGE2}dB"

    # ───── Stage 1 Conversion ─────
    convert_with_filter "$proc_file" "$job_dir/audio_stage1.wav" "$FILTER_STAGE1" "Stage 1"

    # Whisper Stage 1
    run_whisper "$job_dir/audio_stage1.wav" "$job_dir/transcript_stage1"

    # Blank ratio detection
    BLANK_RATIO=$(grep -c "\[BLANK_AUDIO\]" "$job_dir/transcript_stage1.txt" | awk '{print $1}')
    TOTAL_LINES=$(wc -l < "$job_dir/transcript_stage1.txt")
    BLANK_RATIO=$(awk -v b="$BLANK_RATIO" -v t="$TOTAL_LINES" 'BEGIN { if (t==0) print 0; else print b/t }')

    log "Blank ratio after Stage 1: $BLANK_RATIO"

    if (( $(echo "$BLANK_RATIO > 0.15" | bc -l) )); then
        log "High blank ratio — running Stage 2…"

        convert_with_filter "$proc_file" "$job_dir/audio_stage2.wav" "$FILTER_STAGE2" "Stage 2"

        run_whisper "$job_dir/audio_stage2.wav" "$job_dir/transcript"

    else
        mv "$job_dir/transcript_stage1.txt" "$job_dir/transcript.txt"
        mv "$job_dir/transcript_stage1.json" "$job_dir/transcript.json"
        mv "$job_dir/transcript_stage1.srt" "$job_dir/transcript.srt"
    fi

    mv "$proc_file" "$DONE/$base"
    log "Job $job_id completed."
}

# ─────────────────────────────────────────
# PROCESS QUEUE
# ─────────────────────────────────────────
log "Processing queue…"

# Process local files
for f in "$INCOMING"/*; do
    [ -e "$f" ] || continue
    process_file "$f" || log_error "Job failed, continuing."
done

# Process URLs
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