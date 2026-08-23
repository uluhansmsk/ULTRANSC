# Changelog

## 0.8.0

- Added parallel/concurrent job processing via `MAX_CONCURRENT_JOBS` (`ThreadPoolExecutor`).
- Added native WebVTT (`.vtt`), timestamped Markdown (`.md`), and standalone interactive HTML (`.html`) outputs.
- Added continuous queue watch / daemon mode (`--watch`, `-w`) with custom polling interval.
- Added queue status inspection (`--status`) and queue cleanup (`--clean [done|failed|all]`) CLI commands.
- Added CLI config overrides for `--model`, `--language`, `--concurrency`, `--fast`, and `--webhook`.
- Added webhook notification integration (`WEBHOOK_URL`) compatible with Discord and Slack.
- Added Docker (`Dockerfile`) and Docker Compose (`docker-compose.yml`) support with pre-installed FFmpeg, yt-dlp, and whisper.cpp.
- Added comprehensive Open Source community infrastructure (`CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, GitHub issue/PR templates).
- Enhanced download progress reporting for Whisper models with chunk-based transfer statistics.
- Cross-platform test suite improvements for Windows environments.

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
