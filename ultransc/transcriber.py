import os
import shlex
import shutil
import subprocess
from pathlib import Path
from typing import Optional, List
from urllib.request import urlretrieve

from .logger import get_logger
from .utils import run_cmd

class Transcriber:
    def __init__(self, paths, config, os_name: str, ram_gb: int):
        self.logger = get_logger()
        self.paths = paths
        self.config = config
        self.os_name = os_name
        self.ram_gb = ram_gb
        
        self.whisper_bin = ""
        self.metal_supported = False
        self.model = ""

    def detect_whisper_cmd(self) -> Optional[str]:
        if self.config.whisper_cmd != "auto":
            configured = Path(self.config.whisper_cmd)
            if "/" in self.config.whisper_cmd and configured.exists() and os.access(configured, os.X_OK):
                return self.config.whisper_cmd
            found = shutil.which(self.config.whisper_cmd)
            return found or None
        for candidate in (
            str(self.paths.bin / "whisper-cli"),
            str(self.paths.bin / "whisper-cpp"),
            "whisper-cli",
            "whisper-cpp",
            "whisper",
        ):
            if "/" in candidate:
                path = Path(candidate)
                if path.exists() and os.access(path, os.X_OK):
                    return candidate
            else:
                found = shutil.which(candidate)
                if found:
                    return candidate
        return None

    def init_whisper(self) -> None:
        self.whisper_bin = self.detect_whisper_cmd() or ""
        if not self.whisper_bin:
            if self.os_name == "Linux":
                self.logger.error("Whisper binary not found. Set WHISPER_CMD or install whisper.cpp (whisper-cli).")
            else:
                self.logger.error("Whisper binary not found. Install whisper-cpp (whisper-cli).")
            raise SystemExit(1)
        self.logger.info(f"Whisper command OK: {self.whisper_bin}")
        self.metal_supported = False
        if self.os_name == "Darwin" and self.config.prefer_metal == "true":
            result = run_cmd([self.whisper_bin, "--help"], capture=True)
            if "--metal" in ((result.stdout or "") + (result.stderr or "")):
                self.metal_supported = True
                self.logger.info("Metal acceleration supported")
            else:
                self.logger.info("Metal flag not supported by whisper binary; running on CPU")

    def run_whisper(self, wav: Path, out: Path, threads_value: str) -> bool:
        thread_args = ["--threads", threads_value] if threads_value else []
        if self.config.whisper_speed_preset in ("max", "fast"):
            preset_args = ["--best-of", "1", "--beam-size", "1"]
        elif self.config.whisper_speed_preset == "balanced":
            preset_args = ["--best-of", "2", "--beam-size", "2"]
        else:
            preset_args = []
        extra_args = shlex.split(self.config.whisper_args) if self.config.whisper_args else []
        metal_args = ["--metal"] if self.metal_supported else []
        args = [
            self.whisper_bin,
            str(wav),
            "--language",
            self.config.language,
            "--model",
            str(self.paths.models / self.model),
            *thread_args,
            *preset_args,
            *extra_args,
            *metal_args,
            "--output-txt",
            "--output-json",
            "--output-srt",
            "--output-file",
            str(out),
        ]
        try:
            return run_cmd(args, timeout=7200).returncode == 0
        except subprocess.TimeoutExpired:
            return False
