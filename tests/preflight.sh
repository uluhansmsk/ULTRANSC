#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

info() { echo "[PREFLIGHT] $*"; }
fail() { echo "[PREFLIGHT][FAIL] $*"; exit 1; }

info "Running tests"
if bash "$ROOT_DIR/tests/run.sh"; then
    info "Tests passed"
    exit 0
fi

info "Tests failed, running autofix"
bash "$ROOT_DIR/tests/autofix.sh" || fail "autofix failed"

info "Re-running tests"
bash "$ROOT_DIR/tests/run.sh" || fail "tests failed after autofix"

info "Preflight complete"
