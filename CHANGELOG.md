# Changelog

## 0.7.0

- Ported the ULTRANSC runtime from Bash modules to a Python package under `ultransc/`.
- Kept shell files as compatibility launchers only.
- Added Python tests with fake `ffmpeg`, `ffprobe`, `whisper-cli`, and `yt-dlp` binaries.
- Hardened URL queue handling with audio-only `yt-dlp` selection, real extension detection, failed URL preservation, and interrupt recovery.
- Made preflight validation opt-in for normal transcription runs.
- Added packaging metadata, CLI entry points, and a GitHub Actions test workflow.

## 0.7.0-beta1

- Split the earlier monolithic Bash script into modular shell components.
- Added queue folders, crash recovery, retries, setup validation, and beta preflight checks.
