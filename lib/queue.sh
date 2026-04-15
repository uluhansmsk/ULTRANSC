# Queue processing.

recover_processing_queue() {
    if [ "$ENABLE_CRASH_RECOVERY" = "true" ]; then
        for f in "$PROCESSING"/*; do
            [ -e "$f" ] || continue
            log "Recovering interrupted file: $(basename "$f")"
            mv "$f" "$INCOMING/"
        done
    fi
}

process_incoming_queue() {
    for f in "$INCOMING"/*; do
        [ -e "$f" ] || continue
        process_file "$f" || log_error "Job failed, continuing."
    done
}

process_url_queue() {
    local tmp_links
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
}

run_queue() {
    log "Processing queue…"
    recover_processing_queue
    process_incoming_queue
    process_url_queue
}
