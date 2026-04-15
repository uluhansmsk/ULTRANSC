#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────
#  ULTRANSC v0.7.0-beta1 — BETA EDITION
# ─────────────────────────────────────────

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load modular components
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/env.sh"
source "$ROOT_DIR/lib/model.sh"
source "$ROOT_DIR/lib/whisper.sh"
source "$ROOT_DIR/lib/audio.sh"
source "$ROOT_DIR/lib/job.sh"
source "$ROOT_DIR/lib/queue.sh"

load_config
init_paths
init_defaults
init_folders

if [ -f "$ROOT_DIR/tests/preflight.sh" ]; then
	bash "$ROOT_DIR/tests/preflight.sh"
fi

trap 'log_error "ULTRANSC crashed inside a job. Continuing…"' ERR
trap release_lock EXIT

acquire_lock

check_environment
init_whisper
init_model

clean_incomplete_jobs
run_queue

log "Queue empty. ULTRANSC completed all tasks."
