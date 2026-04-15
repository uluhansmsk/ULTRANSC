# Job processing.

clean_incomplete_jobs() {
    for job in "$WORKSPACE"/*; do
        [ -d "$job" ] || continue
        if [ ! -f "$job/transcript.txt" ]; then
            log "Cleaning incomplete job: $job"
            rm -rf "$job"
        fi
    done
}

process_file() {
    local file="$1"

    # Normalize job folder name based on filename
    local fname
    fname=$(basename "$file")
    local clean_name="${fname%.*}"
    clean_name="${clean_name// /_}"

    local job_id
    job_id="$(date +%Y%m%d_%H%M%S)_$RANDOM"
    local job_dir="$WORKSPACE/${clean_name}_$job_id"

    mkdir -p "$job_dir"

    log "Starting job $job_id for $file"

    local base
    base=$(basename "$file")
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

    should_run_stage2="false"
    if [ "$FAST_MODE_VALUE" = "true" ]; then
        log "Fast mode enabled — skipping Stage 2"
    elif [[ "$STAGE2_MAX_DURATION" =~ ^[0-9]+$ ]] && (( STAGE2_MAX_DURATION > 0 )) && (( DURATION > STAGE2_MAX_DURATION )); then
        log "Stage 2 skipped due to STAGE2_MAX_DURATION (${STAGE2_MAX_DURATION}s)"
    elif awk -v r="$BLANK_RATIO" 'BEGIN { exit !(r > 0.15) }'; then
        should_run_stage2="true"
    fi

    if [ "$should_run_stage2" = "true" ]; then
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
