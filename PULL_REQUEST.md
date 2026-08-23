# PR Title
`feat: complete Python architecture, concurrency, Docker support, rich exports, and community standards (v0.8.0)`

---

# PR Description

## 📌 Summary of Changes

This pull request delivers a major modernization of ULTRANSC (v0.8.0), transitioning the legacy shell codebase into a robust, cross-platform, modular Python architecture, while introducing enterprise-grade batch transcription features, zero-setup Docker containerization, and comprehensive open-source community standards.

---

## 🚀 Key Features & Enhancements

### 1. Modular Core Architecture (`ultransc/`)
- Decoupled pipeline logic into distinct, single-responsibility modules:
  - `core.py`: Pipeline orchestration, lifecycle hooks, lock management.
  - `transcriber.py`: `whisper-cli` detection, argument builder, and execution.
  - `media.py`: FFmpeg/ffprobe audio analysis, volume detection, and two-stage conversion.
  - `models.py`: Whisper model resolution, chunked downloading with real-time percentage/MB progress reporting.
  - `queue_manager.py`: Interrupted job recovery, queue state management, and robust `yt-dlp` audio downloading.
  - `export.py`: Multi-format transcript generation.
  - `utils.py`: Cross-platform utilities, safe file operations, and notification dispatcher.

### 2. Parallel / Concurrent Queue Processing
- Added `MAX_CONCURRENT_JOBS` support in `config/default.conf` and `ultransc/config.py`.
- Integrated `ThreadPoolExecutor` in `process_incoming_queue()` to process multiple media files simultaneously on multi-core workstations and servers.

### 3. Rich Transcript Output Formats
Each completed job in `workspace/<job_id>/` now produces:
- `transcript.txt`: Raw plain text.
- `transcript.srt`: SubRip subtitle file.
- `transcript.vtt`: WebVTT subtitle file for modern web players.
- `transcript.md`: Formatted, timestamped (`[00:01:23]`) Markdown lecture notes with timeline.
- `transcript.html`: A self-contained, standalone interactive HTML reader with live search filtering, timestamp badges, and clipboard copy functionality.
- `transcript.json` & `segments.json`: Structured segment metadata.

### 4. Advanced CLI & Queue Management
Enhanced `ultransc` CLI with powerful administrative controls:
- **Continuous Watch / Daemon Mode (`-w`, `--watch`, `--interval <N>`)**: Actively polls `queue/incoming/` and `queue/links.txt` and automatically triggers transcription when new media arrives.
- **Queue Status Dashboard (`--status`)**: Displays a formatted overview of queue counts (`incoming`, `processing`, `done`, `failed`, `links`), remaining disk space, and installed models.
- **Queue Cleanup (`--clean [done|failed|all]`)**: Cleans up finished or failed files with one command.
- **Dynamic Config Overrides**: Override `--model`, `--language` (`--lang`), `--concurrency` (`-c`), `--webhook`, and `--fast` directly from the command line without editing config files.

### 5. Webhook Notifications
- Integrated `WEBHOOK_URL` in `config/default.conf` compatible with both Discord and Slack JSON payloads.
- Sends automatic completion summaries and crash alert notifications to team channels.

### 6. Containerization (Docker & Docker Compose)
- **`Dockerfile`**: Multi-stage lightweight Debian container with `ffmpeg`, `yt-dlp`, and compiled `whisper.cpp` (`whisper-cli`) ready out of the box.
- **`docker-compose.yml`**: Volume-mounted setup for `./queue`, `./workspace`, `./models`, and `./config` for zero-install deployment.
- **`.dockerignore`**: Optimized build context.

### 7. Open Source & Community Standards
- **`CONTRIBUTING.md`**: Guide for new contributors covering environment setup, Ruff linting, test suite execution, and Conventional Commits.
- **`CODE_OF_CONDUCT.md`**: Contributor Covenant v2.1 standard.
- **`SECURITY.md`**: Vulnerability disclosure policy.
- **`.github/ISSUE_TEMPLATE/`**: Form-based templates for Bug Reports, Feature Requests, and Discussions.
- **`.github/PULL_REQUEST_TEMPLATE.md`**: PR checklist and guidelines.
- **`README.md` Badges**: CI status, License (MIT), Python (3.9+), Docker Ready, PRs Welcome.

### 8. Cross-Platform Unit Test Suite
- Comprehensive test coverage in `tests/test_python_port.py` with mock binaries (`ffprobe`, `ffmpeg`, `whisper-cli`, `yt-dlp`).
- Windows-compatible test execution using `.bat` wrappers and cross-platform path handling.
- Safe shell syntax checking in `tests/run.py` that gracefully detects bash availability.

---

## 🧪 Testing & Verification

- [x] All unit tests pass (`python tests/run.py` / `python -m unittest discover tests`).
- [x] Python compilation checks pass (`compileall`).
- [x] Tested Markdown (`.md`) and HTML (`.html`) generation from Whisper outputs.
- [x] Tested CLI flags (`--status`, `--clean`, `--watch`, `--model`, `--lang`, `--concurrency`).
- [x] Verified backward compatibility with existing `ultransc.sh`, `check-setup.sh`, and `setup.sh` launchers.

---

## 🔄 Backward Compatibility
- 100% backward compatible with existing shell launchers (`ultransc.sh`, `setup.sh`, `check-setup.sh`, `ice.sh`).
- Existing configuration files in `config/default.conf` are fully preserved with safe defaults.
