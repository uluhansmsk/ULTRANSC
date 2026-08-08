# Beta Changelog (Scratch)

This file tracks beta-only changes during the Python refactor period.

## v0.7.0-beta1 (2026-04-15)

- Full Python implementation under ultransc/ with shell wrappers kept only for compatibility.
- Python setup, check-setup, preflight, autofix, ice, and legacy transcription helpers.
- Shell-style config parsing for existing config/default.conf compatibility.
- Required transcript sidecar validation before a job can complete.
- Python tests with fake media tools for queue and output-contract coverage.
- Linux setup builds whisper-cli without shared lib dependency.
- macOS Metal auto-detection and safe fallback.
- Fast-mode and performance knobs (beta defaults).
- Safe optional-argument handling for Python subprocess calls.
- Preflight tests with auto-fix before runs and validation.

Notes:

- This is a scratch document and may be rewritten before final release.
