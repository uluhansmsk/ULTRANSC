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
- Regex matching in the ice helper
- Shell wrapper syntax for compatibility scripts
