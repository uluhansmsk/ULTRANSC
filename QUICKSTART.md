# ULTRANSC v0.5 Quick Reference

## 🚀 Quick Start

```bash
# 1. Add files to queue
cp lecture.mp4 queue/incoming/

# 2. Run transcription
./ultransc.sh

# 3. Find results
ls workspace/lecture_*/
```

---

## 📂 Directory Structure

```
ULTRANSC/
├── ultransc.sh          # Main script
├── config/
│   └── default.conf     # Configuration file
├── queue/
│   ├── incoming/        # Drop files here
│   ├── links.txt        # Add URLs here (one per line)
│   ├── processing/      # Currently processing
│   └── done/            # Completed files
├── workspace/           # Output directory
│   └── job_name_timestamp/
│       ├── transcript.txt
│       ├── transcript.json
│       ├── transcript.srt
│       ├── segments.json
│       ├── job.log
│       └── raw_input
├── models/              # Whisper models (.bin files)
├── logs/                # System logs
└── bin/                 # Auto-downloaded tools (yt-dlp)
```

---

## ⚙️ Essential Config Settings

Edit `config/default.conf`:

```bash
# Model Selection
MODEL=auto                      # auto | specific model name
CHUNK_MINUTES=15                # Split files > N minutes

# Memory Management
MIN_FREE_RAM_GB=2               # Wait if RAM below this
MAX_SWAP_GB=5                   # Abort if swap exceeds this

# Audio Quality
AUDIO_NORMALIZATION=true        # Enable loudness normalization
HIGHPASS_FREQ=150               # Remove low rumble
LOWPASS_FREQ=3800               # Remove high hiss

# Features
ENABLE_CHUNKING=true            # Split long files
ENABLE_CRASH_RECOVERY=true      # Resume incomplete jobs
AUTO_CLEANUP_TEMP=true          # Delete temp files after success

# Processing
THREADS=auto                    # CPU threads (auto = 75% of cores)
PRIORITY_ORDER=local,incoming,urls  # Processing order
```

---

## 📝 Common Tasks

### Process a YouTube URL

```bash
echo "https://www.youtube.com/watch?v=dQw4w9WgXcQ" >> queue/links.txt
./ultransc.sh
```

### Process Multiple Files

```bash
cp *.mp4 queue/incoming/
./ultransc.sh
```

### Resume Failed Jobs

Jobs automatically resume on next run if `ENABLE_CRASH_RECOVERY=true`

### Check Processing Status

```bash
# View system log
tail -f logs/system.log

# View specific job log
tail -f workspace/my_lecture_20260107_143052/job.log
```

### Clean Old Jobs

```bash
# Remove completed jobs older than 30 days
find workspace/ -type d -mtime +30 -exec rm -rf {} \;
```

---

## 🔧 Troubleshooting

### "No valid models found"

```bash
# Download a model
curl -L https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin \
     -o models/ggml-medium.en.bin
```

### "Insufficient disk space"

```bash
# Enable auto-cleanup in config
AUTO_CLEANUP_TEMP=true
COMPRESS_RAW_INPUT=true

# Or manually clean temp files
find workspace/ -name "audio.wav" -delete
find workspace/ -name "chunks" -type d -exec rm -rf {} \;
```

### "Swap usage exceeds limit"

```bash
# Increase limit or enable chunking for shorter segments
MAX_SWAP_GB=10
CHUNK_MINUTES=10
```

### "Job keeps failing"

```bash
# Check job log
cat workspace/job_name_timestamp/job.log

# Increase retry attempts
MAX_RETRIES=5

# Try smaller model
MODEL=ggml-small.en.bin
```

### "Transcription quality is poor"

```bash
# Enable all audio enhancements
AUDIO_NORMALIZATION=true
HIGHPASS_FREQ=150
LOWPASS_FREQ=3800
TARGET_LOUDNESS=-18

# Try larger model
MODEL=ggml-medium.en.bin
```

---

## 📊 Output Files Explained

| File              | Description                                       |
| ----------------- | ------------------------------------------------- |
| `transcript.txt`  | Plain text transcript (newline-separated)         |
| `transcript.json` | Full JSON with timestamps, confidence scores      |
| `transcript.srt`  | Subtitle format (timecoded)                       |
| `segments.json`   | Symlink to JSON (for `ice.sh` keyword extraction) |
| `job.log`         | Processing log with metrics and errors            |
| `raw_input`       | Original file (or `.gz` if compressed)            |
| `.state`          | Internal state file (for crash recovery)          |

---

## 🎯 Performance Tuning

### For Speed

```bash
MODEL=ggml-small.en.bin     # Faster, less accurate
AUDIO_NORMALIZATION=false   # Skip normalization
ENABLE_CHUNKING=false       # No splitting (if file < 3h)
THREADS=auto                # Use all cores
```

### For Quality

```bash
MODEL=ggml-medium.en.bin    # Slower, more accurate
AUDIO_NORMALIZATION=true    # Full preprocessing
CHUNK_MINUTES=20            # Longer chunks (more context)
```

### For Stability (Overnight Batches)

```bash
ENABLE_BACKPRESSURE=true    # Wait for memory
MIN_FREE_RAM_GB=3           # Higher threshold
MAX_SWAP_GB=3               # Lower swap limit
ENABLE_CRASH_RECOVERY=true  # Resume on restart
AUTO_CLEANUP_TEMP=true      # Save disk space
MAX_RETRIES=3               # Retry failures
```

---

## 🔗 Integration with ice.sh

Extract keyword snippets from transcripts:

```bash
# Find all mentions of "neural network" in lecture 5
./ice.sh math lezione 5 -- "neural network"

# Multiple keywords
./ice.sh cs lecture 10 -- "algorithm" "complexity" "optimization"

# Output in blocks/
ls blocks/cs_lecture_10*.txt
```

---

## 🐛 Debug Mode

Enable verbose logging:

```bash
# In config/default.conf
LOG_LEVEL=debug

# Then run
./ultransc.sh

# Check detailed logs
tail -f logs/system.log
```

---

## 💡 Tips & Best Practices

1. **Use chunking for long files**: Anything over 1 hour benefits from `CHUNK_MINUTES=15`
2. **Monitor first run**: Watch `logs/system.log` to ensure everything works
3. **Start with small model**: Test with `ggml-small.en.bin` before downloading larger models
4. **Enable crash recovery**: Always keep `ENABLE_CRASH_RECOVERY=true` for overnight batches
5. **Clean old jobs regularly**: Old workspace folders accumulate; clean monthly
6. **Check audio quality first**: Bad audio → bad transcription, no model can fix it
7. **Use priority order**: Process quick local files before long URL downloads
8. **Keep raw_input**: Disable compression until you're sure transcripts are good

---

## 📈 Monitoring

### Check Resource Usage

```bash
# During processing
top  # or htop

# Check ULTRANSC resource usage
ps aux | grep ultransc
```

### Logs to Watch

```bash
# System activity
tail -f logs/system.log

# Errors only
tail -f logs/errors.log

# Current job
tail -f workspace/$(ls -t workspace/ | head -1)/job.log
```

---

## 🔒 Privacy & Security

- **100% local**: No data leaves your machine
- **No telemetry**: Zero tracking or analytics
- **No accounts**: No sign-ups, tokens, or keys
- **Offline capable**: Works without internet (after initial yt-dlp download)
- **Full control**: All data in your `workspace/` directory

---

## 📚 Further Reading

- Full documentation: `README.md`
- Changelog: `CHANGELOG.md`
- Configuration reference: `config/default.conf` (inline comments)
- Architecture: See source code comments in `ultransc.sh`

---

**Questions?** Open an issue on GitHub or check the logs — they're detailed for a reason.
