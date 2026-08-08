# ULTRANSC

Local-first Python transcription pipeline for long lecture batches.

## Status

Version: v0.7.0-beta1
Release date: 2026-04-15
State: Beta Python refactor, macOS and Linux supported

## What It Does

- Transcribes local audio/video files and URLs
- Uses adaptive two-stage audio preprocessing for noisy speech
- Selects Whisper models automatically, with safe fallback behavior
- Processes jobs through queue folders
- Retries transient ffmpeg and whisper-cli failures with exponential backoff
- Isolates failed inputs into queue/failed
- Preserves failed URL entries in queue/links.txt for rerun
- Produces transcript.txt, transcript.srt, transcript.json, and segments.json

## Implementation

ULTRANSC is implemented in Python under ultransc/.

The .sh files are compatibility launchers only:

- ultransc.sh -> python3 -m ultransc
- check-setup.sh -> python3 -m ultransc.check_setup
- setup.sh -> python3 -m ultransc.setup
- ice.sh -> python3 -m ultransc.ice
- tests/*.sh -> Python test/preflight modules
- legacy/transcribe.sh -> python3 -m ultransc.legacy_transcribe

No pipeline, setup, check, test, or helper logic lives in shell scripts in this branch.

## Requirements

- Python 3.9+
- ffmpeg
- ffprobe
- whisper-cli, whisper-cpp, or whisper from whisper.cpp
- bash only if using the compatibility .sh launchers

macOS install:

```bash
brew install ffmpeg whisper-cpp
```

Linux quick install (Ubuntu/Debian):

```bash
sudo apt update
sudo apt install -y ffmpeg curl build-essential cmake git
```

If whisper-cli is not available from your package manager, ULTRANSC can use a local binary in bin/whisper-cli.

yt-dlp is downloaded automatically into bin/ on first run when missing.

## Out-Of-Box Setup

Run the Python setup command:

```bash
python3 -m ultransc.setup
```

Compatibility wrapper:

```bash
./setup.sh
```

Setup will:

- Create required queue/workspace/log/model folders
- Install core dependencies best-effort per OS
- Build local whisper.cpp binary when needed on Linux
- Download the default model if none is present
- Run Python preflight and check-setup validation

## Quick Start

1. Put files in queue/incoming/.
2. Optionally add URLs to queue/links.txt, one per line.
3. Run:

```bash
python3 -m ultransc
```

Compatibility wrapper:

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

Each completed job creates:

- raw_input
- transcript.txt
- transcript.srt
- transcript.json
- segments.json

Path format:

```text
workspace/<clean_name>_<timestamp>_<random>/
```

## Reliability And Performance Features

- Single-instance lock to prevent concurrent queue corruption
- Crash recovery for queue/processing back to queue/incoming
- Retry wrapper for ffmpeg and whisper-cli stages
- Shell-style config parsing for existing config/default.conf compatibility
- Validation checks for duration parsing and required transcript sidecar outputs
- Optional cleanup of temporary WAV files
- Linux-friendly whisper command auto-detection from system PATH or bin/
- Optional automatic model bootstrap when models/ is empty
- Fast mode to skip Stage 2 for speed (auto default is off on macOS)
- Whisper speed presets: fast, balanced, quality
- Thread auto-detection for whisper and ffmpeg
- Metal acceleration on macOS when supported by the detected whisper binary

## Configuration

Edit config/default.conf to tune behavior.

The parser accepts shell-style assignment lines, including comments and quoted values:

```bash
TARGET_LOUDNESS="-18"
WHISPER_ARGS='--prompt "course lecture"'
```

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

- Set WHISPER_CMD to an explicit executable if needed, for example bin/whisper-cli.

## Operational Guidance For Large Batches

- Keep at least 20GB free disk recommended for 50+ lectures
- Run only one ULTRANSC instance at a time
- Monitor logs/system.log and logs/errors.log during runs
- Reprocess queue/failed items after fixing root causes

## Dual-Machine Workflow

- Keep the same repo layout on both machines.
- Feed each machine with a separate input subset in queue/incoming/.
- Use distinct links.txt lists per machine for URL jobs.
- Merge final transcripts from each machine's workspace/ directory.

## Setup Validation

Run:

```bash
python3 -m ultransc.check_setup
```

Compatibility wrapper:

```bash
./check-setup.sh
```

This validates Python files, external tools, folders, model presence, permissions, and resource warnings.

## Tests

Run:

```bash
python3 tests/run.py
```

Compatibility wrapper:

```bash
bash tests/run.sh
```

The tests avoid production queues and real media processing. They use fake ffmpeg, ffprobe, whisper-cli, and yt-dlp binaries to verify queue behavior, output validation, config parsing, URL retries, and the ice helper.

## Code Structure

- ultransc/core.py: main pipeline, queue handling, model selection, audio conversion, whisper invocation
- ultransc/check_setup.py: setup validator
- ultransc/setup.py: bootstrap/install flow
- ultransc/ice.py: transcript snippet helper
- ultransc/preflight.py and ultransc/autofix.py: validation helpers
- ultransc/legacy_transcribe.py: Python version of the legacy one-shot URL helper
- tests/: Python tests and compatibility launchers

## Companion Utility

Keyword extraction helper:

```bash
python3 -m ultransc.ice <lecture-pattern...> -- "keyword1" "keyword2"
```

Compatibility wrapper:

```bash
./ice.sh <lecture-pattern...> -- "keyword1" "keyword2"
```

It scans matching transcripts and saves curated snippets in blocks/.

## License

No license file is currently included in this repository.
