# ULTRANSC

Local-first transcription pipeline for humans who got tired of SaaS paywalls, API keys, and "premium features".  
Feed it a link or a file. It downloads the media, extracts audio, transcribes it with Whisper, and stores everything in a clean structure.  
No accounts. No cloud. No bullshit.

---

## Status

This is the **initial prototype**.  
Right now it's a Bash script with a working pipeline:

> URL → yt-dlp → ffmpeg → whisper.cpp → transcript (.txt, .srt, .json)

It works locally, archiving videos, lectures, VODs, podcasts, streams, or files you drag into it.

This is not final. It’s the seed that grows into a full cross-platform CLI, GUI, daemon, and plugin ecosystem.

---

## Philosophy

- **Local-first**
- **Configurable, not rigid**
- **Modular and swappable components**
- **Works offline**
- **Sandboxed runtime (eventually)**
- **No forced cloud dependencies**
- **Users choose how deep they go: casual mode or expert flags**

If something breaks upstream, ULTRANSC can switch modules, versions, or providers.  
If your system has tools installed, ULTRANSC can use them.  
If not, it will eventually manage its own sandboxed runtime.

---

## Current Features (Prototype)

- Supports URLs via `yt-dlp`
- Supports local media files (.mp4, .wav, .webm, etc.)
- Converts media to 16kHz mono WAV for transcription
- Transcribes using `whisper.cpp`
- Outputs:
  - transcript.txt
  - transcript.srt
  - transcript.json
- Creates organized output folder per processed item

---

## Requirements (Current Prototype)

Make sure these are installed:

- ffmpeg
- yt-dlp
- whisper.cpp binary + model (recommend medium.en, small.en, or base)

macOS example (Homebrew):

brew install ffmpeg yt-dlp
brew install whisper-cpp

---

## Installation (Prototype)

Clone the repo:

git clone https://github.com/ulhanus/ultransc.git
cd ultransc

Make script executable:

chmod +x ultransc.sh

---

## Usage

Basic:

./ultransc.sh https://www.youtube.com/watch?v=example

Local file:

./ultransc.sh my_audio_or_video.mp4

Transcripts will appear under:

~/Documents/Transcripts

---

## Roadmap (High-Level)

0.2  Modular Bash script (the current target)
0.4  Rust CLI rewrite (same behavior, stable config + flags)
0.6  Local scheduler, queue, runtime sandbox, daemon mode
0.8  Knowledge indexing + search (metadata + raw text)
1.0  GUI app (Tauri) + installers (brew/winget/deb)
2.x  Plugin ecosystem, multi-engine support, embeddings, semantic search, and full local RAG

---

## Vision

ULTRANSC is not just a script.  
It becomes:

- a personal media archive tool
- an offline transcription engine
- a downloader that never breaks silently
- a searchable memory layer for long-form content
- a self-contained knowledge system

Nothing leaves your machine unless you explicitly want it to.

The goal:  
**Handle anything that can be transcribed, from any platform, forever — locally.**

---

## Contributing

Right now: open issues, propose structure, break things, critique decisions.  
Later: modules, engines, language support, UI, packaging, docs, tests.

If you have opinions, welcome. If you don't, you'll develop some.

---

## License

Will likely be MIT/Apache dual or similar permissive license — TBD.

---


Made because everything good went premium and I'm not doing subscriptions to exist.
