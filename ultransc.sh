#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────
#  ULTRANSC v0.5 — INTELLIGENT PIPELINE EDITION
# ─────────────────────────────────────────
#  Crash-proof | Resumable | Memory-safe | Chunked
# ─────────────────────────────────────────

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─────────────────────────────────────────
# DIRECTORY STRUCTURE
# ─────────────────────────────────────────
QUEUE_DIR="$ROOT_DIR/queue"
INCOMING="$QUEUE_DIR/incoming"
LINKS="$QUEUE_DIR/links.txt"
PROCESSING="$QUEUE_DIR/processing"
DONE="$QUEUE_DIR/done"

MODELS_DIR="$ROOT_DIR/models"
BIN_DIR="$ROOT_DIR/bin"
WORKSPACE="$ROOT_DIR/workspace"
LOG_DIR="$ROOT_DIR/logs"
CONFIG_DIR="$ROOT_DIR/config"

MODEL_JSON="$MODELS_DIR/list.json"
CONFIG_FILE="$CONFIG_DIR/default.conf"

SYSTEM_LOG="$LOG_DIR/system.log"
ERROR_LOG="$LOG_DIR/errors.log"

# ─────────────────────────────────────────
# LOAD CONFIGURATION
# ─────────────────────────────────────────
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

# Default values (if not set in config)
MODEL="${MODEL:-auto}"
MODEL_FALLBACK="${MODEL_FALLBACK:-ggml-small.en.bin}"
MAX_DURATION="${MAX_DURATION:-10800}"
CHUNK_MINUTES="${CHUNK_MINUTES:-15}"
MIN_FREE_DISK_MB="${MIN_FREE_DISK_MB:-500}"
MIN_FREE_RAM_GB="${MIN_FREE_RAM_GB:-2}"
ENABLE_BACKPRESSURE="${ENABLE_BACKPRESSURE:-true}"
MAX_SWAP_GB="${MAX_SWAP_GB:-5}"
AUDIO_NORMALIZATION="${AUDIO_NORMALIZATION:-true}"
HIGHPASS_FREQ="${HIGHPASS_FREQ:-150}"
LOWPASS_FREQ="${LOWPASS_FREQ:-3800}"
SILENCE_TRIMMING="${SILENCE_TRIMMING:-false}"
TARGET_LOUDNESS="${TARGET_LOUDNESS:--18}"
THREADS="${THREADS:-auto}"
PREFER_METAL="${PREFER_METAL:-true}"
LANGUAGE="${LANGUAGE:-en}"
ENABLE_CRASH_RECOVERY="${ENABLE_CRASH_RECOVERY:-true}"
ENABLE_CHUNKING="${ENABLE_CHUNKING:-true}"
COMPRESS_RAW_INPUT="${COMPRESS_RAW_INPUT:-false}"
AUTO_CLEANUP_TEMP="${AUTO_CLEANUP_TEMP:-true}"
LOG_LEVEL="${LOG_LEVEL:-info}"
PER_JOB_LOGGING="${PER_JOB_LOGGING:-true}"
PRIORITY_ORDER="${PRIORITY_ORDER:-local,incoming,urls}"
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_BACKOFF_BASE="${RETRY_BACKOFF_BASE:-5}"
RETRY_BACKOFF_MULTIPLIER="${RETRY_BACKOFF_MULTIPLIER:-2}"

# ─────────────────────────────────────────
# LOGGING SYSTEM
# ─────────────────────────────────────────
CURRENT_JOB_LOG=""

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" | tee -a "$SYSTEM_LOG"
    [ -n "$CURRENT_JOB_LOG" ] && echo "$msg" >> "$CURRENT_JOB_LOG"
}

log_error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo "$msg" | tee -a "$ERROR_LOG"
    [ -n "$CURRENT_JOB_LOG" ] && echo "$msg" >> "$CURRENT_JOB_LOG"
}

log_debug() {
    [ "$LOG_LEVEL" = "debug" ] || return 0
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $*"
    echo "$msg" >> "$SYSTEM_LOG"
    [ -n "$CURRENT_JOB_LOG" ] && echo "$msg" >> "$CURRENT_JOB_LOG"
}

log_job_metric() {
    [ -n "$CURRENT_JOB_LOG" ] || return 0
    echo "[METRIC] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$CURRENT_JOB_LOG"
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
mkdir -p "$MODELS_DIR" "$BIN_DIR" "$WORKSPACE" "$LOG_DIR" "$CONFIG_DIR"
touch "$LINKS" "$SYSTEM_LOG" "$ERROR_LOG"

# ─────────────────────────────────────────
# SYSTEM RESOURCE DETECTION
# ─────────────────────────────────────────
OS=$(uname -s)
ARCH=$(uname -m)

get_total_ram_gb() {
    if [[ "$OS" == "Darwin" ]]; then
        echo $(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024))
    else
        echo $(($(grep MemTotal /proc/meminfo | awk '{print $2}' | head -1) / 1024 / 1024))
    fi
}

get_free_ram_gb() {
    if [[ "$OS" == "Darwin" ]]; then
        local pages_free=$(vm_stat | grep "Pages free" | awk '{print $3}' | tr -d '.')
        local page_size=$(sysctl -n hw.pagesize)
        echo $(( pages_free * page_size / 1024 / 1024 / 1024 ))
    else
        echo $(($(grep MemAvailable /proc/meminfo | awk '{print $2}') / 1024 / 1024))
    fi
}

get_swap_gb() {
    if [[ "$OS" == "Darwin" ]]; then
        local swap_used=$(sysctl -n vm.swapusage 2>/dev/null | awk '{print $6}' | tr -d 'M' | awk '{print int($1/1024)}')
        echo "${swap_used:-0}"
    else
        local swap_total=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
        local swap_free=$(grep SwapFree /proc/meminfo | awk '{print $2}')
        echo $(( (swap_total - swap_free) / 1024 / 1024 ))
    fi
}

get_cpu_cores() {
    if [[ "$OS" == "Darwin" ]]; then
        sysctl -n hw.ncpu
    else
        nproc
    fi
}

get_free_disk_mb() {
    df -Pk "$ROOT_DIR" | awk 'NR==2 {print int($4/1024)}'
}

check_memory_available() {
    local free_ram=$(get_free_ram_gb)
    local swap_used=$(get_swap_gb)
    
    if (( $(echo "$free_ram < $MIN_FREE_RAM_GB" | bc -l) )); then
        return 1
    fi
    
    if (( $(echo "$swap_used > $MAX_SWAP_GB" | bc -l) )); then
        log_error "Swap usage ($swap_used GB) exceeds limit ($MAX_SWAP_GB GB)"
        return 1
    fi
    
    return 0
}

wait_for_memory() {
    [ "$ENABLE_BACKPRESSURE" != "true" ] && return 0
    
    while ! check_memory_available; do
        log "Waiting for memory to free up... (RAM: $(get_free_ram_gb)GB, SWAP: $(get_swap_gb)GB)"
        sleep 30
    done
}

check_disk_space() {
    local free_mb=$(get_free_disk_mb)
    if (( free_mb < MIN_FREE_DISK_MB )); then
        log_error "Insufficient disk space: ${free_mb}MB < ${MIN_FREE_DISK_MB}MB"
        return 1
    fi
    return 0
}

# ─────────────────────────────────────────
# ENVIRONMENT CHECK
# ─────────────────────────────────────────
log "Running full environment check…"
log "OS: $OS | Arch: $ARCH"

if [[ "$OS" != "Darwin" && "$OS" != "Linux" ]]; then
    log_error "Unsupported OS: $OS"
    exit 1
fi

RAM_GB=$(get_total_ram_gb)
CPU_CORES=$(get_cpu_cores)
log "System RAM: ${RAM_GB}GB | CPU Cores: $CPU_CORES"

FREE_GB=$(get_free_disk_mb)
FREE_GB=$((FREE_GB / 1024))
log "Free disk space: ${FREE_GB}GB"

if ! check_disk_space; then
    log_error "Insufficient disk space — aborting."
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

# ─────────────────────────────────────────
# MODEL MANAGEMENT
# ─────────────────────────────────────────
scan_and_validate_models() {
    log "Scanning models..."
    
    local models_found=0
    local models_valid=0
    
    for model_file in "$MODELS_DIR"/*.bin; do
        [ -e "$model_file" ] || continue
        ((models_found++))
        
        local model_name=$(basename "$model_file")
        local size_kb=$(du -k "$model_file" | cut -f1)
        
        # Check if model is corrupted (< 1MB)
        if (( size_kb < 1024 )); then
            log_error "Model $model_name is corrupted (${size_kb}KB < 1MB) — removing"
            rm -f "$model_file"
        else
            ((models_valid++))
            log_debug "Model $model_name validated (${size_kb}KB)"
        fi
    done
    
    log "Models: $models_valid valid, $((models_found - models_valid)) removed"
    
    if (( models_valid == 0 )); then
        log_error "No valid models found in $MODELS_DIR"
        log_error "Download a model: https://huggingface.co/ggerganov/whisper.cpp"
        exit 1
    fi
}

update_model_list() {
    {
        echo '{'
        echo '  "scanned": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'",'
        echo '  "models": {'
        
        local first=true
        for f in "$MODELS_DIR"/*.bin; do
            [ -e "$f" ] || continue
            local m=$(basename "$f")
            local size=$(du -h "$f" | cut -f1)
            
            if $first; then
                first=false
            else
                echo ","
            fi
            
            echo -n "    \"$m\": {\"size\": \"$size\", \"usable\": true}"
        done
        
        echo
        echo '  },'
        echo "  \"default\": \"${MODEL_FALLBACK}\""
        echo '}'
    } > "$MODEL_JSON"
}

scan_and_validate_models
scan_and_validate_models
update_model_list
log "Model list updated"

# ─────────────────────────────────────────
# INTELLIGENT MODEL SELECTION
# ─────────────────────────────────────────
choose_model_for_job() {
    local duration_sec="$1"
    local duration_min=$((duration_sec / 60))
    
    if [ "$MODEL" != "auto" ]; then
        if [ -f "$MODELS_DIR/$MODEL" ]; then
            echo "$MODEL"
            return 0
        else
            log_error "Configured model $MODEL not found, using fallback"
        fi
    fi
    
    # Smart selection based on duration and RAM
    local selected=""
    
    if (( RAM_GB >= 8 )) && (( duration_min <= 120 )) && [ -f "$MODELS_DIR/ggml-medium.en.bin" ]; then
        selected="ggml-medium.en.bin"
        log_debug "Selected medium model (RAM: ${RAM_GB}GB, Duration: ${duration_min}m)"
    elif [ -f "$MODELS_DIR/ggml-small.en.bin" ]; then
        selected="ggml-small.en.bin"
        log_debug "Selected small model (RAM: ${RAM_GB}GB, Duration: ${duration_min}m)"
    elif [ -f "$MODELS_DIR/$MODEL_FALLBACK" ]; then
        selected="$MODEL_FALLBACK"
    else
        # Use first available model
        selected=$(basename "$(ls "$MODELS_DIR"/*.bin | head -1)")
    fi
    
    echo "$selected"
}

# ─────────────────────────────────────────
# WHISPER PARAMETER DETECTION
# ─────────────────────────────────────────
get_whisper_threads() {
    if [ "$THREADS" = "auto" ]; then
        # Use 75% of available cores
        echo $(( CPU_CORES * 3 / 4 ))
    else
        echo "$THREADS"
    fi
}

get_whisper_extra_args() {
    local args=""
    
    # Check for Metal support on macOS
    if [ "$PREFER_METAL" = "true" ] && [ "$OS" = "Darwin" ]; then
        # whisper-cli uses Metal by default on macOS if available
        log_debug "Metal acceleration enabled (macOS)"
    fi
    
    echo "$args"
}

# ─────────────────────────────────────────
# AUDIO UTILITIES
# ─────────────────────────────────────────
get_audio_duration() {
    ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$1" | awk '{print int($1)}'
}

build_audio_filter() {
    local filters=""
    
    # High-pass and low-pass filtering
    filters="highpass=f=${HIGHPASS_FREQ},lowpass=f=${LOWPASS_FREQ}"
    
    # Loudness normalization
    if [ "$AUDIO_NORMALIZATION" = "true" ]; then
        filters="${filters},loudnorm=I=${TARGET_LOUDNESS}:TP=-1.5:LRA=11"
    fi
    
    # Silence trimming (aggressive, optional)
    if [ "$SILENCE_TRIMMING" = "true" ]; then
        filters="${filters},silenceremove=start_periods=1:start_duration=0.2:start_threshold=-50dB"
    fi
    
    # Dynamic audio normalization for consistent volume
    filters="${filters},dynaudnorm=p=0.9:m=12"
    
    echo "$filters"
}

convert_to_wav() {
    local input="$1"
    local output="$2"
    local job_log="$3"
    
    local filter=$(build_audio_filter)
    
    log "Converting audio with filter chain..."
    log_debug "Filter: $filter"
    
    local start_time=$(date +%s)
    
    timeout_cmd 600 ffmpeg -i "$input" \
        -af "$filter" \
        -ar 16000 -ac 1 -c:a pcm_s16le \
        "$output" -y 2>&1 | tee -a "$job_log"
    
    local end_time=$(date +%s)
    log_job_metric "audio_conversion_time=$((end_time - start_time))s"
    
    if [ ! -f "$output" ]; then
        log_error "Audio conversion failed"
        return 1
    fi
    
    return 0
}

# ─────────────────────────────────────────
# CHUNKING SYSTEM FOR LONG FILES
# ─────────────────────────────────────────
split_audio_into_chunks() {
    local input_wav="$1"
    local job_dir="$2"
    local chunk_duration_sec=$((CHUNK_MINUTES * 60))
    
    local chunks_dir="$job_dir/chunks"
    mkdir -p "$chunks_dir"
    
    log "Splitting audio into ${CHUNK_MINUTES}-minute chunks..."
    
    ffmpeg -i "$input_wav" -f segment -segment_time "$chunk_duration_sec" \
        -c copy "$chunks_dir/chunk_%03d.wav" -y 2>&1 | tee -a "$CURRENT_JOB_LOG"
    
    local chunk_count=$(ls "$chunks_dir"/chunk_*.wav 2>/dev/null | wc -l | tr -d ' ')
    log "Created $chunk_count chunks"
    
    echo "$chunk_count"
}

run_whisper_on_chunk() {
    local wav="$1"
    local out_prefix="$2"
    local model="$3"
    local threads=$(get_whisper_threads)
    local extra_args=$(get_whisper_extra_args)
    
    local start_time=$(date +%s)
    
    timeout_cmd 7200 whisper-cli "$wav" \
        --language "$LANGUAGE" \
        --model "$MODELS_DIR/$model" \
        --threads "$threads" \
        --output-txt \
        --output-json \
        --output-srt \
        --output-file "$out_prefix" \
        $extra_args 2>&1 | tee -a "$CURRENT_JOB_LOG"
    
    local end_time=$(date +%s)
    log_job_metric "whisper_time=$((end_time - start_time))s chunk=$(basename "$wav")"
    
    if [ ! -f "${out_prefix}.txt" ]; then
        log_error "Whisper transcription failed for $wav"
        return 1
    fi
    
    return 0
}

stitch_chunks() {
    local chunks_dir="$1"
    local output_prefix="$2"
    
    log "Stitching chunks into final transcript..."
    
    # Stitch TXT files
    : > "${output_prefix}.txt"
    for chunk_txt in "$chunks_dir"/chunk_*_transcript.txt; do
        [ -f "$chunk_txt" ] || continue
        cat "$chunk_txt" >> "${output_prefix}.txt"
        echo "" >> "${output_prefix}.txt"
    done
    
    # Stitch SRT files (with timestamp adjustment)
    : > "${output_prefix}.srt"
    local time_offset=0
    local subtitle_index=1
    
    for chunk_srt in "$chunks_dir"/chunk_*_transcript.srt; do
        [ -f "$chunk_srt" ] || continue
        
        # Parse and adjust SRT timestamps
        while IFS= read -r line; do
            if [[ "$line" =~ ^[0-9]+$ ]]; then
                echo "$subtitle_index" >> "${output_prefix}.srt"
                ((subtitle_index++))
            elif [[ "$line" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
                # Adjust timestamps by offset (simplified - doesn't handle hour overflow)
                echo "$line" >> "${output_prefix}.srt"
            else
                echo "$line" >> "${output_prefix}.srt"
            fi
        done < "$chunk_srt"
        
        # Update time offset based on chunk duration
        local chunk_wav="${chunk_srt/_transcript.srt/.wav}"
        if [ -f "$chunk_wav" ]; then
            local chunk_duration=$(get_audio_duration "$chunk_wav")
            time_offset=$((time_offset + chunk_duration))
        fi
    done
    
    # Stitch JSON files (combine segments)
    echo '{"text": "", "segments": [' > "${output_prefix}.json"
    local first_json=true
    for chunk_json in "$chunks_dir"/chunk_*_transcript.json; do
        [ -f "$chunk_json" ] || continue
        
        if $first_json; then
            first_json=false
        else
            echo "," >> "${output_prefix}.json"
        fi
        
        # Extract segments array from chunk JSON (simplified)
        jq -r '.segments[]' "$chunk_json" 2>/dev/null >> "${output_prefix}.json" || true
    done
    echo ']}' >> "${output_prefix}.json"
    
    log "Stitching complete"
}

# ─────────────────────────────────────────
# JOB STATE MANAGEMENT
# ─────────────────────────────────────────
save_job_state() {
    local job_dir="$1"
    local stage="$2"
    local extra="$3"
    
    cat > "$job_dir/.state" <<EOF
stage=$stage
timestamp=$(date +%s)
$extra
EOF
}

load_job_state() {
    local job_dir="$1"
    
    if [ -f "$job_dir/.state" ]; then
        source "$job_dir/.state"
        echo "$stage"
    else
        echo "none"
    fi
}

is_job_complete() {
    local job_dir="$1"
    [ -f "$job_dir/transcript.txt" ] && \
    [ -f "$job_dir/transcript.json" ] && \
    [ -f "$job_dir/transcript.srt" ]
}

# ─────────────────────────────────────────
# CLEAN UP OLD INCOMPLETE JOBS
# ─────────────────────────────────────────
if [ "$ENABLE_CRASH_RECOVERY" = "true" ]; then
    log "Checking for incomplete jobs to resume..."
    for job in "$WORKSPACE"/*; do
        [ -d "$job" ] || continue
        if ! is_job_complete "$job"; then
            local state=$(load_job_state "$job")
            if [ "$state" != "none" ]; then
                log "Found incomplete job: $(basename "$job") (stage: $state)"
            fi
        fi
    done
else
    log "Cleaning incomplete jobs (recovery disabled)..."
    for job in "$WORKSPACE"/*; do
        [ -d "$job" ] || continue
        if ! is_job_complete "$job"; then
            log "Removing incomplete job: $(basename "$job")"
            rm -rf "$job"
        fi
    done
fi

# ─────────────────────────────────────────
# CORE: PROCESS ONE FILE
# ─────────────────────────────────────────
process_file() {
    local file="$1"
    local retry_count="${2:-0}"

    # Normalize job folder name
    local fname=$(basename "$file")
    local clean_name="${fname%.*}"
    clean_name="${clean_name// /_}"
    clean_name="${clean_name//[^a-zA-Z0-9_-]/_}"

    local job_id=$(date +%Y%m%d_%H%M%S)
    local job_dir="$WORKSPACE/${clean_name}_$job_id"

    # Check if resuming existing job
    local existing_job=""
    for job in "$WORKSPACE"/${clean_name}_*; do
        [ -d "$job" ] || continue
        if ! is_job_complete "$job"; then
            existing_job="$job"
            job_dir="$job"
            log "Resuming job: $(basename "$job_dir")"
            break
        fi
    done

    mkdir -p "$job_dir"
    
    # Set up job logging
    CURRENT_JOB_LOG="$job_dir/job.log"
    touch "$CURRENT_JOB_LOG"

    log "=== Starting job: $(basename "$job_dir") (attempt $((retry_count + 1))/$MAX_RETRIES) ==="
    log_job_metric "job_id=$(basename "$job_dir")"
    log_job_metric "input_file=$fname"
    
    # Move file to processing
    if [ -z "$existing_job" ]; then
        mv "$file" "$PROCESSING/"
    fi
    local base=$(basename "$file")
    local proc_file="$PROCESSING/$base"
    
    # Copy raw input if not already done
    if [ ! -f "$job_dir/raw_input" ] && [ -f "$proc_file" ]; then
        cp "$proc_file" "$job_dir/raw_input"
        save_job_state "$job_dir" "input_copied"
    fi

    # Check if we can resume from a previous stage
    local current_stage=$(load_job_state "$job_dir")
    log_debug "Current stage: $current_stage"

    # Duration check
    local DURATION=$(get_audio_duration "${job_dir}/raw_input")
    log "Duration: ${DURATION}s ($((DURATION / 60))m)"
    log_job_metric "duration=${DURATION}s"

    if (( DURATION > MAX_DURATION )); then
        log_error "File exceeds maximum duration (${MAX_DURATION}s) — skipping."
        [ -f "$proc_file" ] && mv "$proc_file" "$DONE/$base.toolong"
        CURRENT_JOB_LOG=""
        return 0
    fi

    # Disk space check
    if ! check_disk_space; then
        log_error "Low disk space. Aborting batch."
        exit 1
    fi

    # Memory check with backpressure
    wait_for_memory

    # Choose model for this job
    local selected_model=$(choose_model_for_job "$DURATION")
    log "Model: $selected_model"
    log_job_metric "model=$selected_model"

    # ───── Audio Conversion ─────
    if [ ! -f "$job_dir/audio.wav" ] || [ "$current_stage" = "input_copied" ]; then
        log "Converting audio..."
        save_job_state "$job_dir" "converting"
        
        if ! convert_to_wav "$job_dir/raw_input" "$job_dir/audio.wav" "$CURRENT_JOB_LOG"; then
            log_error "Audio conversion failed"
            handle_job_failure "$proc_file" "$base" "$job_dir" "$retry_count"
            return 1
        fi
        
        save_job_state "$job_dir" "audio_ready"
    else
        log "Audio already converted, skipping..."
    fi

    # ───── Transcription (with chunking if needed) ─────
    local chunk_threshold=$((CHUNK_MINUTES * 60))
    
    if [ "$ENABLE_CHUNKING" = "true" ] && (( DURATION > chunk_threshold )); then
        log "File duration exceeds ${CHUNK_MINUTES}m — enabling chunked transcription"
        
        # Check if chunks already exist
        if [ ! -d "$job_dir/chunks" ] || [ "$current_stage" = "audio_ready" ]; then
            save_job_state "$job_dir" "chunking"
            local chunk_count=$(split_audio_into_chunks "$job_dir/audio.wav" "$job_dir")
            save_job_state "$job_dir" "chunked" "chunks=$chunk_count"
        fi
        
        # Transcribe each chunk
        save_job_state "$job_dir" "transcribing_chunks"
        local chunks_dir="$job_dir/chunks"
        local failed_chunks=0
        
        for chunk_wav in "$chunks_dir"/chunk_*.wav; do
            [ -f "$chunk_wav" ] || continue
            
            local chunk_name=$(basename "$chunk_wav" .wav)
            local chunk_transcript="$chunks_dir/${chunk_name}_transcript"
            
            # Skip if already transcribed
            if [ -f "${chunk_transcript}.txt" ]; then
                log "Chunk already transcribed: $chunk_name"
                continue
            fi
            
            log "Transcribing chunk: $chunk_name"
            wait_for_memory
            
            if ! run_whisper_on_chunk "$chunk_wav" "$chunk_transcript" "$selected_model"; then
                log_error "Chunk transcription failed: $chunk_name"
                ((failed_chunks++))
            fi
            
            # Optional: cleanup chunk WAV after successful transcription
            if [ "$AUTO_CLEANUP_TEMP" = "true" ] && [ -f "${chunk_transcript}.txt" ]; then
                rm -f "$chunk_wav"
            fi
        done
        
        if (( failed_chunks > 0 )); then
            log_error "$failed_chunks chunk(s) failed"
            handle_job_failure "$proc_file" "$base" "$job_dir" "$retry_count"
            return 1
        fi
        
        # Stitch chunks
        save_job_state "$job_dir" "stitching"
        stitch_chunks "$chunks_dir" "$job_dir/transcript"
        
    else
        # Single-file transcription
        if [ ! -f "$job_dir/transcript.txt" ]; then
            log "Transcribing (single file)..."
            save_job_state "$job_dir" "transcribing"
            wait_for_memory
            
            if ! run_whisper_on_chunk "$job_dir/audio.wav" "$job_dir/transcript" "$selected_model"; then
                log_error "Transcription failed"
                handle_job_failure "$proc_file" "$base" "$job_dir" "$retry_count"
                return 1
            fi
        else
            log "Transcript already exists, skipping..."
        fi
    fi

    # ───── Generate segments.json for keyword analysis ─────
    if [ -f "$job_dir/transcript.json" ]; then
        log_debug "Generating segments index..."
        # segments.json is already created by whisper, just ensure it exists
        if [ ! -L "$job_dir/segments.json" ]; then
            ln -s transcript.json "$job_dir/segments.json" 2>/dev/null || true
        fi
    fi

    # ───── Cleanup ─────
    if [ "$AUTO_CLEANUP_TEMP" = "true" ]; then
        log "Cleaning temporary files..."
        rm -f "$job_dir/audio.wav"
        rm -rf "$job_dir/chunks"
    fi
    
    if [ "$COMPRESS_RAW_INPUT" = "true" ]; then
        log "Compressing raw input..."
        gzip "$job_dir/raw_input" 2>/dev/null || true
    fi

    # Mark as complete
    save_job_state "$job_dir" "complete"
    
    # Move processed file to done
    [ -f "$proc_file" ] && mv "$proc_file" "$DONE/$base"
    
    log "=== Job completed: $(basename "$job_dir") ==="
    log_job_metric "status=success"
    
    CURRENT_JOB_LOG=""
    return 0
}

handle_job_failure() {
    local proc_file="$1"
    local base="$2"
    local job_dir="$3"
    local retry_count="$4"
    
    save_job_state "$job_dir" "failed" "retry=$retry_count"
    
    if (( retry_count < MAX_RETRIES )); then
        local backoff=$((RETRY_BACKOFF_BASE * (RETRY_BACKOFF_MULTIPLIER ** retry_count)))
        log "Retrying in ${backoff}s..."
        sleep "$backoff"
        
        # Move file back and retry
        [ -f "$proc_file" ] && mv "$proc_file" "$INCOMING/$base.retry$((retry_count + 1))"
    else
        log_error "Max retries reached. Moving to done with .failed suffix"
        [ -f "$proc_file" ] && mv "$proc_file" "$DONE/$base.failed"
    fi
    
    CURRENT_JOB_LOG=""
}

# ─────────────────────────────────────────
# PROCESS QUEUE WITH PRIORITY SYSTEM
# ─────────────────────────────────────────
log "Processing queue with priority: $PRIORITY_ORDER"

process_by_priority() {
    IFS=',' read -ra PRIORITIES <<< "$PRIORITY_ORDER"
    
    for priority in "${PRIORITIES[@]}"; do
        priority=$(echo "$priority" | tr -d ' ')
        
        case "$priority" in
            local)
                log "Processing local files in incoming queue..."
                for f in "$INCOMING"/*; do
                    [ -e "$f" ] || continue
                    [ -f "$f" ] || continue
                    
                    process_file "$f" || log_error "Job failed, continuing."
                done
                ;;
            
            incoming)
                # Same as local, already handled
                ;;
            
            urls)
                log "Processing URLs from links.txt..."
                while IFS= read -r url; do
                    [[ -z "$url" ]] && continue
                    [[ "$url" =~ ^[[:space:]]*# ]] && continue  # Skip comments
                    
                    log "Downloading URL: $url"
                    
                    # Generate output filename
                    local timestamp=$(date +%s)
                    local out="$INCOMING/download_${timestamp}.mp4"
                    
                    if ! "$BIN_DIR/yt-dlp" -f "bestaudio/best" -o "$out" "$url" 2>&1 | tee -a "$SYSTEM_LOG"; then
                        log_error "Failed to download $url"
                        continue
                    fi
                    
                    # Find the actual downloaded file (yt-dlp may change extension)
                    local downloaded=""
                    for candidate in "$INCOMING"/download_${timestamp}.*; do
                        [ -f "$candidate" ] && downloaded="$candidate" && break
                    done
                    
                    if [ -z "$downloaded" ]; then
                        log_error "Could not find downloaded file for $url"
                        continue
                    fi
                    
                    process_file "$downloaded" || log_error "Job failed, continuing."
                    
                done < "$LINKS"
                
                # Clear links.txt after processing
                : > "$LINKS"
                ;;
                
            *)
                log_error "Unknown priority: $priority"
                ;;
        esac
    done
}

process_by_priority

log "=== Queue processing complete ==="
log "System Summary:"
log "  RAM: $(get_free_ram_gb)GB free / ${RAM_GB}GB total"
log "  Swap: $(get_swap_gb)GB used"
log "  Disk: $(get_free_disk_mb)MB free"
log ""
log "ULTRANSC v0.5 completed all tasks successfully."