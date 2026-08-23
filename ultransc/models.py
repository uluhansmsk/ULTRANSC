import json
import time
from pathlib import Path
from typing import Optional
from urllib.error import URLError
from urllib.request import urlopen, Request

from .logger import get_logger

class ModelManager:
    def __init__(self, paths, config, ram_gb: int):
        self.logger = get_logger()
        self.paths = paths
        self.config = config
        self.ram_gb = ram_gb
        self.default_model = "ggml-medium.en.bin" if config.model == "auto" else config.model

    def update_model_list(self) -> None:
        installed = {path.name: True for path in sorted(self.paths.models.glob("*.bin"))}
        payload = {"installed": installed, "default": self.default_model}
        self.paths.model_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    def download_with_retry(self, url: str, target_path: Path) -> bool:
        """Robust download with progress reporting and retry logic."""
        attempt = 1
        max_attempts = self.config.max_retries
        delay = self.config.retry_backoff_base

        while attempt <= max_attempts:
            try:
                self.logger.info(f"Downloading (attempt {attempt}/{max_attempts}): {url}")
                req = Request(url, headers={'User-Agent': 'ULTRANSC/1.0'})
                with urlopen(req, timeout=30) as response, open(target_path, 'wb') as out_file:
                    total_size = int(response.headers.get('content-length', 0))
                    downloaded = 0
                    chunk_size = 1024 * 1024  # 1MB
                    last_pct = -1
                    while True:
                        chunk = response.read(chunk_size)
                        if not chunk:
                            break
                        out_file.write(chunk)
                        downloaded += len(chunk)
                        if total_size > 0:
                            pct = int((downloaded / total_size) * 100)
                            if pct != last_pct and (pct % 10 == 0 or pct == 100):
                                mb_down = downloaded / (1024 * 1024)
                                mb_tot = total_size / (1024 * 1024)
                                self.logger.info(f"Download progress: {pct}% ({mb_down:.1f}MB / {mb_tot:.1f}MB)")
                                last_pct = pct
                return True
            except (URLError, OSError) as e:
                self.logger.error(f"Download failed: {e}")
                if attempt < max_attempts:
                    self.logger.info(f"Retrying in {delay}s...")
                    time.sleep(delay)
                    delay *= self.config.retry_backoff_multiplier
                attempt += 1
        return False

    def ensure_model_available(self) -> None:
        if any(self.paths.models.glob("*.bin")):
            return
        if self.config.auto_download_model != "true":
            self.logger.error(f"No model found in {self.paths.models} and AUTO_DOWNLOAD_MODEL=false")
            raise SystemExit(1)
        model_to_download = self.default_model
        model_url = f"{self.config.model_base_url}/{model_to_download}"
        target_path = self.paths.models / model_to_download
        
        self.logger.info(f"No models found - downloading default model: {model_to_download}")
        success = self.download_with_retry(model_url, target_path)
        
        if not success or not target_path.exists() or target_path.stat().st_size == 0:
            self.logger.error(f"Failed to download valid model file.")
            if target_path.exists():
                target_path.unlink()
            raise SystemExit(1)
            
        self.logger.info(f"Model downloaded successfully: {model_to_download}")

    def choose_model(self) -> str:
        if self.config.model and self.config.model != "auto" and (self.paths.models / self.config.model).exists():
            return self.config.model
        if self.ram_gb >= 6 and (self.paths.models / "ggml-medium.en.bin").exists():
            return "ggml-medium.en.bin"
        if (self.paths.models / "ggml-small.en.bin").exists():
            return "ggml-small.en.bin"
        for path in sorted(self.paths.models.glob("*.bin")):
            return path.name
        self.logger.error(f"No Whisper models found in {self.paths.models}")
        raise SystemExit(1)

    def init_model(self) -> str:
        if not self.paths.model_json.exists():
            self.paths.model_json.write_text('{"installed":{}, "default":"ggml-medium.en.bin"}\n', encoding="utf-8")
        self.update_model_list()
        self.logger.info("Model list updated")
        self.ensure_model_available()
        self.update_model_list()
        self.logger.info("Model list refreshed")
        chosen_model = self.choose_model()
        self.logger.info(f"Using transcription model: {chosen_model}")
        return chosen_model
