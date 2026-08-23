import os
import random
import time
import shlex
from pathlib import Path
from typing import List, Optional

from .logger import get_logger
from .utils import move_replace, is_queue_artifact, cleanup_download_attempt, run_cmd

class QueueManager:
    def __init__(self, paths, config):
        self.logger = get_logger()
        self.paths = paths
        self.config = config

    def acquire_lock(self) -> None:
        if self.paths.lock_dir.exists():
            pid_file = self.paths.lock_dir / "pid"
            lock_pid = pid_file.read_text(encoding="utf-8").strip() if pid_file.exists() else ""
            if lock_pid.isdigit():
                try:
                    os.kill(int(lock_pid), 0)
                    self.logger.error(f"Another ULTRANSC run is active (pid: {lock_pid}).")
                    raise SystemExit(1)
                except ProcessLookupError:
                    pass
                except PermissionError:
                    self.logger.error(f"Another ULTRANSC run is active (pid: {lock_pid}).")
                    raise SystemExit(1)
            self.logger.info(f"Stale lock detected. Removing {self.paths.lock_dir}")
            if pid_file.exists():
                pid_file.unlink()
            try:
                self.paths.lock_dir.rmdir()
            except OSError:
                pass
        try:
            self.paths.lock_dir.mkdir()
        except FileExistsError:
            self.logger.error(f"Another ULTRANSC run is active (lock: {self.paths.lock_dir}).")
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

    def clean_incomplete_jobs(self) -> None:
        for job in self.paths.workspace.iterdir() if self.paths.workspace.exists() else []:
            if job.is_dir() and not (job / "transcript.txt").exists():
                self.logger.info(f"Cleaning incomplete job: {job}")
                import shutil
                shutil.rmtree(job)

    def recover_processing_queue(self) -> None:
        if self.config.enable_crash_recovery == "true":
            for item in self.paths.processing.iterdir() if self.paths.processing.exists() else []:
                if is_queue_artifact(item):
                    self.logger.info(f"Ignoring queue metadata file: {item.name}")
                    if item.is_file() or item.is_symlink():
                        item.unlink()
                    continue
                self.logger.info(f"Recovering interrupted file: {item.name}")
                move_replace(item, self.paths.incoming / item.name)

    def process_url_queue(self, process_file_callback) -> None:
        tmp_links = self.paths.links.with_suffix(self.paths.links.suffix + ".tmp")
        kept: List[str] = []
        if not self.paths.links.exists():
            self.paths.links.touch()
        urls = [line.rstrip("\n") for line in self.paths.links.read_text(encoding="utf-8").splitlines()]

        def save_kept(extra: Optional[List[str]] = None) -> None:
            lines = kept + (extra or [])
            tmp_links.write_text("".join(f"{line}\n" for line in lines if line), encoding="utf-8")
            move_replace(tmp_links, self.paths.links)

        for index, raw in enumerate(urls):
            url = raw.rstrip("\n")
            if not url or url.lstrip().startswith("#"):
                continue
            self.logger.info(f"Downloading URL: {url}")
            stem = f"download_{int(time.time())}_{random.randrange(0, 32768)}"
            out_template = self.paths.incoming / f"{stem}.%(ext)s"
            ytdlp_args = [
                str(self.paths.bin / "yt-dlp"),
                "--no-update",
                "-f",
                self.config.ytdlp_format,
                "-o",
                str(out_template),
            ]
            if self.config.ytdlp_max_filesize:
                ytdlp_args.extend(["--max-filesize", self.config.ytdlp_max_filesize])
            ytdlp_args.extend(shlex.split(self.config.ytdlp_extra_args))
            ytdlp_args.append(url)
            try:
                result = run_cmd(ytdlp_args)
            except KeyboardInterrupt:
                cleanup_download_attempt(self.paths.incoming, stem)
                remaining = [url] + [line for line in urls[index + 1 :] if line]
                save_kept(remaining)
                self.logger.error(f"Interrupted while downloading {url}; URL queue preserved.")
                raise SystemExit(130)
            if result.returncode != 0:
                cleanup_download_attempt(self.paths.incoming, stem)
                self.logger.error(f"Failed to download {url}")
                kept.append(url)
                continue
            downloads = sorted(self.paths.incoming.glob(f"{stem}.*"))
            downloaded = next((path for path in downloads if path.is_file() and not is_queue_artifact(path)), None)
            if downloaded is None:
                cleanup_download_attempt(self.paths.incoming, stem)
                self.logger.error(f"Could not find downloaded file for {url}")
                kept.append(url)
                continue
            
            # Delegate the file processing back to the App
            if not process_file_callback(downloaded):
                cleanup_download_attempt(self.paths.incoming, stem)
                self.logger.error(f"URL job failed, keeping URL for retry: {url}")
                kept.append(url)
        save_kept()
