import os
import re
import shutil
import subprocess
from pathlib import Path
from typing import Optional, List

from .logger import get_logger
from .utils import run_cmd

class MediaProcessor:
    def __init__(self, ffmpeg_threads: str, max_duration: int, stage2_max_duration: int, min_free_disk_mb: int, target_loudness: str):
        self.logger = get_logger()
        self.ffmpeg_threads = ffmpeg_threads
        self.max_duration = max_duration
        self.stage2_max_duration = stage2_max_duration
        self.min_free_disk_mb = min_free_disk_mb
        self.target_loudness = target_loudness

    def check_tools(self) -> None:
        if not shutil.which("ffmpeg"):
            self.logger.error("FFmpeg not found. Install it.")
            raise SystemExit(1)
        self.logger.info("FFmpeg OK")
        if not shutil.which("ffprobe"):
            self.logger.error("ffprobe not found. Install FFmpeg package with ffprobe.")
            raise SystemExit(1)
        self.logger.info("ffprobe OK")

    def get_duration(self, media: Path) -> Optional[int]:
        result = run_cmd(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format=duration",
                "-of",
                "default=noprint_wrappers=1:nokey=1",
                str(media),
            ],
            capture=True,
        )
        text = (result.stdout or "").strip().splitlines()
        if not text:
            return None
        try:
            return int(float(text[0].strip()))
        except ValueError:
            return None

    def get_mean_volume(self, media: Path) -> str:
        result = run_cmd(["ffmpeg", "-i", str(media), "-af", "volumedetect", "-f", "null", os.devnull], capture=True)
        text = (result.stdout or "") + (result.stderr or "")
        match = re.search(r"mean_volume:\s*([^ ]+)\s*dB", text)
        return match.group(1) if match else ""

    def convert_with_filter(self, input_file: Path, output: Path, audio_filter: str, tag: str) -> bool:
        thread_args: List[str] = []
        if self.ffmpeg_threads:
            thread_args = ["-threads", self.ffmpeg_threads]
        self.logger.info(f"Running FFmpeg ({tag})...")
        args = [
            "ffmpeg",
            "-i",
            str(input_file),
            "-af",
            audio_filter,
            "-ar",
            "16000",
            "-ac",
            "1",
            "-c:a",
            "pcm_s16le",
            *thread_args,
            str(output),
            "-y",
        ]
        try:
            return run_cmd(args, timeout=300).returncode == 0
        except subprocess.TimeoutExpired:
            return False
