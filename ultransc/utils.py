import shutil
import subprocess
import json
from pathlib import Path
from typing import List, Optional
from urllib.request import Request, urlopen
from urllib.error import URLError

def free_mb(path: Path) -> int:
    usage = shutil.disk_usage(path)
    return int(usage.free / 1024 / 1024)

def move_replace(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() or dst.is_symlink():
        if dst.is_dir() and not dst.is_symlink():
            shutil.rmtree(dst)
        else:
            dst.unlink()
    shutil.move(str(src), str(dst))

def is_queue_artifact(path: Path) -> bool:
    return path.name.startswith(".") or path.name.endswith((".part", ".ytdl", ".temp", ".tmp"))

def cleanup_download_attempt(directory: Path, stem: str) -> None:
    for path in directory.glob(f"{stem}*"):
        if path.is_file() or path.is_symlink():
            path.unlink()

def run_cmd(args: List[str], timeout: Optional[int] = None, capture: bool = False) -> subprocess.CompletedProcess:
    kwargs = {
        "text": True,
        "timeout": timeout,
    }
    if capture:
        kwargs.update({"stdout": subprocess.PIPE, "stderr": subprocess.PIPE})
    return subprocess.run(args, **kwargs)

def notify_webhook(url: str, message: str) -> None:
    if not url:
        return
    try:
        data = json.dumps({"content": message, "text": message}).encode("utf-8")
        req = Request(url, data=data, headers={'Content-Type': 'application/json', 'User-Agent': 'ULTRANSC/1.0'})
        with urlopen(req, timeout=10):
            pass
    except (URLError, OSError):
        pass
