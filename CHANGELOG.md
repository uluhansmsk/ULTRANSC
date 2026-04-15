# Changelog

All notable changes to ULTRANSC are documented in this file.

## v0.7.0 (2026-04-15)

Release type: Linux setup hardening

### Added

- Linux setup now builds whisper-cli with static linking to avoid missing libwhisper.so.1 at runtime.
- Fast mode to skip Stage 2 for speed.
- Whisper speed presets and extra args support.
- Thread auto-detection for whisper and ffmpeg.
- Metal acceleration support on macOS when available.
- Stale lock recovery to avoid false "already running" blocks.

### Fixed

- Resolved Linux runtime error: libwhisper.so.1 missing when using local bin/whisper-cli.
- Avoided macOS failures by only enabling --metal when supported by the whisper binary.
- Fixed WHISPER_ARGS expansion to avoid unbound variable errors under set -u.
- Fixed metal_args expansion to avoid unbound variable errors under set -u.

## v0.6.0 (2026-04-15)

Release type: Stability and operational hardening

### Added

- Single-instance lock using .ultransc.lock to prevent concurrent queue mutation.
- queue/failed as a dedicated sink for failed or invalid inputs.
- Retry engine with exponential backoff for ffmpeg and whisper-cli stages.
- ffprobe runtime dependency check in startup validation.
- URL queue persistence flow that rewrites links.txt with only failed/pending URLs.
- Runtime config defaults mapped from config/default.conf for key operational knobs.
- setup.sh bootstrap script for first-run setup on macOS and Linux.
- Linux-capable whisper command detection (whisper-cli, whisper-cpp, whisper, and local bin/whisper-cli).
- Automatic model bootstrap when models/ is empty (configurable).

### Changed

- Model selection now honors explicit MODEL when present and available.
- Auto model selection now gracefully falls back to any installed .bin model if preferred models are missing.
- Job IDs now include a random suffix to reduce collision risk in dense batch runs.
- MAX_DURATION, MIN_FREE_DISK_MB, TARGET_LOUDNESS, and LANGUAGE are now runtime-configurable.
- THREADS and WHISPER_CMD are now config-driven.
- README expanded with Linux setup and dual-machine operation guidance.

### Fixed

- Removed hidden hard dependency on bc by replacing float comparison with awk logic.
- Implemented actual crash recovery behavior by re-queueing queue/processing items to queue/incoming when enabled.
- Added robust duration parsing failure handling for invalid/corrupt media.
- Added output existence checks to fail fast when whisper stage artifacts are missing.
- Fixed setup validator behavior under set -e so warnings no longer abort execution.
- Fixed ice.sh lecture folder discovery for names containing spaces and shell-sensitive patterns.
- Fixed ice.sh keyword scanning to avoid hard exit when grep returns no matches.

### Operational Notes

- Recommended free disk for large runs (50 lectures): at least 20GB.
- AUTO_CLEANUP_TEMP=true is recommended for long runs to reduce disk pressure.
- Failed files are moved to queue/failed and should be reviewed and retried manually.

## v0.5 Stable (2026-01-23)

Release type: Recovery from broken v0.5.0

### Changed

- Reverted to known stable core behavior from earlier working branch.
- Kept minimal configuration support.

### Fixed

- Restored practical two-stage processing and queue workflow.
- Resolved environment check instability present in v0.5.0 line.

## v0.5.0 (2026-01-07) - BROKEN

Status: Deprecated, not recommended for use.

### Notes

- Introduced experimental pipeline controls but with severe runtime issues.
- Marked as unusable in production workloads.

## v0.3.3b (2025-12)

### Added

- Two-stage audio processing with blank-audio detection.
- Dynamic gain adjustment from measured mean volume.
- Queue-oriented workflow for local-first processing.

### Notes

- Served as the practical baseline used later for recovery.

## v0.3.x - v0.1

Early development iterations.
