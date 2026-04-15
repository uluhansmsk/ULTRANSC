# Whisper command detection and execution.

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

init_whisper() {
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

    METAL_SUPPORTED="false"
    if [ "$OS" = "Darwin" ] && [ "$PREFER_METAL" = "true" ]; then
        if "$WHISPER_BIN" --help 2>/dev/null | grep -q -- "--metal"; then
            METAL_SUPPORTED="true"
            log "Metal acceleration supported"
        else
            log "Metal flag not supported by whisper binary; running on CPU"
        fi
    fi
}

run_whisper() {
    local wav="$1"
    local out="$2"

    local -a thread_args=()
    local -a preset_args=()
    local -a extra_args
    local -a metal_args=()

    extra_args=()

    if [[ -n "${THREADS_VALUE:-}" ]]; then
        thread_args=(--threads "$THREADS_VALUE")
    fi

    case "$WHISPER_SPEED_PRESET" in
        max|fast)
            preset_args=(--best-of 1 --beam-size 1)
            ;;
        balanced)
            preset_args=(--best-of 2 --beam-size 2)
            ;;
        quality)
            preset_args=()
            ;;
        *)
            preset_args=()
            ;;
    esac

    if [ -n "${WHISPER_ARGS:-}" ]; then
        read -r -a extra_args <<< "$WHISPER_ARGS"
    fi

    if [ "$METAL_SUPPORTED" = "true" ]; then
        metal_args=(--metal)
    fi

    timeout_cmd 7200 "$WHISPER_BIN" "$wav" \
        --language "$LANGUAGE" \
        --model "$MODELS_DIR/$MODEL" \
        "${thread_args[@]}" \
        "${preset_args[@]}" \
        "${extra_args[@]-}" \
        "${metal_args[@]-}" \
        --output-txt \
        --output-json \
        --output-srt \
        --output-file "$out"
}
