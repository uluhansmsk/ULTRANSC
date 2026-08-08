# Tests

These tests are lightweight and safe. They do not execute real media processing.

Run:

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
- Shell wrapper syntax for compatibility scripts
