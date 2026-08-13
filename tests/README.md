# Tests

These tests are lightweight and safe. They do not touch production queues or execute real media processing.

Run:

```bash
python3 tests/run.py
```

Compatibility wrapper:

```bash
bash tests/run.sh
```

Preflight (auto-fix on failure):

```bash
bash tests/preflight.sh
```

What it checks:

- Python compilation checks
- Python pipeline behavior with fake ffmpeg, ffprobe, whisper-cli, and yt-dlp
- Shell-style config parsing
- Required transcript sidecar validation
- Stage 2 retry path when Stage 1 contains too much blank audio
- URL queue retry and interrupt recovery
- Single-instance lock behavior
- CLI preflight flag parsing
- Minimal generated-audio smoke coverage with real ffmpeg/ffprobe when available
- Regex matching in the ice helper
- Shell wrapper syntax for compatibility scripts
