#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; exit 1; }

run_syntax_checks() {
    local files=(
        "$ROOT_DIR/ultransc.sh"
        "$ROOT_DIR/lib/common.sh"
        "$ROOT_DIR/lib/env.sh"
        "$ROOT_DIR/lib/model.sh"
        "$ROOT_DIR/lib/whisper.sh"
        "$ROOT_DIR/lib/audio.sh"
        "$ROOT_DIR/lib/job.sh"
        "$ROOT_DIR/lib/queue.sh"
        "$ROOT_DIR/check-setup.sh"
        "$ROOT_DIR/setup.sh"
    )

    local f
    for f in "${files[@]}"; do
        bash -n "$f" || fail "syntax check failed: $f"
    done
    pass "syntax checks"
}

run_module_checks() {
    # shellcheck disable=SC1090
    source "$ROOT_DIR/lib/common.sh"
    # shellcheck disable=SC1090
    source "$ROOT_DIR/lib/env.sh"
    # shellcheck disable=SC1090
    source "$ROOT_DIR/lib/model.sh"
    # shellcheck disable=SC1090
    source "$ROOT_DIR/lib/whisper.sh"
    # shellcheck disable=SC1090
    source "$ROOT_DIR/lib/audio.sh"
    # shellcheck disable=SC1090
    source "$ROOT_DIR/lib/job.sh"
    # shellcheck disable=SC1090
    source "$ROOT_DIR/lib/queue.sh"

    declare -F load_config >/dev/null || fail "load_config missing"
    declare -F init_paths >/dev/null || fail "init_paths missing"
    declare -F init_model >/dev/null || fail "init_model missing"
    declare -F run_queue >/dev/null || fail "run_queue missing"
    declare -F process_file >/dev/null || fail "process_file missing"

    pass "module exports"
}

run_config_checks() {
    grep -q "FAST_MODE" "$ROOT_DIR/config/default.conf" || fail "FAST_MODE missing"
    grep -q "WHISPER_SPEED_PRESET" "$ROOT_DIR/config/default.conf" || fail "WHISPER_SPEED_PRESET missing"
    grep -q "PREFER_METAL" "$ROOT_DIR/config/default.conf" || fail "PREFER_METAL missing"
    pass "config keys"
}

run_syntax_checks
run_module_checks
run_config_checks

run_executable_checks() {
    local files=(
        "$ROOT_DIR/ultransc.sh"
        "$ROOT_DIR/check-setup.sh"
        "$ROOT_DIR/setup.sh"
        "$ROOT_DIR/tests/run.sh"
        "$ROOT_DIR/tests/preflight.sh"
        "$ROOT_DIR/tests/autofix.sh"
    )

    local f
    for f in "${files[@]}"; do
        [ -x "$f" ] || fail "not executable: $f"
    done

    pass "executables"
}

run_executable_checks

pass "all tests"
