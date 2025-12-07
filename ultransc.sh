#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────
# ULTRANSC v0.3.3 — Faint Audio Intelligence Edition
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

mkdir -p "$INCOMING" "$PROCESSING" "$DONE"
mkdir -p "$MODELS_DIR" "$BIN_DIR" "$WORKSPACE" "$LOG_DIR"
touch "$LINKS" "$SYSTEM_LOG" "$ERROR_LOG"

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
# UNIVERSAL TIMEOUT
# ─────────────────────────────────────────
timeout_cmd() {
    local secs="$1"
    shift

    (
        "$@" &
        local pid=$!

        (
            sleep "$secs"
            kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
        ) &
        local watcher=$!

        wait "$pid"
        local status=$?

        kill -0 "$watcher" 2>/dev/null && kill -9 "$watcher" 2>/dev/null
        return $status
    )
}

# ─────────────────────────────────────────
# ENVIRONMENT CHECK
# ─────────────────────────────────────────
log "Running full environment check…"

ARCH=$(uname -m)
log "Detected architecture: $ARCH"

RAM_GB=$(($(sysctl -n hw.memsize 2>/dev/null || grep MemTotal /proc/meminfo | awk '{print $2 * 1024}') / 1024 / 1024 / 1024))
log "System RAM: ${RAM_GB}GB"

if ! command -v ffmpeg >/dev/null; then
    log_error "FFmpeg not found."
    exit 1
fi
log "FFmpeg OK"

if ! command -v whisper-cli >/dev/null; then
    log_error "whisper-cli not found."
    exit 1
fi
log "whisper-cli OK"

# yt-dlp bootstrap
if [ ! -f "$BIN_DIR/yt-dlp" ]; then
    log "Downloading yt-dlp…"
    curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
        -o "$BIN_DIR/yt-dlp"
    chmod +x "$BIN_DIR/yt-dlp"
else
    log "yt-dlp OK"
fi

# Model list setup
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
#  AUDIO ANALYSIS (mean volume)
# ─────────────────────────────────────────
get_mean_volume() {
    ffmpeg -i "$1" -af "volumedetect" -f null /dev/null 2>&1 \
        | grep 'mean_volume' | sed 's/.*mean_volume: //; s/ dB//'
}

# Count BLANK_AUDIO lines from Whisper SRT
count_blank_segments() {
    grep -c "\[BLANK_AUDIO\]" "$1" || echo 0
}

# ─────────────────────────────────────────
# FFMPEG FILTER STAGES
# ─────────────────────────────────────────

FILTER_STAGE1="highpass=f=120, lowpass=f=3800, dynaudnorm=p=0.8:m=10, volume=12dB"
FILTER_STAGE2="highpass=f=120, lowpass=f=4200, dynaudnorm=p=0.9:m=12, volume=18dB"

convert_with_filter() {
    local input="$1"
    local output="$2"
    local filter="$3"
    local tag="$4"

    log "Running FFmpeg ($tag)…"

    timeout_cmd 300 ffmpeg -i "$input" \
        -af "$filter" \
        -ar 16000 -ac 1 -c:a pcm_s16le \
        "$output" -y
}

# ─────────────────────────────────────────
# WHISPER RUNNER
# ─────────────────────────────────────────
run_whisper() {
    local wav="$1"
    local outprefix="$2"

    timeout_cmd 7200 whisper-cli "$wav" \
        --language en \
        --model "$MODELS_DIR/$MODEL" \
        --output-txt \
        --output-srt \
        --output-json \
        --output-file "$outprefix"
}

# ─────────────────────────────────────────
# PROCESS FILE
# ─────────────────────────────────────────
process_file() {
    local file="$1"

    # sanitize filename for folder
    local base=$(basename "$file")
    local safe_name="${base//[^A-Za-z0-9._-]/_}"
    local name="${safe_name%.*}"

    local job_id=$(date +%Y%m%d_%H%M%S)
    local job_dir="$WORKSPACE/${name}_$job_id"

    mkdir -p "$job_dir"
    log "Starting job $job_id for $file"

    mv "$file" "$PROCESSING/"
    local proc_file="$PROCESSING/$base"
    cp "$proc_file" "$job_dir/raw_input"

    # Duration check
    DURATION=$(ffprobe -v error -show_entries format=duration \
               -of default=noprint_wrappers=1:nokey=1 "$proc_file" \
               | awk '{print int($1)}')
    if (( DURATION > 10800 )); then
        log_error "File exceeds 3 hours, skipping."
        return
    fi

    # Stage 0: loudness evaluation
    log "Analyzing loudness…"
    MEAN_VOL=$(get_mean_volume "$proc_file")
    log "Mean volume: $MEAN_VOL dB"

    # Convert using Stage 1 first
    convert_with_filter "$proc_file" "$job_dir/audio_stage1.wav" "$FILTER_STAGE1" "Stage 1"

    # Whisper Stage 1
    run_whisper "$job_dir/audio_stage1.wav" "$job_dir/transcript_stage1"

    # Check blank audio ratio
    SRT1="$job_dir/transcript_stage1.srt"
    TOTAL_LINES=$(wc -l < "$SRT1")
    BLANKS=$(count_blank_segments "$SRT1")
    BLANK_RATIO=$(awk -v b="$BLANKS" -v t="$TOTAL_LINES" 'BEGIN { if (t==0) print 1; else print b/t }')

    log "Blank ratio after Stage 1: $BLANK_RATIO"

    USED_STAGE="stage1"
    RERUN="false"

    if (( $(echo "$BLANK_RATIO > 0.15" | bc -l) )); then
        log "High blank ratio detected — reprocessing with Stage 2"

        convert_with_filter "$proc_file" "$job_dir/audio_stage2.wav" "$FILTER_STAGE2" "Stage 2"

        run_whisper "$job_dir/audio_stage2.wav" "$job_dir/transcript"

        USED_STAGE="stage2"
        RERUN="true"
    else
        mv "$job_dir/transcript_stage1.txt" "$job_dir/transcript.txt"
        mv "$job_dir/transcript_stage1.json" "$job_dir/transcript.json"
        mv "$job_dir/transcript_stage1.srt" "$job_dir/transcript.srt"
        USED_STAGE="stage1"
    fi

    # Audio analysis
    cat > "$job_dir/audio_analysis.json" <<EOF
{
    "mean_volume_db": $MEAN_VOL,
    "blank_ratio": $BLANK_RATIO,
    "filter_used": "$USED_STAGE",
    "rerun": $RERUN
}
EOF

    mv "$proc_file" "$DONE/$base"
    log "Job $job_id completed."
}

# ─────────────────────────────────────────
# QUEUE EXECUTION
# ─────────────────────────────────────────
log "Processing queue…"

for f in "$INCOMING"/*; do
    [ -e "$f" ] || continue
    process_file "$f"
done

while IFS= read -r url; do
    [[ -z "$url" ]] && continue

    out="$INCOMING/download_$(date +%s).mp4"
    log "Downloading: $url"

    if "$BIN_DIR/yt-dlp" -o "$out" "$url"; then
        process_file "$out"
    else
        log_error "Download failed: $url"
    fi

done < "$LINKS"

log "Queue empty. ULTRANSC completed all tasks."