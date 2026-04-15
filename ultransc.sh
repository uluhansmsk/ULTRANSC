#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────
#  ULTRANSC v0.6.0 — STABLE EDITION
# ─────────────────────────────────────────

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load optional config file if it exists
CONFIG_FILE="$ROOT_DIR/config/default.conf"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE" 2>/dev/null || true
fi

QUEUE_DIR="$ROOT_DIR/queue"
INCOMING="$QUEUE_DIR/incoming"
LINKS="$QUEUE_DIR/links.txt"
PROCESSING="$QUEUE_DIR/processing"
DONE="$QUEUE_DIR/done"
FAILED="$QUEUE_DIR/failed"

MODELS_DIR="$ROOT_DIR/models"
BIN_DIR="$ROOT_DIR/bin"
WORKSPACE="$ROOT_DIR/workspace"
LOG_DIR="$ROOT_DIR/logs"

MODEL_JSON="$MODELS_DIR/list.json"
if [ "${MODEL:-auto}" = "auto" ]; then
    DEFAULT_MODEL="ggml-medium.en.bin"
else
    DEFAULT_MODEL="$MODEL"
fi
CONFIG_DIR="${CONFIG_DIR:-$ROOT_DIR/config}"

SYSTEM_LOG="$LOG_DIR/system.log"
ERROR_LOG="$LOG_DIR/errors.log"
LOCK_DIR="$ROOT_DIR/.ultransc.lock"

# Runtime defaults (overridable from config/default.conf)
MAX_DURATION="${MAX_DURATION:-10800}"
MIN_FREE_DISK_MB="${MIN_FREE_DISK_MB:-500}"
TARGET_LOUDNESS="${TARGET_LOUDNESS:--18}"
LANGUAGE="${LANGUAGE:-en}"
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_BACKOFF_BASE="${RETRY_BACKOFF_BASE:-5}"
RETRY_BACKOFF_MULTIPLIER="${RETRY_BACKOFF_MULTIPLIER:-2}"
ENABLE_CRASH_RECOVERY="${ENABLE_CRASH_RECOVERY:-true}"
AUTO_CLEANUP_TEMP="${AUTO_CLEANUP_TEMP:-true}"
AUTO_DOWNLOAD_MODEL="${AUTO_DOWNLOAD_MODEL:-true}"
MODEL_BASE_URL="${MODEL_BASE_URL:-https://huggingface.co/ggerganov/whisper.cpp/resolve/main}"
WHISPER_CMD="${WHISPER_CMD:-auto}"
THREADS="${THREADS:-auto}"

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

on_exit() {
    [ -d "$LOCK_DIR" ] && rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap on_exit EXIT

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
mkdir -p "$FAILED"
mkdir -p "$MODELS_DIR" "$BIN_DIR" "$WORKSPACE" "$LOG_DIR" "$CONFIG_DIR"
touch "$LINKS" "$SYSTEM_LOG" "$ERROR_LOG"

# Single-instance guard to avoid queue corruption during long runs.
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    log_error "Another ULTRANSC run is active (lock: $LOCK_DIR)."
    exit 1
fi

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

if ! command -v ffprobe &>/dev/null; then
    log_error "ffprobe not found. Install FFmpeg package with ffprobe."
    exit 1
fi
log "ffprobe OK"

detect_whisper_cmd() {
    local candidate

    if [ "$WHISPER_CMD" != "auto" ]; then
        if [[ "$WHISPER_CMD" == */* ]] && [ -x "$WHISPER_CMD" ]; then
            echo "$WHISPER_CMD"
            return 0
        fi

        if command -v "$WHISPER_CMD" &>/dev/null; then
            echo "$WHISPER_CMD"
            return 0
        fi
        return 1
    fi

    for candidate in "$BIN_DIR/whisper-cli" "$BIN_DIR/whisper-cpp" whisper-cli whisper-cpp whisper; do
        if [[ "$candidate" == */* ]]; then
            [ -x "$candidate" ] || continue
            echo "$candidate"
            return 0
        fi

        command -v "$candidate" &>/dev/null || continue
        echo "$candidate"
        return 0
    done

    return 1
}

WHISPER_BIN="$(detect_whisper_cmd || true)"
if [ -z "$WHISPER_BIN" ]; then
    if [ "$OS" = "Linux" ]; then
        log_error "Whisper binary not found. Set WHISPER_CMD or install whisper.cpp (whisper-cli)."
    else
        log_error "Whisper binary not found. Install whisper-cpp (whisper-cli)."
    fi
    exit 1
fi
log "Whisper command OK: $WHISPER_BIN"

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

ensure_model_available() {
    local model_count
    local model_to_download
    local model_url
    local target_path

    model_count=$(find "$MODELS_DIR" -maxdepth 1 -name "*.bin" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$model_count" -gt 0 ]; then
        return 0
    fi

    if [ "$AUTO_DOWNLOAD_MODEL" != "true" ]; then
        log_error "No model found in $MODELS_DIR and AUTO_DOWNLOAD_MODEL=false"
        exit 1
    fi

    model_to_download="$DEFAULT_MODEL"
    model_url="$MODEL_BASE_URL/$model_to_download"
    target_path="$MODELS_DIR/$model_to_download"

    log "No models found — downloading default model: $model_to_download"
    if ! curl -fL "$model_url" -o "$target_path"; then
        log_error "Model download failed: $model_url"
        rm -f "$target_path"
        exit 1
    fi

    if [ ! -s "$target_path" ]; then
        log_error "Downloaded model is empty: $target_path"
        rm -f "$target_path"
        exit 1
    fi

    log "Model downloaded successfully: $model_to_download"
}

ensure_model_available
update_model_list
log "Model list refreshed"

choose_model() {
    # Honor explicit model config when available.
    if [ -n "${MODEL:-}" ] && [ "$MODEL" != "auto" ] && [ -f "$MODELS_DIR/$MODEL" ]; then
        echo "$MODEL"
        return
    fi

    # Auto-select by RAM with graceful fallback to any installed model.
    if (( RAM_GB >= 6 )) && [ -f "$MODELS_DIR/ggml-medium.en.bin" ]; then
        echo "ggml-medium.en.bin"
        return
    fi

    if [ -f "$MODELS_DIR/ggml-small.en.bin" ]; then
        echo "ggml-small.en.bin"
        return
    fi

    for f in "$MODELS_DIR"/*.bin; do
        [ -f "$f" ] || continue
        basename "$f"
        return
    done

    log_error "No Whisper models found in $MODELS_DIR"
    exit 1
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

run_with_retries() {
    local attempt=1
    local delay="$RETRY_BACKOFF_BASE"

    while true; do
        if "$@"; then
            return 0
        fi

        if (( attempt >= MAX_RETRIES )); then
            return 1
        fi

        log_error "Attempt $attempt failed. Retrying in ${delay}s..."
        sleep "$delay"
        delay=$(( delay * RETRY_BACKOFF_MULTIPLIER ))
        attempt=$(( attempt + 1 ))
    done
}

run_whisper() {
    local wav="$1"
    local out="$2"

    local thread_args=()
    if [ "$THREADS" != "auto" ]; then
        thread_args=(--threads "$THREADS")
    fi

    timeout_cmd 7200 "$WHISPER_BIN" "$wav" \
        --language "$LANGUAGE" \
        --model "$MODELS_DIR/$MODEL" \
        "${thread_args[@]}" \
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

    local job_id="$(date +%Y%m%d_%H%M%S)_$RANDOM"
    local job_dir="$WORKSPACE/${clean_name}_$job_id"

    mkdir -p "$job_dir"

    log "Starting job $job_id for $file"

    local base=$(basename "$file")
    mv "$file" "$PROCESSING/"
    local proc_file="$PROCESSING/$base"

    fail_job() {
        local reason="$1"
        log_error "$reason"
        [ -f "$proc_file" ] && mv "$proc_file" "$FAILED/$base" 2>/dev/null || true
        return 1
    }

    if [ ! -f "$proc_file" ]; then
        fail_job "Could not move file to processing queue: $file"
        return 1
    fi

    cp "$proc_file" "$job_dir/raw_input"

    # Check runtime duration
    DURATION=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$proc_file" 2>/dev/null | awk '{print int($1)}' || true)

    if [[ -z "$DURATION" || ! "$DURATION" =~ ^[0-9]+$ ]]; then
        fail_job "Cannot read media duration (possibly corrupt file): $base"
        return 1
    fi

    if (( DURATION > MAX_DURATION )); then
        log_error "File exceeds MAX_DURATION (${MAX_DURATION}s) — skipping."
        mv "$proc_file" "$FAILED/$base"
        return 0
    fi

    # Check disk space
    SPACE_LEFT=$(df -Pk "$ROOT_DIR" | awk 'NR==2 {print int($4/1024)}')
    if (( SPACE_LEFT < MIN_FREE_DISK_MB )); then
        log_error "Low disk (<${MIN_FREE_DISK_MB}MB). Aborting batch."
        exit 1
    fi

    # ───── Stage 0: Loudness Analysis ─────
    log "Analyzing loudness…"
    MEAN_VOL=$(get_mean_volume "$proc_file")
    if [[ -z "${MEAN_VOL:-}" ]]; then
        MEAN_VOL="${TARGET_LOUDNESS}"
    fi
    log "Mean volume: $MEAN_VOL dB"

    TARGET_DB="$TARGET_LOUDNESS"

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
    if ! run_with_retries convert_with_filter "$proc_file" "$job_dir/audio_stage1.wav" "$FILTER_STAGE1" "Stage 1"; then
        fail_job "FFmpeg Stage 1 failed for $base"
        return 1
    fi

    # Whisper Stage 1
    if ! run_with_retries run_whisper "$job_dir/audio_stage1.wav" "$job_dir/transcript_stage1"; then
        fail_job "Whisper Stage 1 failed for $base"
        return 1
    fi

    if [ ! -s "$job_dir/transcript_stage1.txt" ]; then
        fail_job "Missing Stage 1 transcript output for $base"
        return 1
    fi

    # Blank ratio detection
    BLANK_RATIO=$(grep -c "\[BLANK_AUDIO\]" "$job_dir/transcript_stage1.txt" | awk '{print $1}')
    TOTAL_LINES=$(wc -l < "$job_dir/transcript_stage1.txt")
    BLANK_RATIO=$(awk -v b="$BLANK_RATIO" -v t="$TOTAL_LINES" 'BEGIN { if (t==0) print 0; else print b/t }')

    log "Blank ratio after Stage 1: $BLANK_RATIO"

    if awk -v r="$BLANK_RATIO" 'BEGIN { exit !(r > 0.15) }'; then
        log "High blank ratio — running Stage 2…"

        if ! run_with_retries convert_with_filter "$proc_file" "$job_dir/audio_stage2.wav" "$FILTER_STAGE2" "Stage 2"; then
            fail_job "FFmpeg Stage 2 failed for $base"
            return 1
        fi

        if ! run_with_retries run_whisper "$job_dir/audio_stage2.wav" "$job_dir/transcript"; then
            fail_job "Whisper Stage 2 failed for $base"
            return 1
        fi

        if [ ! -s "$job_dir/transcript.txt" ]; then
            fail_job "Missing Stage 2 transcript output for $base"
            return 1
        fi

    else
        mv "$job_dir/transcript_stage1.txt" "$job_dir/transcript.txt"
        mv "$job_dir/transcript_stage1.json" "$job_dir/transcript.json"
        mv "$job_dir/transcript_stage1.srt" "$job_dir/transcript.srt"
    fi

    # Create segments.json symlink for ice.sh integration
    if [ -f "$job_dir/transcript.json" ]; then
        ln -sf transcript.json "$job_dir/segments.json" 2>/dev/null || true
    fi

    if [ "$AUTO_CLEANUP_TEMP" = "true" ]; then
        rm -f "$job_dir/audio_stage1.wav" "$job_dir/audio_stage2.wav"
    fi

    mv "$proc_file" "$DONE/$base"
    log "Job $job_id completed."
}

# ─────────────────────────────────────────
# PROCESS QUEUE
# ─────────────────────────────────────────
log "Processing queue…"

# Recover interrupted jobs by moving processing files back into the queue.
if [ "$ENABLE_CRASH_RECOVERY" = "true" ]; then
    for f in "$PROCESSING"/*; do
        [ -e "$f" ] || continue
        log "Recovering interrupted file: $(basename "$f")"
        mv "$f" "$INCOMING/"
    done
fi

# Process local files
for f in "$INCOMING"/*; do
    [ -e "$f" ] || continue
    process_file "$f" || log_error "Job failed, continuing."
done

# Process URLs and keep only failed/pending URLs in links.txt.
tmp_links="$LINKS.tmp"
> "$tmp_links"

while IFS= read -r url; do
    [[ -z "$url" ]] && continue

    log "Downloading URL: $url"
    out="$INCOMING/download_$(date +%s)_$RANDOM.mp4"

    if ! "$BIN_DIR/yt-dlp" -o "$out" "$url"; then
        log_error "Failed to download $url"
        echo "$url" >> "$tmp_links"
        continue
    fi

    if ! process_file "$out"; then
        log_error "URL job failed, keeping URL for retry: $url"
        echo "$url" >> "$tmp_links"
    fi

done < "$LINKS"

mv "$tmp_links" "$LINKS"

log "Queue empty. ULTRANSC completed all tasks."