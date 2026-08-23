import shlex
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Any

def read_conf(path: Path) -> Dict[str, str]:
    values: Dict[str, str] = {}
    if not path.exists():
        return values
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        try:
            parts = shlex.split(line, comments=True, posix=True)
        except ValueError:
            parts = [line.split("#", 1)[0].strip()]
        if not parts:
            continue
        assignment = parts[1] if parts[0] == "export" and len(parts) > 1 else parts[0]
        if "=" not in assignment:
            continue
        key, value = assignment.split("=", 1)
        values[key.strip()] = value
    return values


@dataclass
class Config:
    model: str = "auto"
    max_duration: int = 10800
    min_free_disk_mb: int = 500
    target_loudness: str = "-18"
    language: str = "en"
    max_retries: int = 3
    retry_backoff_base: int = 5
    retry_backoff_multiplier: int = 2
    enable_crash_recovery: str = "true"
    auto_cleanup_temp: str = "true"
    auto_download_model: str = "true"
    model_base_url: str = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
    whisper_cmd: str = "auto"
    threads: str = "auto"
    fast_mode: str = "auto"
    whisper_speed_preset: str = "fast"
    whisper_args: str = ""
    ffmpeg_threads: str = "auto"
    stage2_max_duration: int = 0
    prefer_metal: str = "true"
    run_preflight: str = "false"
    ytdlp_format: str = "bestaudio"
    ytdlp_extra_args: str = "--extractor-args youtube:skip=dash"
    ytdlp_max_filesize: str = ""
    filter_stage1: str = "highpass=f=120, lowpass=f=3800, dynaudnorm=p=0.8:m=10, volume={gain:.1f}dB"
    filter_stage2: str = "highpass=f=120, lowpass=f=4200, dynaudnorm=p=0.9:m=12, volume={gain:.1f}dB"

    @classmethod
    def load(cls, path: Path) -> "Config":
        raw = read_conf(path)
        
        def get(k: str, default: Any) -> Any:
            return raw.get(k, default)
            
        def get_int(k: str, default: int) -> int:
            return int(raw.get(k, default))

        return cls(
            model=get("MODEL", "auto") or "auto",
            max_duration=get_int("MAX_DURATION", 10800),
            min_free_disk_mb=get_int("MIN_FREE_DISK_MB", 500),
            target_loudness=get("TARGET_LOUDNESS", "-18"),
            language=get("LANGUAGE", "en"),
            max_retries=get_int("MAX_RETRIES", 3),
            retry_backoff_base=get_int("RETRY_BACKOFF_BASE", 5),
            retry_backoff_multiplier=get_int("RETRY_BACKOFF_MULTIPLIER", 2),
            enable_crash_recovery=get("ENABLE_CRASH_RECOVERY", "true"),
            auto_cleanup_temp=get("AUTO_CLEANUP_TEMP", "true"),
            auto_download_model=get("AUTO_DOWNLOAD_MODEL", "true"),
            model_base_url=get("MODEL_BASE_URL", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"),
            whisper_cmd=get("WHISPER_CMD", "auto"),
            threads=get("THREADS", "auto"),
            fast_mode=get("FAST_MODE", "auto"),
            whisper_speed_preset=get("WHISPER_SPEED_PRESET", "fast"),
            whisper_args=get("WHISPER_ARGS", ""),
            ffmpeg_threads=get("FFMPEG_THREADS", "auto"),
            stage2_max_duration=get_int("STAGE2_MAX_DURATION", 0),
            prefer_metal=get("PREFER_METAL", "true"),
            run_preflight=get("RUN_PREFLIGHT", "false"),
            ytdlp_format=get("YTDLP_FORMAT", "bestaudio"),
            ytdlp_extra_args=get("YTDLP_EXTRA_ARGS", "--extractor-args youtube:skip=dash"),
            ytdlp_max_filesize=get("YTDLP_MAX_FILESIZE", ""),
            filter_stage1=get("FILTER_STAGE1", "highpass=f=120, lowpass=f=3800, dynaudnorm=p=0.8:m=10, volume={gain:.1f}dB"),
            filter_stage2=get("FILTER_STAGE2", "highpass=f=120, lowpass=f=4200, dynaudnorm=p=0.9:m=12, volume={gain:.1f}dB"),
        )
