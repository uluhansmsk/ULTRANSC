# ULTRANSC

Local-first transcription pipeline for humans who got tired of SaaS paywalls, API keys, and "premium features".  
Feed it a link or a file. It downloads the media, extracts audio, transcribes it with Whisper, and stores everything in a clean structure.  
No accounts. No cloud. No bullshit.

---

## Status

**Current Version: v0.5** — Production-ready intelligent pipeline

> URL → yt-dlp → ffmpeg (loudnorm) → whisper.cpp (chunked) → transcript (.txt, .srt, .json)

**New in v0.5:**
- ✅ Intelligent file chunking for 3+ hour recordings
- ✅ Crash recovery and job resumption
- ✅ Memory-aware backpressure system
- ✅ Advanced audio normalization (loudnorm + dynamic filtering)
- ✅ Smart model selection based on duration and RAM
- ✅ Per-job logging and metrics
- ✅ Configurable pipeline via config/default.conf
- ✅ Priority-based queue processing
- ✅ Automatic retry with exponential backoff
- ✅ Model corruption detection and validation

**Stability:** Can transcribe 20+ lecture recordings overnight without crashes or data loss.

---

## Philosophy

- **Local-first**
- **Crash-proof and resumable**
- **Memory-safe (no swap explosions)**
- **Configurable, not rigid**
- **Modular and swappable components**
- **Works offline**
- **No forced cloud dependencies**

If something breaks upstream, ULTRANSC can switch modules, versions, or providers.  
If your system has tools installed, ULTRANSC can use them.  
Jobs never get lost — incomplete transcriptions resume automatically.

---

## Features

### Core Pipeline
- Supports URLs via yt-dlp (YouTube, Vimeo, 1000+ sites)
- Supports local media files (.mp4, .wav, .webm, .opus, etc.)
- Robust audio preprocessing:
  - Loudness normalization (LUFS-based)
  - High/low-pass filtering for speech clarity
  - Dynamic volume normalization
  - Optional silence trimming
- Transcribes using whisper.cpp with auto-tuned parameters

### Intelligent Processing
- **Automatic chunking**: Files longer than 15 minutes (configurable) are split, transcribed separately, and stitched seamlessly
- **Smart model selection**: Chooses whisper model based on file duration and available RAM
- **Memory backpressure**: Waits if RAM is low; aborts if swap exceeds limits
- **Crash recovery**: Resumes incomplete jobs from last checkpoint
- **Retry logic**: Failed jobs retry with exponential backoff (max 3 attempts)

### Resource Management
- Monitors disk space, RAM, and swap usage
- Auto-cleans temporary files after successful transcription
- Optional raw input compression to save space
- Detects and removes corrupted model files

---

## Requirements

Make sure these are installed:

- **ffmpeg** (audio processing)
- **whisper-cpp** (transcription engine)
- **curl** (for yt-dlp auto-download)

macOS example (Homebrew):

    brew install ffmpeg whisper-cpp

**Note:** yt-dlp is automatically downloaded to bin/ on first run.

---

## Installation

Clone the repo:

    git clone https://github.com/ulhanus/ultransc.git
    cd ultransc

Make script executable:

    chmod +x ultransc.sh

Download a Whisper model:

    curl -L https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin -o models/ggml-medium.en.bin

---

## Usage

### Basic transcription

    ./ultransc.sh

### Process a URL
Add URLs to queue/links.txt (one per line):

    echo "https://www.youtube.com/watch?v=example" >> queue/links.txt
    ./ultransc.sh

### Process local files
Drop files into queue/incoming/:

    cp my_lecture.mp4 queue/incoming/
    ./ultransc.sh

### Output location
Transcripts appear in workspace/ with timestamped folders:

    workspace/
      my_lecture_20260107_143052/
        transcript.txt
        transcript.json
        transcript.srt
        segments.json
        job.log
        raw_input

---

## Configuration

Edit config/default.conf to customize behavior.

**Audio Quality:**

    AUDIO_NORMALIZATION=true
    TARGET_LOUDNESS=-18
    HIGHPASS_FREQ=150
    LOWPASS_FREQ=3800

**Performance:**

    CHUNK_MINUTES=15
    THREADS=auto
    MIN_FREE_RAM_GB=2

**Reliability:**

    ENABLE_CRASH_RECOVERY=true
    MAX_RETRIES=3

---

## Roadmap

**v0.5** ✅ (Current)  
Intelligent chunking, crash recovery, memory-safe processing

**v0.6** (Planned)  
Daemon mode, web UI, GPU acceleration detection

**v1.0** (Future)  
Rust CLI rewrite, plugin architecture

**2.x** (Vision)  
Knowledge indexing, semantic search, GUI app, full local RAG

---

## Contributing

Open issues, propose structure, break things, critique decisions.  
All contributions welcome: modules, engines, UI, docs, tests.

---

## License

TBD (likely MIT/Apache dual or similar permissive license)

---

Made because everything good went premium and I'm not doing subscriptions to exist.
