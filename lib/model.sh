# Model management.

update_model_list() {
    {
        echo '{ "installed": {'
        local first=true
        for f in "$MODELS_DIR"/*.bin; do
            [ -e "$f" ] || continue
            local m
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

choose_model() {
    if [ -n "${MODEL:-}" ] && [ "$MODEL" != "auto" ] && [ -f "$MODELS_DIR/$MODEL" ]; then
        echo "$MODEL"
        return
    fi

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

init_model() {
    if [ ! -f "$MODEL_JSON" ]; then
        echo '{"installed":{}, "default":"ggml-medium.en.bin"}' > "$MODEL_JSON"
    fi

    update_model_list
    log "Model list updated"

    ensure_model_available
    update_model_list
    log "Model list refreshed"

    MODEL=$(choose_model)
    log "Using transcription model: $MODEL"
}
