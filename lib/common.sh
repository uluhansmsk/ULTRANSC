# Shared helpers for ULTRANSC.

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$SYSTEM_LOG"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$ERROR_LOG"
}

# Universal timeout (dependency-free)
# Usage: timeout_cmd <seconds> <command> [args...]
# Returns the command exit status.
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

acquire_lock() {
    if [ -d "$LOCK_DIR" ]; then
        if [ -f "$LOCK_DIR/pid" ]; then
            local lock_pid
            lock_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
            if [[ -n "$lock_pid" && "$lock_pid" =~ ^[0-9]+$ ]] && kill -0 "$lock_pid" 2>/dev/null; then
                log_error "Another ULTRANSC run is active (pid: $lock_pid)."
                exit 1
            fi
        fi

        log "Stale lock detected. Removing $LOCK_DIR"
        rm -f "$LOCK_DIR/pid" 2>/dev/null || true
        rmdir "$LOCK_DIR" 2>/dev/null || true
    fi

    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        log_error "Another ULTRANSC run is active (lock: $LOCK_DIR)."
        exit 1
    fi
    echo "$$" > "$LOCK_DIR/pid"
}

release_lock() {
    if [ -d "$LOCK_DIR" ]; then
        rm -f "$LOCK_DIR/pid" 2>/dev/null || true
        rmdir "$LOCK_DIR" 2>/dev/null || true
    fi
}
