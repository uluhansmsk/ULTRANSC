from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path


def clean_name(value: str) -> str:
    return re.sub(r'[/:*?"<>|]', "_", value).strip() or "Untitled"


def run_capture(args) -> str:
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return result.stdout.strip()


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv:
        print("Usage: transcribe <url>")
        return 1
    url = argv[0]
    base_dir = Path.home() / "Documents" / "Transcripts"
    model = Path.home() / "Documents" / "whisper-cpp-bin" / "ggml-medium.en.bin"
    print("Fetching metadata...")
    title = clean_name(run_capture(["yt-dlp", "--get-title", url]) or "Untitled")
    channel = clean_name(run_capture(["yt-dlp", "--get-filename", "-o", "%(channel)s", url]) or "UnknownChannel")
    platform = clean_name(url.split("/")[2].replace("www.", "") if "://" in url and len(url.split("/")) > 2 else "unknown")
    date = datetime.now().strftime("%Y-%m-%d_%H-%M")
    output_dir = base_dir / platform / channel / f"{date}_{title}"
    output_dir.mkdir(parents=True, exist_ok=True)
    os.chdir(output_dir)
    print(f"Output directory: {output_dir}")
    print("Downloading source...")
    subprocess.run([
        "yt-dlp",
        "--extractor-args",
        "youtube:skip=dash",
        "-f",
        "bestaudio/best",
        "-o",
        "source.%(ext)s",
        url,
    ], check=True)
    files = sorted(Path(".").glob("source.*"))
    if not files:
        raise SystemExit("Downloaded source file not found")
    print("Converting to WAV...")
    subprocess.run(
        ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", str(files[0]), "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", "audio.wav"],
        check=True,
    )
    print("Transcribing using whisper...")
    subprocess.run(
        [
            "whisper-cli",
            "audio.wav",
            "--model",
            str(model),
            "--output-txt",
            "--output-srt",
            "--output-json",
            "--language",
            "auto",
            "--print-progress",
            "--output-file",
            "transcript",
        ],
        check=True,
    )
    print("Cleaning temporary audio...")
    audio = Path("audio.wav")
    if audio.exists():
        audio.unlink()
    print("")
    print("DONE")
    print("Transcript files created:")
    print("   - transcript.txt")
    print("   - transcript.srt")
    print("   - transcript.json")
    print("")
    print(f"Stored in: {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
