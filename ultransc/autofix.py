from __future__ import annotations

import os
import shutil
from pathlib import Path


def info(message: str) -> None:
    print(f"[AUTOFIX] {message}")


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    info("Ensuring directories")
    for rel in (
        "queue/incoming",
        "queue/processing",
        "queue/done",
        "queue/failed",
        "models",
        "bin",
        "logs",
        "workspace",
        "config",
    ):
        (root / rel).mkdir(parents=True, exist_ok=True)
    for rel in ("queue/links.txt", "logs/system.log", "logs/errors.log"):
        (root / rel).touch(exist_ok=True)
    info("Ensuring executable bits")
    for rel in ("ultransc.sh", "check-setup.sh", "setup.sh", "tests/run.sh", "tests/preflight.sh", "tests/autofix.sh"):
        path = root / rel
        if path.exists():
            path.chmod(path.stat().st_mode | 0o111)
    lock_dir = root / ".ultransc.lock"
    if lock_dir.is_dir():
        info("Removing stale lock")
        pid = lock_dir / "pid"
        if pid.exists():
            pid.unlink()
        try:
            lock_dir.rmdir()
        except OSError:
            pass
    info("Autofix complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
