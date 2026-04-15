# Environment initialization and checks.

load_config() {
    CONFIG_FILE="$ROOT_DIR/config/default.conf"
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE" 2>/dev/null || true
    fi
}

init_paths() {
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
    CONFIG_DIR="${CONFIG_DIR:-$ROOT_DIR/config}"

    SYSTEM_LOG="$LOG_DIR/system.log"
    ERROR_LOG="$LOG_DIR/errors.log"
    LOCK_DIR="$ROOT_DIR/.ultransc.lock"
}

init_defaults() {
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
    FAST_MODE="${FAST_MODE:-auto}"
    WHISPER_SPEED_PRESET="${WHISPER_SPEED_PRESET:-fast}"
    WHISPER_ARGS="${WHISPER_ARGS:-}"
    FFMPEG_THREADS="${FFMPEG_THREADS:-auto}"
    STAGE2_MAX_DURATION="${STAGE2_MAX_DURATION:-0}"
    PREFER_METAL="${PREFER_METAL:-true}"

    if [ "${MODEL:-auto}" = "auto" ]; then
        DEFAULT_MODEL="ggml-medium.en.bin"
    else
        DEFAULT_MODEL="$MODEL"
    fi
}

init_folders() {
    mkdir -p "$INCOMING" "$PROCESSING" "$DONE" "$FAILED"
    mkdir -p "$MODELS_DIR" "$BIN_DIR" "$WORKSPACE" "$LOG_DIR" "$CONFIG_DIR"
    touch "$LINKS" "$SYSTEM_LOG" "$ERROR_LOG"
}

bootstrap_ytdlp() {
    if [ ! -f "$BIN_DIR/yt-dlp" ]; then
        log "yt-dlp missing — downloading local copy…"
        curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
             -o "$BIN_DIR/yt-dlp"
        chmod +x "$BIN_DIR/yt-dlp"
    else
        log "yt-dlp OK"
    fi
}

check_tools() {
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
}

check_resources() {
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
}

check_environment() {
    log "Running full environment check…"

    OS=$(uname -s)
    if [[ "$OS" != "Darwin" && "$OS" != "Linux" ]]; then
        log_error "Unsupported OS: $OS"
        exit 1
    fi

    ARCH=$(uname -m)
    log "Detected architecture: $ARCH"

    if [ "$OS" = "Darwin" ]; then
        CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
    else
        CPU_CORES=$(nproc 2>/dev/null || echo 1)
    fi
    if [[ -z "$CPU_CORES" || ! "$CPU_CORES" =~ ^[0-9]+$ ]]; then
        CPU_CORES=1
    fi

    RAM_GB=$(($(sysctl -n hw.memsize 2>/dev/null || grep MemTotal /proc/meminfo | awk '{print $2 * 1024}') / 1024 / 1024 / 1024))
    log "System RAM: ${RAM_GB}GB"
    log "CPU cores: ${CPU_CORES}"

    if [ "$THREADS" = "auto" ]; then
        THREADS_VALUE="$CPU_CORES"
    else
        THREADS_VALUE="$THREADS"
    fi

    if [ "$FFMPEG_THREADS" = "auto" ]; then
        FFMPEG_THREADS_VALUE="$CPU_CORES"
    else
        FFMPEG_THREADS_VALUE="$FFMPEG_THREADS"
    fi

    log "Whisper threads: ${THREADS_VALUE}"
    log "FFmpeg threads: ${FFMPEG_THREADS_VALUE}"

    if [ "$FAST_MODE" = "auto" ]; then
        if [ "$OS" = "Darwin" ]; then
            FAST_MODE_VALUE="false"
        else
            FAST_MODE_VALUE="true"
        fi
    else
        FAST_MODE_VALUE="$FAST_MODE"
    fi
    log "Speed preset: ${WHISPER_SPEED_PRESET} (fast mode: ${FAST_MODE_VALUE})"

    check_resources
    bootstrap_ytdlp
    check_tools
}
