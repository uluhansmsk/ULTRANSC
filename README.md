# ULTRANSC

Local-first transcription pipeline for long lecture batches.

## Status

Version: v0.7.0-beta1
Release date: 2026-04-15
State: Beta (modular refactor), macOS and Linux supported

## What It Does

- Transcribes local audio/video files and URLs
- Uses adaptive two-stage audio preprocessing for noisy speech
- Selects models automatically, with safe fallback behavior
- Processes jobs through queue folders
- Retries transient failures with exponential backoff
- Isolates failed inputs into a dedicated failed queue
- Preserves failed URL entries for rerun
- Produces transcript.txt, transcript.srt, transcript.json, and segments.json

## Requirements

- bash
- ffmpeg
- ffprobe
- whisper-cli (whisper.cpp)
- curl

macOS install:

```bash
brew install ffmpeg whisper-cpp
```

Linux quick install (Ubuntu/Debian):

```bash
sudo apt update
sudo apt install -y ffmpeg curl build-essential cmake git
```

If whisper-cli is not available from your distro package manager, ULTRANSC can use a local binary in bin/whisper-cli.

yt-dlp is downloaded automatically into bin/ on first run.

## Out-Of-Box Setup

Run the bootstrap script once:

```bash
chmod +x setup.sh
./setup.sh
```

It will:

- Create required queue/workspace/log/model folders
- Install core dependencies (best effort per OS)
- Build local whisper.cpp binary when needed (Linux)
- Download the default model if none is present
- Run check-setup.sh at the end

## Quick Start

1. Put files in queue/incoming/.
2. Optionally add URLs to queue/links.txt, one per line.
3. Run:

```bash
./ultransc.sh
```

4. Check outputs in workspace/.

## Queue Layout

- queue/incoming: new local files
- queue/processing: currently active files
- queue/done: completed source files
- queue/failed: inputs that failed processing
- queue/links.txt: pending URL jobs

## Outputs Per Job

Each job creates:

- raw_input
- transcript.txt
- transcript.srt
- transcript.json
- segments.json

Path format:

```text
workspace/<clean_name>_<timestamp>_<random>/
```

## Reliability And Performance Features In v0.7.0

- Single-instance lock to prevent concurrent queue corruption
- Crash recovery for queue/processing back to queue/incoming
- Retry wrapper for ffmpeg and whisper-cli stages
- Config-driven processing limits and retry behavior
- Validation checks for duration parsing and required outputs
- Optional cleanup of temporary WAV files
- Linux-friendly whisper command auto-detection (system or local bin/)
- Optional automatic model bootstrap when models/ is empty
- Linux setup builds whisper-cli without shared lib dependency
- Fast mode to skip Stage 2 for speed (auto default is off on macOS)
- Whisper speed presets (fast, balanced, quality)
- Thread auto-detection for whisper and ffmpeg
- Metal acceleration on macOS when available
- Auto-detects --metal support and falls back to CPU if unsupported
- Safe handling when WHISPER_ARGS is empty under strict shell mode
- Safe handling when metal args are omitted under strict shell mode

## Configuration

Edit config/default.conf to tune behavior.

Important keys:

- MODEL
- MAX_DURATION
- MIN_FREE_DISK_MB
- TARGET_LOUDNESS
- LANGUAGE
- THREADS
- WHISPER_CMD
- FAST_MODE
- WHISPER_SPEED_PRESET
- WHISPER_ARGS
- FFMPEG_THREADS
- STAGE2_MAX_DURATION
- ENABLE_CRASH_RECOVERY
- AUTO_CLEANUP_TEMP
- AUTO_DOWNLOAD_MODEL
- MODEL_BASE_URL
- MAX_RETRIES
- RETRY_BACKOFF_BASE
- RETRY_BACKOFF_MULTIPLIER

Linux note:

- Set WHISPER_CMD to an explicit executable if needed (for example bin/whisper-cli).

## Operational Guidance For Large Batches

- Keep at least 20GB free disk recommended for 50+ lectures
- Run only one ultransc.sh instance at a time
- Monitor logs/system.log and logs/errors.log during runs
- Reprocess queue/failed items after fixing root causes

## Dual-Machine Workflow (macOS + Linux)

- Keep the same repo layout on both machines.
- Feed each machine with a separate input subset in queue/incoming/.
- Use distinct links.txt lists per machine for URL jobs.
- Merge final transcripts from each machine's workspace/ directory.

## Setup Validation

Run:

```bash
bash check-setup.sh
```

This validates tools, folders, model presence, permissions, and resource warnings.

## Tests

Run the lightweight test suite:

```bash
bash tests/run.sh
```

These tests avoid touching production queues or large files.

## Beta Notes

- See BETA_CHANGELOG.md for beta-only notes.
- See TODO_BETA.md for temporary TODOs to remove after beta.

## Code Structure

- ultransc.sh is the entry point
- lib/ contains modular shell components (env, model, whisper, audio, jobs, queue)

## Companion Utility

Keyword extraction helper:

```bash
./ice.sh <lecture-pattern...> -- "keyword1" "keyword2"
```

It scans matching transcripts and saves curated snippets in blocks/.

## License

No license file is currently included in this repository.
