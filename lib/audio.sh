# Audio helper functions.

get_mean_volume() {
    ffmpeg -i "$1" -af "volumedetect" -f null /dev/null 2>&1 \
        | grep 'mean_volume' | sed 's/.*mean_volume: //; s/ dB//'
}

convert_with_filter() {
    local input="$1"
    local output="$2"
    local filter="$3"
    local tag="$4"
    local -a thread_args=()

    if [[ -n "${FFMPEG_THREADS_VALUE:-}" ]]; then
        thread_args=(-threads "$FFMPEG_THREADS_VALUE")
    fi

    log "Running FFmpeg ($tag)…"

    timeout_cmd 300 ffmpeg -i "$input" \
        -af "$filter" \
        -ar 16000 -ac 1 -c:a pcm_s16le "${thread_args[@]}" "$output" -y
}
