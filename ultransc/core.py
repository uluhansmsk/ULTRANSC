from __future__ import annotations

import json
import os
import platform
import random
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, Iterable, List, Optional
from urllib.request import urlretrieve


def _read_conf(path: Path) -> Dict[str, str]:
    values: Dict[str, str] = {}
    if not path.exists():
        return values
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.split("#", 1)[0].strip()
        values[key.strip()] = value
    return values


def _free_mb(path: Path) -> int:
    usage = shutil.disk_usage(path)
    return int(usage.free / 1024 / 1024)


def _move_replace(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() or dst.is_symlink():
        if dst.is_dir() and not dst.is_symlink():
            shutil.rmtree(dst)
        else:
            dst.unlink()
    shutil.move(str(src), str(dst))


def _run(args: List[str], timeout: Optional[int] = None, capture: bool = False) -> subprocess.CompletedProcess:
    kwargs = {
        "text": True,
        "timeout": timeout,
    }
    if capture:
        kwargs.update({"stdout": subprocess.PIPE, "stderr": subprocess.PIPE})
    return subprocess.run(args, **kwargs)


@dataclass
class Paths:
    root: Path

    @property
    def queue(self) -> Path:
        return self.root / "queue"

    @property
    def incoming(self) -> Path:
        return self.queue / "incoming"

    @property
    def links(self) -> Path:
        return self.queue / "links.txt"

    @property
    def processing(self) -> Path:
        return self.queue / "processing"

    @property
    def done(self) -> Path:
        return self.queue / "done"

    @property
    def failed(self) -> Path:
        return self.queue / "failed"

    @property
    def models(self) -> Path:
        return self.root / "models"

    @property
    def bin(self) -> Path:
        return self.root / "bin"

    @property
    def workspace(self) -> Path:
        return self.root / "workspace"

    @property
    def logs(self) -> Path:
        return self.root / "logs"

    @property
    def config_dir(self) -> Path:
        return self.root / "config"

    @property
    def model_json(self) -> Path:
        return self.models / "list.json"

    @property
    def system_log(self) -> Path:
        return self.logs / "system.log"

    @property
    def error_log(self) -> Path:
        return self.logs / "errors.log"

    @property
    def lock_dir(self) -> Path:
        return self.root / ".ultransc.lock"

    @property
    def config_file(self) -> Path:
        return self.config_dir / "default.conf"


class App:
    def __init__(self, root: Optional[Path] = None) -> None:
        self.paths = Paths((root or Path.cwd()).resolve())
        self.config = _read_conf(self.paths.config_file)
        self.os_name = platform.system()
        self.arch = platform.machine()
        self.cpu_cores = 1
        self.ram_gb = 1
        self.threads_value = "1"
        self.ffmpeg_threads_value = "1"
        self.fast_mode_value = "false"
        self.whisper_bin = ""
        self.metal_supported = False
        self._init_defaults()

    def _cfg(self, key: str, default: str) -> str:
        return self.config.get(key, default)

    def _init_defaults(self) -> None:
        model = self.config.get("MODEL", "auto") or "auto"
        self.model = model
        self.max_duration = int(self._cfg("MAX_DURATION", "10800"))
        self.min_free_disk_mb = int(self._cfg("MIN_FREE_DISK_MB", "500"))
        self.target_loudness = self._cfg("TARGET_LOUDNESS", "-18")
        self.language = self._cfg("LANGUAGE", "en")
        self.max_retries = int(self._cfg("MAX_RETRIES", "3"))
        self.retry_backoff_base = int(self._cfg("RETRY_BACKOFF_BASE", "5"))
        self.retry_backoff_multiplier = int(self._cfg("RETRY_BACKOFF_MULTIPLIER", "2"))
        self.enable_crash_recovery = self._cfg("ENABLE_CRASH_RECOVERY", "true")
        self.auto_cleanup_temp = self._cfg("AUTO_CLEANUP_TEMP", "true")
        self.auto_download_model = self._cfg("AUTO_DOWNLOAD_MODEL", "true")
        self.model_base_url = self._cfg(
            "MODEL_BASE_URL",
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main",
        )
        self.whisper_cmd = self._cfg("WHISPER_CMD", "auto")
        self.threads = self._cfg("THREADS", "auto")
        self.fast_mode = self._cfg("FAST_MODE", "auto")
        self.whisper_speed_preset = self._cfg("WHISPER_SPEED_PRESET", "fast")
        self.whisper_args = self._cfg("WHISPER_ARGS", "")
        self.ffmpeg_threads = self._cfg("FFMPEG_THREADS", "auto")
        self.stage2_max_duration = int(self._cfg("STAGE2_MAX_DURATION", "0"))
        self.prefer_metal = self._cfg("PREFER_METAL", "true")
        self.default_model = "ggml-medium.en.bin" if model == "auto" else model

    def init_folders(self) -> None:
        for path in (
            self.paths.incoming,
            self.paths.processing,
            self.paths.done,
            self.paths.failed,
            self.paths.models,
            self.paths.bin,
            self.paths.workspace,
            self.paths.logs,
            self.paths.config_dir,
        ):
            path.mkdir(parents=True, exist_ok=True)
        self.paths.links.touch(exist_ok=True)
        self.paths.system_log.touch(exist_ok=True)
        self.paths.error_log.touch(exist_ok=True)

    def log(self, message: str) -> None:
        text = f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {message}"
        print(text)
        with self.paths.system_log.open("a", encoding="utf-8") as handle:
            handle.write(text + "\n")

    def log_error(self, message: str) -> None:
        text = f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ERROR: {message}"
        print(text)
        with self.paths.error_log.open("a", encoding="utf-8") as handle:
            handle.write(text + "\n")

    def acquire_lock(self) -> None:
        if self.paths.lock_dir.exists():
            pid_file = self.paths.lock_dir / "pid"
            lock_pid = pid_file.read_text(encoding="utf-8").strip() if pid_file.exists() else ""
            if lock_pid.isdigit():
                try:
                    os.kill(int(lock_pid), 0)
                    self.log_error(f"Another ULTRANSC run is active (pid: {lock_pid}).")
                    raise SystemExit(1)
                except ProcessLookupError:
                    pass
                except PermissionError:
                    self.log_error(f"Another ULTRANSC run is active (pid: {lock_pid}).")
                    raise SystemExit(1)
            self.log(f"Stale lock detected. Removing {self.paths.lock_dir}")
            if pid_file.exists():
                pid_file.unlink()
            try:
                self.paths.lock_dir.rmdir()
            except OSError:
                pass
        try:
            self.paths.lock_dir.mkdir()
        except FileExistsError:
            self.log_error(f"Another ULTRANSC run is active (lock: {self.paths.lock_dir}).")
            raise SystemExit(1)
        (self.paths.lock_dir / "pid").write_text(str(os.getpid()), encoding="utf-8")

    def release_lock(self) -> None:
        pid_file = self.paths.lock_dir / "pid"
        if pid_file.exists():
            pid_file.unlink()
        if self.paths.lock_dir.exists():
            try:
                self.paths.lock_dir.rmdir()
            except OSError:
                pass

    def run_with_retries(self, func, *args) -> bool:
        attempt = 1
        delay = self.retry_backoff_base
        while True:
            if func(*args):
                return True
            if attempt >= self.max_retries:
                return False
            self.log_error(f"Attempt {attempt} failed. Retrying in {delay}s...")
            time.sleep(delay)
            delay *= self.retry_backoff_multiplier
            attempt += 1

    def check_resources(self) -> None:
        free_gb = int(_free_mb(self.paths.root) / 1024)
        if free_gb < 2:
            self.log_error("Less than 2GB free disk space - aborting.")
            raise SystemExit(1)
        test_file = self.paths.root / ".ultransc_write_test"
        try:
            test_file.touch()
        except OSError:
            self.log_error(f"Cannot write to ULTRANSC directory ({self.paths.root})")
            raise SystemExit(1)
        finally:
            if test_file.exists():
                test_file.unlink()

    def bootstrap_ytdlp(self) -> None:
        target = self.paths.bin / "yt-dlp"
        if target.exists():
            self.log("yt-dlp OK")
            return
        self.log("yt-dlp missing - downloading local copy...")
        urlretrieve("https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp", target)
        target.chmod(0o755)

    def check_tools(self) -> None:
        if not shutil.which("ffmpeg"):
            self.log_error("FFmpeg not found. Install it.")
            raise SystemExit(1)
        self.log("FFmpeg OK")
        if not shutil.which("ffprobe"):
            self.log_error("ffprobe not found. Install FFmpeg package with ffprobe.")
            raise SystemExit(1)
        self.log("ffprobe OK")

    def check_environment(self) -> None:
        self.log("Running full environment check...")
        if self.os_name not in ("Darwin", "Linux"):
            self.log_error(f"Unsupported OS: {self.os_name}")
            raise SystemExit(1)
        self.log(f"Detected architecture: {self.arch}")
        self.cpu_cores = os.cpu_count() or 1
        if self.os_name == "Darwin":
            try:
                mem_bytes = int(subprocess.check_output(["sysctl", "-n", "hw.memsize"], text=True).strip())
                self.ram_gb = int(mem_bytes / 1024 / 1024 / 1024)
            except Exception:
                self.ram_gb = 1
        else:
            try:
                mem_kb = 0
                for line in Path("/proc/meminfo").read_text(encoding="utf-8").splitlines():
                    if line.startswith("MemTotal:"):
                        mem_kb = int(line.split()[1])
                        break
                self.ram_gb = int(mem_kb / 1024 / 1024) or 1
            except Exception:
                self.ram_gb = 1
        self.log(f"System RAM: {self.ram_gb}GB")
        self.log(f"CPU cores: {self.cpu_cores}")
        self.threads_value = str(self.cpu_cores) if self.threads == "auto" else self.threads
        self.ffmpeg_threads_value = str(self.cpu_cores) if self.ffmpeg_threads == "auto" else self.ffmpeg_threads
        self.log(f"Whisper threads: {self.threads_value}")
        self.log(f"FFmpeg threads: {self.ffmpeg_threads_value}")
        if self.fast_mode == "auto":
            self.fast_mode_value = "false" if self.os_name == "Darwin" else "true"
        else:
            self.fast_mode_value = self.fast_mode
        self.log(f"Speed preset: {self.whisper_speed_preset} (fast mode: {self.fast_mode_value})")
        self.check_resources()
        self.bootstrap_ytdlp()
        self.check_tools()

    def detect_whisper_cmd(self) -> Optional[str]:
        if self.whisper_cmd != "auto":
            configured = Path(self.whisper_cmd)
            if "/" in self.whisper_cmd and configured.exists() and os.access(configured, os.X_OK):
                return self.whisper_cmd
            found = shutil.which(self.whisper_cmd)
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
                self.log_error("Whisper binary not found. Set WHISPER_CMD or install whisper.cpp (whisper-cli).")
            else:
                self.log_error("Whisper binary not found. Install whisper-cpp (whisper-cli).")
            raise SystemExit(1)
        self.log(f"Whisper command OK: {self.whisper_bin}")
        self.metal_supported = False
        if self.os_name == "Darwin" and self.prefer_metal == "true":
            result = _run([self.whisper_bin, "--help"], capture=True)
            if "--metal" in ((result.stdout or "") + (result.stderr or "")):
                self.metal_supported = True
                self.log("Metal acceleration supported")
            else:
                self.log("Metal flag not supported by whisper binary; running on CPU")

    def update_model_list(self) -> None:
        installed = {path.name: True for path in sorted(self.paths.models.glob("*.bin"))}
        payload = {"installed": installed, "default": self.default_model}
        self.paths.model_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    def ensure_model_available(self) -> None:
        if any(self.paths.models.glob("*.bin")):
            return
        if self.auto_download_model != "true":
            self.log_error(f"No model found in {self.paths.models} and AUTO_DOWNLOAD_MODEL=false")
            raise SystemExit(1)
        model_to_download = self.default_model
        model_url = f"{self.model_base_url}/{model_to_download}"
        target_path = self.paths.models / model_to_download
        self.log(f"No models found - downloading default model: {model_to_download}")
        try:
            urlretrieve(model_url, target_path)
        except Exception:
            self.log_error(f"Model download failed: {model_url}")
            if target_path.exists():
                target_path.unlink()
            raise SystemExit(1)
        if not target_path.exists() or target_path.stat().st_size == 0:
            self.log_error(f"Downloaded model is empty: {target_path}")
            if target_path.exists():
                target_path.unlink()
            raise SystemExit(1)
        self.log(f"Model downloaded successfully: {model_to_download}")

    def choose_model(self) -> str:
        if self.model and self.model != "auto" and (self.paths.models / self.model).exists():
            return self.model
        if self.ram_gb >= 6 and (self.paths.models / "ggml-medium.en.bin").exists():
            return "ggml-medium.en.bin"
        if (self.paths.models / "ggml-small.en.bin").exists():
            return "ggml-small.en.bin"
        for path in sorted(self.paths.models.glob("*.bin")):
            return path.name
        self.log_error(f"No Whisper models found in {self.paths.models}")
        raise SystemExit(1)

    def init_model(self) -> None:
        if not self.paths.model_json.exists():
            self.paths.model_json.write_text('{"installed":{}, "default":"ggml-medium.en.bin"}\n', encoding="utf-8")
        self.update_model_list()
        self.log("Model list updated")
        self.ensure_model_available()
        self.update_model_list()
        self.log("Model list refreshed")
        self.model = self.choose_model()
        self.log(f"Using transcription model: {self.model}")

    def get_mean_volume(self, media: Path) -> str:
        result = _run(["ffmpeg", "-i", str(media), "-af", "volumedetect", "-f", "null", os.devnull], capture=True)
        text = (result.stdout or "") + (result.stderr or "")
        match = re.search(r"mean_volume:\s*([^ ]+)\s*dB", text)
        return match.group(1) if match else ""

    def convert_with_filter(self, input_file: Path, output: Path, audio_filter: str, tag: str) -> bool:
        thread_args: List[str] = []
        if self.ffmpeg_threads_value:
            thread_args = ["-threads", self.ffmpeg_threads_value]
        self.log(f"Running FFmpeg ({tag})...")
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
            return _run(args, timeout=300).returncode == 0
        except subprocess.TimeoutExpired:
            return False

    def run_whisper(self, wav: Path, out: Path) -> bool:
        thread_args = ["--threads", self.threads_value] if self.threads_value else []
        if self.whisper_speed_preset in ("max", "fast"):
            preset_args = ["--best-of", "1", "--beam-size", "1"]
        elif self.whisper_speed_preset == "balanced":
            preset_args = ["--best-of", "2", "--beam-size", "2"]
        else:
            preset_args = []
        extra_args = shlex.split(self.whisper_args) if self.whisper_args else []
        metal_args = ["--metal"] if self.metal_supported else []
        args = [
            self.whisper_bin,
            str(wav),
            "--language",
            self.language,
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
            return _run(args, timeout=7200).returncode == 0
        except subprocess.TimeoutExpired:
            return False

    def clean_incomplete_jobs(self) -> None:
        for job in self.paths.workspace.iterdir() if self.paths.workspace.exists() else []:
            if job.is_dir() and not (job / "transcript.txt").exists():
                self.log(f"Cleaning incomplete job: {job}")
                shutil.rmtree(job)

    def _duration(self, media: Path) -> Optional[int]:
        result = _run(
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

    def process_file(self, file_path: Path) -> bool:
        fname = file_path.name
        clean_name = Path(fname).stem.replace(" ", "_")
        job_id = f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_{random.randrange(0, 32768)}"
        job_dir = self.paths.workspace / f"{clean_name}_{job_id}"
        job_dir.mkdir(parents=True, exist_ok=True)
        self.log(f"Starting job {job_id} for {file_path}")
        base = file_path.name
        proc_file = self.paths.processing / base

        def fail_job(reason: str) -> bool:
            self.log_error(reason)
            if proc_file.exists():
                _move_replace(proc_file, self.paths.failed / base)
            return False

        try:
            _move_replace(file_path, proc_file)
        except Exception:
            return fail_job(f"Could not move file to processing queue: {file_path}")
        if not proc_file.exists():
            return fail_job(f"Could not move file to processing queue: {file_path}")

        shutil.copy2(proc_file, job_dir / "raw_input")
        duration = self._duration(proc_file)
        if duration is None:
            return fail_job(f"Cannot read media duration (possibly corrupt file): {base}")
        if duration > self.max_duration:
            self.log_error(f"File exceeds MAX_DURATION ({self.max_duration}s) - skipping.")
            _move_replace(proc_file, self.paths.failed / base)
            return True
        if _free_mb(self.paths.root) < self.min_free_disk_mb:
            self.log_error(f"Low disk (<{self.min_free_disk_mb}MB). Aborting batch.")
            raise SystemExit(1)

        self.log("Analyzing loudness...")
        mean_vol = self.get_mean_volume(proc_file) or self.target_loudness
        self.log(f"Mean volume: {mean_vol} dB")
        gain_stage1 = max(float(self.target_loudness) - float(mean_vol), 0.0)
        gain_stage2 = gain_stage1 + 6.0
        self.log(f"Computed gain: Stage1 = {gain_stage1:.1f} dB, Stage2 = {gain_stage2:.1f} dB")
        filter_stage1 = f"highpass=f=120, lowpass=f=3800, dynaudnorm=p=0.8:m=10, volume={gain_stage1:.1f}dB"
        filter_stage2 = f"highpass=f=120, lowpass=f=4200, dynaudnorm=p=0.9:m=12, volume={gain_stage2:.1f}dB"

        if not self.run_with_retries(
            self.convert_with_filter, proc_file, job_dir / "audio_stage1.wav", filter_stage1, "Stage 1"
        ):
            return fail_job(f"FFmpeg Stage 1 failed for {base}")
        if not self.run_with_retries(self.run_whisper, job_dir / "audio_stage1.wav", job_dir / "transcript_stage1"):
            return fail_job(f"Whisper Stage 1 failed for {base}")
        stage1_txt = job_dir / "transcript_stage1.txt"
        if not stage1_txt.exists() or stage1_txt.stat().st_size == 0:
            return fail_job(f"Missing Stage 1 transcript output for {base}")

        lines = stage1_txt.read_text(encoding="utf-8", errors="replace").splitlines()
        blank_count = sum(1 for line in lines if "[BLANK_AUDIO]" in line)
        blank_ratio = 0 if not lines else blank_count / len(lines)
        self.log(f"Blank ratio after Stage 1: {blank_ratio:g}")

        should_run_stage2 = False
        if self.fast_mode_value == "true":
            self.log("Fast mode enabled - skipping Stage 2")
        elif self.stage2_max_duration > 0 and duration > self.stage2_max_duration:
            self.log(f"Stage 2 skipped due to STAGE2_MAX_DURATION ({self.stage2_max_duration}s)")
        elif blank_ratio > 0.15:
            should_run_stage2 = True

        if should_run_stage2:
            self.log("High blank ratio - running Stage 2...")
            if not self.run_with_retries(
                self.convert_with_filter, proc_file, job_dir / "audio_stage2.wav", filter_stage2, "Stage 2"
            ):
                return fail_job(f"FFmpeg Stage 2 failed for {base}")
            if not self.run_with_retries(self.run_whisper, job_dir / "audio_stage2.wav", job_dir / "transcript"):
                return fail_job(f"Whisper Stage 2 failed for {base}")
            transcript_txt = job_dir / "transcript.txt"
            if not transcript_txt.exists() or transcript_txt.stat().st_size == 0:
                return fail_job(f"Missing Stage 2 transcript output for {base}")
        else:
            _move_replace(job_dir / "transcript_stage1.txt", job_dir / "transcript.txt")
            _move_replace(job_dir / "transcript_stage1.json", job_dir / "transcript.json")
            _move_replace(job_dir / "transcript_stage1.srt", job_dir / "transcript.srt")

        if (job_dir / "transcript.json").exists():
            segments = job_dir / "segments.json"
            if segments.exists() or segments.is_symlink():
                segments.unlink()
            try:
                segments.symlink_to("transcript.json")
            except OSError:
                pass
        if self.auto_cleanup_temp == "true":
            for temp in (job_dir / "audio_stage1.wav", job_dir / "audio_stage2.wav"):
                if temp.exists():
                    temp.unlink()
        _move_replace(proc_file, self.paths.done / base)
        self.log(f"Job {job_id} completed.")
        return True

    def recover_processing_queue(self) -> None:
        if self.enable_crash_recovery == "true":
            for item in self.paths.processing.iterdir() if self.paths.processing.exists() else []:
                self.log(f"Recovering interrupted file: {item.name}")
                _move_replace(item, self.paths.incoming / item.name)

    def process_incoming_queue(self) -> None:
        for item in sorted(self.paths.incoming.iterdir()) if self.paths.incoming.exists() else []:
            if not self.process_file(item):
                self.log_error("Job failed, continuing.")

    def process_url_queue(self) -> None:
        tmp_links = self.paths.links.with_suffix(self.paths.links.suffix + ".tmp")
        kept: List[str] = []
        if not self.paths.links.exists():
            self.paths.links.touch()
        for raw in self.paths.links.read_text(encoding="utf-8").splitlines():
            url = raw.rstrip("\n")
            if not url:
                continue
            self.log(f"Downloading URL: {url}")
            out = self.paths.incoming / f"download_{int(time.time())}_{random.randrange(0, 32768)}.mp4"
            result = _run([str(self.paths.bin / "yt-dlp"), "-o", str(out), url])
            if result.returncode != 0:
                self.log_error(f"Failed to download {url}")
                kept.append(url)
                continue
            if not self.process_file(out):
                self.log_error(f"URL job failed, keeping URL for retry: {url}")
                kept.append(url)
        tmp_links.write_text("".join(f"{line}\n" for line in kept), encoding="utf-8")
        _move_replace(tmp_links, self.paths.links)

    def run_queue(self) -> None:
        self.log("Processing queue...")
        self.recover_processing_queue()
        self.process_incoming_queue()
        self.process_url_queue()


def run_preflight(root: Path) -> None:
    preflight = root / "tests" / "preflight.sh"
    if preflight.exists():
        subprocess.run(["bash", str(preflight)], check=True)


def run_pipeline(root: Optional[Path] = None, preflight: bool = True) -> int:
    app = App(root)
    app.init_folders()
    if preflight:
        run_preflight(app.paths.root)
    app.acquire_lock()
    try:
        app.check_environment()
        app.init_whisper()
        app.init_model()
        app.clean_incomplete_jobs()
        app.run_queue()
        app.log("Queue empty. ULTRANSC completed all tasks.")
        return 0
    except Exception as exc:
        if not isinstance(exc, SystemExit):
            app.log_error("ULTRANSC crashed inside a job. Continuing...")
            raise
        raise
    finally:
        app.release_lock()

