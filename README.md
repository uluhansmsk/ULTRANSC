# ULTRANSC

[![CI](https://github.com/Dev-Emree/ULTRANSC/actions/workflows/tests.yml/badge.svg)](https://github.com/Dev-Emree/ULTRANSC/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Python 3.9+](https://img.shields.io/badge/python-3.9+-blue.svg)](https://www.python.org/downloads/)
[![Docker](https://img.shields.io/badge/docker-ready-blue.svg)](Dockerfile)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

Local-first Python transcription pipeline for long lecture batches.

## What It Does

ULTRANSC processes local media files and URL jobs from a filesystem queue, converts audio with `ffmpeg`, transcribes with a local Whisper executable, and writes transcript outputs without sending media to a hosted transcription service.

- Transcribes local audio/video files from `queue/incoming/` with optional concurrency (`MAX_CONCURRENT_JOBS`)
- Downloads URL jobs from `queue/links.txt` with audio-first `yt-dlp` defaults
- Uses two-stage audio preprocessing for noisy speech
- Selects a local Whisper model automatically, with safe fallback behavior
- Retries transient `ffmpeg` and `whisper-cli` failures with exponential backoff
- Moves failed inputs into `queue/failed/`
- Preserves failed URL entries for rerun
- Produces `transcript.txt`, `transcript.srt`, `transcript.vtt`, `transcript.md`, `transcript.html`, `transcript.json`, and `segments.json`
- Supports continuous watch daemon mode (`--watch`), queue status dashboard (`--status`), and queue cleanup (`--clean`)
- Supports Discord and Slack completion/crash webhook notifications (`WEBHOOK_URL`)

## Implementation

The primary implementation is Python under `ultransc/`.

Compatibility shell launchers remain for existing users:

- `ultransc.sh` -> `python3 -m ultransc`
- `check-setup.sh` -> `python3 -m ultransc.check_setup`
- `setup.sh` -> `python3 -m ultransc.setup`
- `ice.sh` -> `python3 -m ultransc.ice`
- `legacy/transcribe.sh` -> `python3 -m ultransc.legacy_transcribe`

No pipeline, setup, validation, test, or helper logic lives in shell scripts.

## Requirements

- Python 3.9+
- `ffmpeg`
- `ffprobe`
- `whisper-cli`, `whisper-cpp`, or `whisper` from whisper.cpp
- Bash only if using the compatibility launchers

macOS:

```bash
brew install ffmpeg whisper-cpp
```

Ubuntu/Debian:

```bash
sudo apt update
sudo apt install -y ffmpeg curl build-essential cmake git
```

If `whisper-cli` is not available from your package manager, ULTRANSC can use a local executable at `bin/whisper-cli`.

## Setup

```bash
python3 -m ultransc.setup
```

The setup command creates runtime folders, installs or builds external tools where possible, downloads a default Whisper model when none exists, and runs validation.

For a read-only environment check:

```bash
python3 -m ultransc.check_setup
```

## Docker Quickstart

You can run ULTRANSC inside a container with all dependencies (`ffmpeg`, `yt-dlp`, and `whisper-cli`) pre-installed:

```bash
# Start background watch worker with docker compose
docker compose up -d

# Check status in container
docker compose exec ultransc python -m ultransc --status
```

Any files placed in `./queue/incoming/` or links added to `./queue/links.txt` on the host machine will automatically be processed, and transcripts will appear in `./workspace/`.

## Quick Start

1. Put media files in `queue/incoming/`.
2. Optionally add URLs to `queue/links.txt`, one per line.
3. Run:

```bash
# Standard batch processing
python3 -m ultransc

# Continuous watch / daemon mode
python3 -m ultransc --watch

# Check queue status dashboard
python3 -m ultransc --status

# Clean finished queue files
python3 -m ultransc --clean done

# Custom model, language, and concurrency
python3 -m ultransc --model ggml-large-v3.bin --language tr --concurrency 2
```

4. Read outputs in `workspace/`.

Each completed job creates:

```text
workspace/<clean_name>_<timestamp>_<random>/
```

with:

- `raw_input`
- `transcript.txt`
- `transcript.srt`
- `transcript.vtt`
- `transcript.md` (timestamped markdown lecture notes)
- `transcript.html` (interactive browser reader with search)
- `transcript.json`
- `segments.json`

## Queue Layout

- `queue/incoming/`: new local files
- `queue/processing/`: active files
- `queue/done/`: completed source files
- `queue/failed/`: failed inputs
- `queue/links.txt`: pending URL jobs

Runtime queue contents, logs, downloaded tools, models, and transcript workspaces are intentionally ignored by Git.

## Configuration

Edit `config/default.conf` to tune implemented behavior.

Important keys:

- `MODEL`
- `AUTO_DOWNLOAD_MODEL`
- `MODEL_BASE_URL`
- `MAX_DURATION`
- `MIN_FREE_DISK_MB`
- `TARGET_LOUDNESS`
- `LANGUAGE`
- `THREADS`
- `WHISPER_CMD`
- `PREFER_METAL`
- `FAST_MODE`
- `WHISPER_SPEED_PRESET`
- `WHISPER_ARGS`
- `FFMPEG_THREADS`
- `STAGE2_MAX_DURATION`
- `MAX_CONCURRENT_JOBS`
- `WEBHOOK_URL`
- `YTDLP_FORMAT`
- `YTDLP_EXTRA_ARGS`
- `YTDLP_MAX_FILESIZE`
- `ENABLE_CRASH_RECOVERY`
- `AUTO_CLEANUP_TEMP`
- `RUN_PREFLIGHT`
- `MAX_RETRIES`
- `RETRY_BACKOFF_BASE`
- `RETRY_BACKOFF_MULTIPLIER`

The config parser accepts shell-style assignment lines, comments, and quoted values:

```bash
TARGET_LOUDNESS="-18"
WHISPER_ARGS='--prompt "course lecture"'
```

URL defaults are intentionally conservative:

- `YTDLP_FORMAT=bestaudio` avoids large video fallbacks.
- `YTDLP_EXTRA_ARGS=--extractor-args youtube:skip=dash` works around known DASH parser failures on some environments.
- Failed URLs remain in `queue/links.txt`.
- `YTDLP_MAX_FILESIZE` can cap accidental large downloads, for example `500M`.

## Reliability

- Single-instance lock prevents concurrent queue mutation.
- Stale locks are detected by PID.
- Interrupted files in `queue/processing/` return to `queue/incoming/`.
- Metadata and partial download artifacts are ignored and cleaned.
- URL queue interruption preserves the current and remaining URLs.
- `ffmpeg` and Whisper stages run through a bounded retry wrapper.
- Transcript sidecars are validated before a job is marked complete.

## Tests

```bash
python3 tests/run.py
```

The suite compiles the package, runs unit tests, and checks shell wrapper syntax. Tests use temporary roots and fake external binaries so they do not touch production queues or require real media processing. A minimal generated-audio smoke test exercises real `ffmpeg`/`ffprobe` when they are available and skips otherwise.

Preflight is opt-in for normal transcription runs:

```bash
python3 -m ultransc.preflight
ULTRANSC_RUN_PREFLIGHT=1 python3 -m ultransc
```

## Code Structure

- `ultransc/core.py`: pipeline orchestration, queue handling, model selection, audio conversion, Whisper invocation
- `ultransc/check_setup.py`: setup validator
- `ultransc/setup.py`: bootstrap/install flow
- `ultransc/ice.py`: transcript snippet helper
- `ultransc/legacy_transcribe.py`: Python version of the old one-shot URL helper
- `tests/`: Python tests and compatibility launcher checks

## Design Notes

ULTRANSC is intentionally file-queue based instead of service-first. That keeps media local, makes interrupted work inspectable, and allows long lecture batches to be resumed without a database. The tradeoff is that queue directories and runtime logs are operational state, so they are ignored rather than committed.

The Python port keeps external command calls as argument lists instead of shell strings. This makes `ffmpeg`, `yt-dlp`, and Whisper integration easier to test and avoids shell interpolation hazards from filenames, URLs, and user-provided config values.

## Companion Utility

`ice` extracts transcript snippets around matching keywords:

```bash
python3 -m ultransc.ice <lecture-pattern...> -- "keyword1" "keyword2"
```

It scans matching transcripts and saves curated snippets in `blocks/`.

## Contributing

Contributions are very welcome! Please read our [Contributing Guide](CONTRIBUTING.md) and [Code of Conduct](CODE_OF_CONDUCT.md) to get started.

## License

MIT. See `LICENSE`.

