import os
import platform
import random
import shutil
import time
from datetime import datetime
from pathlib import Path
from typing import Optional
from urllib.request import urlretrieve

# Expose _read_conf for backward compatibility (e.g., tests)
from .config import Config, read_conf as _read_conf
from .logger import setup_logger, get_logger
from .media import MediaProcessor
from .models import ModelManager
from .paths import Paths
from .queue_manager import QueueManager
from .transcriber import Transcriber
from .utils import free_mb, move_replace, is_queue_artifact, notify_webhook


class App:
    def __init__(self, root: Optional[Path] = None) -> None:
        self.paths = Paths((root or Path.cwd()).resolve())
        self.config = Config.load(self.paths.config_file)
        self.os_name = platform.system()
        self.arch = platform.machine()
        self.cpu_cores = 1
        self.ram_gb = 1
        
        # Test compatibility properties
        self.threads_value = "1"
        self.ffmpeg_threads_value = "1"
        self.fast_mode_value = "false"
        self.whisper_bin = ""
        self.model = self.config.model

        # Setup standard logging
        self.logger = setup_logger(self.paths.system_log, self.paths.error_log)
        
        self.queue_mgr = QueueManager(self.paths, self.config)
        self.media = MediaProcessor(
            ffmpeg_threads=self.config.ffmpeg_threads,
            max_duration=self.config.max_duration,
            stage2_max_duration=self.config.stage2_max_duration,
            min_free_disk_mb=self.config.min_free_disk_mb,
            target_loudness=self.config.target_loudness,
        )

    def _cfg(self, key: str, default: str) -> str:
        # For backward compatibility if tests mock/use this
        return _read_conf(self.paths.config_file).get(key, default)

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

    # Legacy logging hooks for tests that mock self.log
    def log(self, message: str) -> None:
        self.logger.info(message)

    def log_error(self, message: str) -> None:
        self.logger.error(message)

    def acquire_lock(self) -> None:
        self.queue_mgr.acquire_lock()

    def release_lock(self) -> None:
        self.queue_mgr.release_lock()

    def run_with_retries(self, func, *args) -> bool:
        attempt = 1
        delay = self.config.retry_backoff_base
        while True:
            if func(*args):
                return True
            if attempt >= self.config.max_retries:
                return False
            self.logger.error(f"Attempt {attempt} failed. Retrying in {delay}s...")
            time.sleep(delay)
            delay *= self.config.retry_backoff_multiplier
            attempt += 1

    def check_resources(self) -> None:
        free_gb = int(free_mb(self.paths.root) / 1024)
        if free_gb < 2:
            self.logger.error("Less than 2GB free disk space - aborting.")
            raise SystemExit(1)
        test_file = self.paths.root / ".ultransc_write_test"
        try:
            test_file.touch()
        except OSError:
            self.logger.error(f"Cannot write to ULTRANSC directory ({self.paths.root})")
            raise SystemExit(1)
        finally:
            if test_file.exists():
                test_file.unlink()

    def bootstrap_ytdlp(self) -> None:
        target = self.paths.bin / "yt-dlp"
        if target.exists():
            self.logger.info("yt-dlp OK")
            return
        self.logger.info("yt-dlp missing - downloading local copy...")
        # Keeping this simple as yt-dlp is very small, but could use download_with_retry
        urlretrieve("https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp", target)
        target.chmod(0o755)

    def check_tools(self) -> None:
        self.media.check_tools()

    def check_environment(self) -> None:
        self.logger.info("Running full environment check...")
        if self.os_name not in ("Darwin", "Linux"):
            self.logger.error(f"Unsupported OS: {self.os_name}")
            raise SystemExit(1)
        self.logger.info(f"Detected architecture: {self.arch}")
        self.cpu_cores = os.cpu_count() or 1
        if self.os_name == "Darwin":
            try:
                import subprocess
                mem_bytes = int(subprocess.check_output(
                    ["sysctl", "-n", "hw.memsize"],
                    text=True,
                    stderr=subprocess.DEVNULL,
                ).strip())
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
        self.logger.info(f"System RAM: {self.ram_gb}GB")
        self.logger.info(f"CPU cores: {self.cpu_cores}")
        self.threads_value = str(self.cpu_cores) if self.config.threads == "auto" else self.config.threads
        self.ffmpeg_threads_value = str(self.cpu_cores) if self.config.ffmpeg_threads == "auto" else self.config.ffmpeg_threads
        self.logger.info(f"Whisper threads: {self.threads_value}")
        self.logger.info(f"FFmpeg threads: {self.ffmpeg_threads_value}")
        
        if self.config.fast_mode == "auto":
            self.fast_mode_value = "false" if self.os_name == "Darwin" else "true"
        else:
            self.fast_mode_value = self.config.fast_mode
        self.logger.info(f"Speed preset: {self.config.whisper_speed_preset} (fast mode: {self.fast_mode_value})")
        
        self.check_resources()
        self.bootstrap_ytdlp()
        self.check_tools()

    def init_whisper(self) -> None:
        self.transcriber = Transcriber(self.paths, self.config, self.os_name, self.ram_gb)
        self.transcriber.init_whisper()
        # For tests that check this attribute
        self.whisper_bin = self.transcriber.whisper_bin

    def init_model(self) -> None:
        model_mgr = ModelManager(self.paths, self.config, self.ram_gb)
        self.model = model_mgr.init_model()
        self.transcriber.model = self.model

    def clean_incomplete_jobs(self) -> None:
        self.queue_mgr.clean_incomplete_jobs()

    # Mocks in test_python_port.py expect these on App
    def _duration(self, media: Path) -> Optional[int]:
        return self.media.get_duration(media)
        
    def get_mean_volume(self, media: Path) -> str:
        return self.media.get_mean_volume(media)
        
    def convert_with_filter(self, input_file: Path, output: Path, audio_filter: str, tag: str) -> bool:
        # Patch media's ffmpeg threads in case test modified self.ffmpeg_threads_value directly
        self.media.ffmpeg_threads = self.ffmpeg_threads_value
        return self.media.convert_with_filter(input_file, output, audio_filter, tag)
        
    def run_whisper(self, wav: Path, out: Path) -> bool:
        return self.transcriber.run_whisper(wav, out, self.threads_value)

    def process_file(self, file_path: Path) -> bool:
        fname = file_path.name
        clean_name = Path(fname).stem.replace(" ", "_")
        job_id = f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_{random.randrange(0, 32768)}"
        job_dir = self.paths.workspace / f"{clean_name}_{job_id}"
        job_dir.mkdir(parents=True, exist_ok=True)
        self.logger.info(f"Starting job {job_id} for {file_path}")
        base = file_path.name
        proc_file = self.paths.processing / base

        def fail_job(reason: str) -> bool:
            self.logger.error(reason)
            if proc_file.exists():
                move_replace(proc_file, self.paths.failed / base)
            return False

        try:
            move_replace(file_path, proc_file)
        except Exception:
            return fail_job(f"Could not move file to processing queue: {file_path}")
        if not proc_file.exists():
            return fail_job(f"Could not move file to processing queue: {file_path}")

        shutil.copy2(proc_file, job_dir / "raw_input")
        duration = self._duration(proc_file)
        if duration is None:
            return fail_job(f"Cannot read media duration (possibly corrupt file): {base}")
        if duration > self.config.max_duration:
            self.logger.error(f"File exceeds MAX_DURATION ({self.config.max_duration}s) - skipping.")
            move_replace(proc_file, self.paths.failed / base)
            return True
        if free_mb(self.paths.root) < self.config.min_free_disk_mb:
            self.logger.error(f"Low disk (<{self.config.min_free_disk_mb}MB). Aborting batch.")
            raise SystemExit(1)

        self.logger.info("Analyzing loudness...")
        mean_vol = self.get_mean_volume(proc_file) or self.config.target_loudness
        self.logger.info(f"Mean volume: {mean_vol} dB")
        gain_stage1 = max(float(self.config.target_loudness) - float(mean_vol), 0.0)
        gain_stage2 = gain_stage1 + 6.0
        self.logger.info(f"Computed gain: Stage1 = {gain_stage1:.1f} dB, Stage2 = {gain_stage2:.1f} dB")
        
        filter_stage1 = self.config.filter_stage1.format(gain=gain_stage1)
        filter_stage2 = self.config.filter_stage2.format(gain=gain_stage2)

        if not self.run_with_retries(
            self.convert_with_filter, proc_file, job_dir / "audio_stage1.wav", filter_stage1, "Stage 1"
        ):
            return fail_job(f"FFmpeg Stage 1 failed for {base}")
        if not self.run_with_retries(self.run_whisper, job_dir / "audio_stage1.wav", job_dir / "transcript_stage1"):
            return fail_job(f"Whisper Stage 1 failed for {base}")
        stage1_txt = job_dir / "transcript_stage1.txt"
        if not stage1_txt.exists() or stage1_txt.stat().st_size == 0:
            return fail_job(f"Missing Stage 1 transcript output for {base}")
        for suffix in ("json", "srt", "vtt"):
            output = job_dir / f"transcript_stage1.{suffix}"
            if not output.exists() or output.stat().st_size == 0:
                return fail_job(f"Missing Stage 1 {suffix.upper()} output for {base}")

        lines = stage1_txt.read_text(encoding="utf-8", errors="replace").splitlines()
        blank_count = sum(1 for line in lines if "[BLANK_AUDIO]" in line)
        blank_ratio = 0 if not lines else blank_count / len(lines)
        self.logger.info(f"Blank ratio after Stage 1: {blank_ratio:g}")

        should_run_stage2 = False
        if self.fast_mode_value == "true":
            self.logger.info("Fast mode enabled - skipping Stage 2")
        elif self.config.stage2_max_duration > 0 and duration > self.config.stage2_max_duration:
            self.logger.info(f"Stage 2 skipped due to STAGE2_MAX_DURATION ({self.config.stage2_max_duration}s)")
        elif blank_ratio > 0.15:
            should_run_stage2 = True

        if should_run_stage2:
            self.logger.info("High blank ratio - running Stage 2...")
            if not self.run_with_retries(
                self.convert_with_filter, proc_file, job_dir / "audio_stage2.wav", filter_stage2, "Stage 2"
            ):
                return fail_job(f"FFmpeg Stage 2 failed for {base}")
            if not self.run_with_retries(self.run_whisper, job_dir / "audio_stage2.wav", job_dir / "transcript"):
                return fail_job(f"Whisper Stage 2 failed for {base}")
            transcript_txt = job_dir / "transcript.txt"
            if not transcript_txt.exists() or transcript_txt.stat().st_size == 0:
                return fail_job(f"Missing Stage 2 transcript output for {base}")
            for suffix in ("json", "srt", "vtt"):
                output = job_dir / f"transcript.{suffix}"
                if not output.exists() or output.stat().st_size == 0:
                    return fail_job(f"Missing Stage 2 {suffix.upper()} output for {base}")
        else:
            move_replace(job_dir / "transcript_stage1.txt", job_dir / "transcript.txt")
            move_replace(job_dir / "transcript_stage1.json", job_dir / "transcript.json")
            move_replace(job_dir / "transcript_stage1.srt", job_dir / "transcript.srt")
            if (job_dir / "transcript_stage1.vtt").exists():
                move_replace(job_dir / "transcript_stage1.vtt", job_dir / "transcript.vtt")

        if (job_dir / "transcript.json").exists():
            segments = job_dir / "segments.json"
            if segments.exists() or segments.is_symlink():
                segments.unlink()
            try:
                segments.symlink_to("transcript.json")
            except OSError:
                pass
        if self.config.auto_cleanup_temp == "true":
            for temp in (job_dir / "audio_stage1.wav", job_dir / "audio_stage2.wav"):
                if temp.exists():
                    temp.unlink()
        move_replace(proc_file, self.paths.done / base)
        self.logger.info(f"Job {job_id} completed.")
        return True

    def process_incoming_queue(self) -> None:
        items = []
        for item in sorted(self.paths.incoming.iterdir()) if self.paths.incoming.exists() else []:
            if is_queue_artifact(item):
                self.logger.info(f"Ignoring queue metadata file: {item.name}")
                if item.is_file() or item.is_symlink():
                    item.unlink()
                continue
            if not item.is_file():
                self.logger.info(f"Ignoring non-file queue entry: {item.name}")
                continue
            items.append(item)
            
        if not items:
            return
            
        if self.config.max_concurrent_jobs <= 1:
            for item in items:
                if not self.process_file(item):
                    self.logger.error("Job failed, continuing.")
        else:
            from concurrent.futures import ThreadPoolExecutor
            self.logger.info(f"Processing up to {self.config.max_concurrent_jobs} jobs concurrently.")
            with ThreadPoolExecutor(max_workers=self.config.max_concurrent_jobs) as executor:
                futures = [executor.submit(self.process_file, item) for item in items]
                for future in futures:
                    if not future.result():
                        self.logger.error("Job failed, continuing.")

    def process_url_queue(self) -> None:
        self.queue_mgr.process_url_queue(self.process_file)

    def recover_processing_queue(self) -> None:
        self.queue_mgr.recover_processing_queue()

    def run_queue(self) -> None:
        self.logger.info("Processing queue...")
        self.recover_processing_queue()
        self.process_incoming_queue()
        self.process_url_queue()


def run_preflight(root: Path) -> None:
    from .preflight import main as preflight_main
    if preflight_main() != 0:
        raise SystemExit(1)


def _truthy(value: Optional[str]) -> bool:
    return str(value or "").strip().lower() in ("1", "true", "yes", "on")


def run_pipeline(root: Optional[Path] = None, preflight: Optional[bool] = None) -> int:
    app = App(root)
    app.init_folders()
    should_preflight = preflight
    if should_preflight is None:
        env_preflight = os.environ.get("ULTRANSC_RUN_PREFLIGHT")
        should_preflight = _truthy(env_preflight) if env_preflight is not None else _truthy(app.config.run_preflight)
    if should_preflight:
        run_preflight(app.paths.root)
    app.acquire_lock()
    try:
        app.check_environment()
        app.init_whisper()
        app.init_model()
        app.clean_incomplete_jobs()
        app.run_queue()
        app.logger.info("Queue empty. ULTRANSC completed all tasks.")
        notify_webhook(app.config.webhook_url, "✅ ULTRANSC completed all tasks in queue.")
        return 0
    except Exception as exc:
        if not isinstance(exc, SystemExit):
            app.logger.error("ULTRANSC crashed inside a job. Continuing...")
            notify_webhook(app.config.webhook_url, f"❌ ULTRANSC crashed: {exc}")
            raise
        raise
    finally:
        app.release_lock()
