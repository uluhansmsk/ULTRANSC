# Migration Guide: v0.3.3 → v0.5

This guide helps you upgrade from ULTRANSC v0.3.3 to v0.5 safely.

---

## ⚠️ Before You Start

### Backup Your Data

```bash
# Backup existing workspace
cp -r workspace workspace.backup

# Backup old script
cp ultransc.sh ultransc.sh.v0.3.3
```

### What's Changed

- **Configuration system**: New `config/default.conf` replaces hardcoded settings
- **Queue behavior**: No longer accepts command-line file arguments
- **Processing logic**: Jobs now resume instead of being deleted on crash
- **Audio pipeline**: Completely rewritten with loudnorm
- **Output structure**: New per-job logging and state files

---

## 📋 Migration Checklist

### ✅ Step 1: Pull Latest Code

```bash
cd /path/to/ultransc
git pull origin main
# or: git fetch && git checkout v0.5
```

### ✅ Step 2: Review Configuration

```bash
# Copy default config if needed
cp config/default.conf config/my-config.conf

# Edit with your preferences
nano config/default.conf
```

**Key settings to review:**

- `MODEL`: Was `DEFAULT_MODEL`, now supports `auto`
- `MAX_DURATION`: Default 10800s (3 hours)
- `CHUNK_MINUTES`: New feature, default 15
- `ENABLE_CRASH_RECOVERY`: New feature, default true

### ✅ Step 3: Verify Dependencies

```bash
# Check required tools
command -v ffmpeg && echo "✓ ffmpeg"
command -v whisper-cli && echo "✓ whisper-cli"
command -v curl && echo "✓ curl"

# Check models
ls -lh models/*.bin
```

### ✅ Step 4: Update Queue Structure

```bash
# Ensure queue directories exist
mkdir -p queue/incoming queue/processing queue/done

# Move any pending files
# (Old v0.3.3 might have files in different locations)
# mv /old/location/*.mp4 queue/incoming/
```

### ✅ Step 5: Clean Old Incomplete Jobs (Optional)

```bash
# v0.5 will try to resume these, but you can clean if desired
find workspace/ -type d -mindepth 1 -maxdepth 1 | while read job; do
    if [ ! -f "$job/transcript.txt" ]; then
        echo "Incomplete: $job"
        # Uncomment to delete:
        # rm -rf "$job"
    fi
done
```

### ✅ Step 6: Test Run

```bash
# Create a small test file
echo "Test" | say -o test.aiff  # macOS
# or: espeak "Test" -w test.wav  # Linux

# Convert to compatible format
ffmpeg -i test.aiff -ar 16000 queue/incoming/test.wav -y

# Run ULTRANSC
./ultransc.sh

# Check output
ls -la workspace/test_*/
cat workspace/test_*/job.log
```

---

## 🔄 What Changed & How to Adapt

### Command-Line Interface

**OLD (v0.3.3):**

```bash
./ultransc.sh my_file.mp4
./ultransc.sh https://youtube.com/watch?v=xxx
```

**NEW (v0.5):**

```bash
# For files
cp my_file.mp4 queue/incoming/
./ultransc.sh

# For URLs
echo "https://youtube.com/watch?v=xxx" >> queue/links.txt
./ultransc.sh
```

### Model Selection

**OLD (v0.3.3):**

```bash
# Hardcoded in script
DEFAULT_MODEL="ggml-medium.en.bin"
```

**NEW (v0.5):**

```bash
# In config/default.conf
MODEL=auto                      # Intelligent selection
# or
MODEL=ggml-medium.en.bin        # Force specific model
```

### Audio Processing

**OLD (v0.3.3):**

- Two-stage adaptive boost
- Mean volume detection
- Blank ratio threshold
- Manual gain calculation

**NEW (v0.5):**

- Unified loudnorm pipeline
- FFmpeg-based normalization
- Configurable filters
- No manual intervention needed

**What to do:** Audio should sound better automatically. If not:

```bash
# Tune in config/default.conf
TARGET_LOUDNESS=-18    # Try -16 to -20
HIGHPASS_FREQ=150      # Try 100-200
LOWPASS_FREQ=3800      # Try 3500-4000
```

### Job Management

**OLD (v0.3.3):**

- Incomplete jobs deleted on restart
- No state tracking
- No resume capability

**NEW (v0.5):**

- Jobs resume automatically
- State files track progress
- Crash-proof by design

**What to do:** Nothing! Jobs will resume. To disable:

```bash
ENABLE_CRASH_RECOVERY=false
```

### Long Files

**OLD (v0.3.3):**

- Processed as single file
- Could cause memory issues
- 3-hour limit enforced

**NEW (v0.5):**

- Automatic chunking
- Seamless stitching
- No practical limit

**What to do:** Enable for long files:

```bash
ENABLE_CHUNKING=true
CHUNK_MINUTES=15    # Adjust based on RAM
```

### Logging

**OLD (v0.3.3):**

- Single system log
- Single error log
- No per-job logs

**NEW (v0.5):**

- System log: `logs/system.log`
- Error log: `logs/errors.log`
- Per-job log: `workspace/*/job.log`
- Debug mode: `LOG_LEVEL=debug`

**What to do:** Check new log locations:

```bash
tail -f logs/system.log
tail -f workspace/latest_job/job.log
```

---

## 🚨 Breaking Changes

### 1. No Command-Line File Arguments

**Impact:** HIGH  
**Solution:** Use queue system

```bash
# Old way (no longer works)
./ultransc.sh file.mp4

# New way
cp file.mp4 queue/incoming/ && ./ultransc.sh
```

### 2. Configuration File Required

**Impact:** LOW  
**Solution:** File created automatically with defaults

```bash
# Will be auto-created on first run
ls config/default.conf
```

### 3. Different Output Structure

**Impact:** MEDIUM  
**Solution:** Expect new files in job directories

```
workspace/job_name_timestamp/
├── transcript.txt      # Same as before
├── transcript.json     # Same as before
├── transcript.srt      # Same as before
├── segments.json       # NEW: Symlink to JSON
├── job.log             # NEW: Per-job log
├── .state              # NEW: State tracking
└── raw_input           # Same as before
```

### 4. Model JSON Format Changed

**Impact:** LOW  
**Solution:** Will be regenerated automatically

**OLD:**

```json
{ "installed": { "model.bin": true }, "default": "model.bin" }
```

**NEW:**

```json
{
  "scanned": "2026-01-07T12:00:00Z",
  "models": {
    "model.bin": { "size": "1.5G", "usable": true }
  },
  "default": "model.bin"
}
```

---

## 🎯 Feature Mapping

| v0.3.3 Feature       | v0.5 Equivalent     | Notes                |
| -------------------- | ------------------- | -------------------- |
| Two-stage processing | Unified loudnorm    | Better quality       |
| Blank detection      | Removed             | Not needed           |
| Simple retry         | Exponential backoff | `MAX_RETRIES=3`      |
| RAM check            | Memory backpressure | `MIN_FREE_RAM_GB=2`  |
| Model auto-select    | Smart selection     | `MODEL=auto`         |
| Queue processing     | Priority system     | `PRIORITY_ORDER=...` |

---

## 📊 Configuration Comparison

### v0.3.3 (Hardcoded)

```bash
DEFAULT_MODEL="ggml-medium.en.bin"
MAX_DURATION=10800
HIGHPASS=120
LOWPASS=3800
```

### v0.5 (config/default.conf)

```bash
MODEL=auto
MODEL_FALLBACK=ggml-small.en.bin
MAX_DURATION=10800
CHUNK_MINUTES=15
MIN_FREE_DISK_MB=500
MIN_FREE_RAM_GB=2
ENABLE_BACKPRESSURE=true
MAX_SWAP_GB=5
AUDIO_NORMALIZATION=true
HIGHPASS_FREQ=150
LOWPASS_FREQ=3800
SILENCE_TRIMMING=false
TARGET_LOUDNESS=-18
THREADS=auto
PREFER_METAL=true
LANGUAGE=en
ENABLE_CRASH_RECOVERY=true
ENABLE_CHUNKING=true
COMPRESS_RAW_INPUT=false
AUTO_CLEANUP_TEMP=true
LOG_LEVEL=info
PER_JOB_LOGGING=true
PRIORITY_ORDER=local,incoming,urls
MAX_RETRIES=3
RETRY_BACKOFF_BASE=5
RETRY_BACKOFF_MULTIPLIER=2
```

**Migration tip:** Start with defaults, tune later based on logs.

---

## 🐛 Known Issues & Workarounds

### Issue: "bc: command not found"

**Cause:** Used for arithmetic in memory checks  
**Solution:** Install bc or use integer-only math

```bash
# macOS
brew install bc

# Linux
sudo apt install bc
```

### Issue: Old jobs show as incomplete

**Cause:** No .state file from v0.3.3  
**Solution:** They'll be detected as complete if transcript.txt exists

### Issue: Audio sounds different

**Cause:** New normalization pipeline  
**Solution:** This is expected and should be better

If quality decreased:

```bash
AUDIO_NORMALIZATION=false  # Disable new pipeline
```

---

## 🎓 Learning the New Features

### Try Chunking

```bash
# Get a 2-hour video
echo "https://youtube.com/watch?v=long-lecture" >> queue/links.txt

# Enable chunking
# (already on by default)
./ultransc.sh

# Check chunk logs
cat workspace/long-lecture_*/job.log | grep chunk
```

### Test Crash Recovery

```bash
# Start a job
cp big_file.mp4 queue/incoming/
./ultransc.sh &

# Kill it mid-process
sleep 60 && kill %1

# Resume
./ultransc.sh
# Should continue from last stage
```

### Monitor Memory

```bash
# Enable debug logging
# In config: LOG_LEVEL=debug

# Run and watch
./ultransc.sh &
tail -f logs/system.log | grep -E "RAM|SWAP|Memory"
```

---

## 🆘 Rollback Procedure

If v0.5 doesn't work for you:

```bash
# 1. Restore old script
mv ultransc.sh ultransc.sh.v0.5
mv ultransc.sh.v0.3.3 ultransc.sh

# 2. Restore workspace if needed
rm -rf workspace
mv workspace.backup workspace

# 3. Continue using v0.3.3
./ultransc.sh file.mp4
```

**Report issues:** Open a GitHub issue with logs so we can fix v0.5.

---

## ✅ Post-Migration Checklist

- [ ] Config file created and reviewed
- [ ] Test run completed successfully
- [ ] Logs are being written
- [ ] Models validated and working
- [ ] Queue system tested (incoming/ and links.txt)
- [ ] Long file chunking tested (optional)
- [ ] Crash recovery tested (optional)
- [ ] Old backup removed (after confirming v0.5 works)

---

## 📚 Additional Resources

- **Full documentation**: `README.md`
- **Quick reference**: `QUICKSTART.md`
- **All changes**: `CHANGELOG.md`
- **Configuration help**: `config/default.conf` (inline comments)

---

**Welcome to v0.5!** You now have a production-grade, crash-proof transcription pipeline. 🎉
