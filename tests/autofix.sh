#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

info() { echo "[AUTOFIX] $*"; }

info "Ensuring directories"
mkdir -p "$ROOT_DIR/queue/incoming" \
    "$ROOT_DIR/queue/processing" \
    "$ROOT_DIR/queue/done" \
    "$ROOT_DIR/queue/failed" \
    "$ROOT_DIR/models" \
    "$ROOT_DIR/bin" \
    "$ROOT_DIR/logs" \
    "$ROOT_DIR/workspace" \
    "$ROOT_DIR/config"

touch "$ROOT_DIR/queue/links.txt" \
    "$ROOT_DIR/logs/system.log" \
    "$ROOT_DIR/logs/errors.log"

info "Ensuring executable bits"
chmod +x "$ROOT_DIR/ultransc.sh" \
    "$ROOT_DIR/check-setup.sh" \
    "$ROOT_DIR/setup.sh" \
    "$ROOT_DIR/tests/run.sh" \
    "$ROOT_DIR/tests/preflight.sh" \
    "$ROOT_DIR/tests/autofix.sh" 2>/dev/null || true

if [ -d "$ROOT_DIR/.ultransc.lock" ]; then
    info "Removing stale lock"
    rm -f "$ROOT_DIR/.ultransc.lock/pid" 2>/dev/null || true
    rmdir "$ROOT_DIR/.ultransc.lock" 2>/dev/null || true
fi

info "Autofix complete"
