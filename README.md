# ULTRANSC

Local-first transcription pipeline. No accounts. No cloud. No bullshit.

## Status

**v0.5 Stable Edition** — Actually works.

## Features

- Transcribes audio/video from URLs or local files
- Adaptive two-stage audio processing for optimal quality
- Automatic model selection (RAM-based)
- Queue system (drop files in queue/incoming/ or add URLs to queue/links.txt)
- Works offline
- Outputs: transcript.txt, transcript.srt, transcript.json, segments.json

## Requirements

- ffmpeg (audio processing)
- whisper-cpp (transcription)

macOS:

    brew install ffmpeg whisper-cpp

Note: yt-dlp downloads automatically on first run.

## Installation

    git clone https://github.com/ulhanus/ultransc.git
    cd ultransc
    chmod +x ultransc.sh

Download a Whisper model:

    curl -L https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin -o models/ggml-medium.en.bin

## Usage

Process local files:

    cp lecture.mp4 queue/incoming/
    ./ultransc.sh

Process URLs:

    echo "https://www.youtube.com/watch?v=xxx" >> queue/links.txt
    ./ultransc.sh

Output location:

    workspace/
      filename_timestamp/
        transcript.txt
        transcript.json
        transcript.srt
        segments.json
        raw_input

## Configuration (Optional)

Create config/default.conf:

    MODEL=ggml-medium.en.bin

The script works perfectly without config - smart defaults included.

## Companion Tools

### ice.sh - Keyword Extraction

Extract snippets from transcripts:

    ./ice.sh lecture_name -- "keyword1" "keyword2"

## Philosophy

- Works - Not theoretical, actually tested and reliable
- Simple - Does transcription, does it well
- Local - Your data stays on your machine
- Offline - No internet required after setup

Made because everything went premium and I'm not doing subscriptions.
