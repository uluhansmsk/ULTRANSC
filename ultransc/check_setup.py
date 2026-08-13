from __future__ import annotations

import os
import platform
import shutil
from pathlib import Path

from .core import _read_conf


def _ok(message: str) -> None:
    print(f"[OK] {message}")


def _warn(message: str) -> None:
    print(f"[WARN] {message}")


def _err(message: str) -> None:
    print(f"[ERR] {message}")


def _has_any(root: Path, candidates) -> str:
    for candidate in candidates:
        path = root / candidate if "/" in candidate else None
        if path and path.exists() and os.access(path, os.X_OK):
            return candidate
        found = shutil.which(candidate)
        if found:
            return found
    return ""


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    if os.environ.get("ULTRANSC_SKIP_PREFLIGHT", "0") != "1":
        from .preflight import main as preflight_main

        if preflight_main() != 0:
            return 1

    print("================================================")
    print("  ULTRANSC v0.7.0-beta1 Installation Validator")
    print("================================================")
    print()

    errors = 0
    warnings = 0

    print("=== Checking System Requirements ===")
    for cmd, required in (("python3", True), ("ffmpeg", True), ("ffprobe", True), ("bash", False), ("curl", False), ("bc", False), ("jq", False)):
        found = shutil.which(cmd)
        if found:
            _ok(f"{cmd}: {found}")
        elif required:
            _err(f"{cmd}: NOT FOUND (REQUIRED)")
            errors += 1
        else:
            _warn(f"{cmd}: NOT FOUND (optional)")
            warnings += 1
    whisper = _has_any(root, ["bin/whisper-cli", "bin/whisper-cpp", "whisper-cli", "whisper-cpp", "whisper"])
    if whisper:
        _ok(f"whisper command: {whisper}")
    else:
        _err("whisper command: NOT FOUND")
        errors += 1

    print()
    print("=== Checking ULTRANSC Structure ===")
    for rel, required in (
        ("pyproject.toml", True),
        ("ultransc/core.py", True),
        ("ultransc/ice.py", True),
        ("ultransc/check_setup.py", True),
        ("ultransc.sh", False),
        ("ice.sh", False),
        ("config/default.conf", True),
    ):
        path = root / rel
        if path.exists():
            _ok(f"{rel}: EXISTS")
        elif required:
            _err(f"{rel}: MISSING (REQUIRED)")
            errors += 1
        else:
            _warn(f"{rel}: MISSING (optional)")
            warnings += 1

    print()
    print("=== Checking Directories ===")
    for rel in ("queue/incoming", "queue/processing", "queue/done", "queue/failed", "models", "workspace", "logs", "bin"):
        path = root / rel
        if path.is_dir():
            _ok(f"{rel}/: EXISTS")
        else:
            _warn(f"{rel}/: MISSING (will be created)")
            warnings += 1

    print()
    print("=== Checking Whisper Models ===")
    models_dir = root / "models"
    models = sorted(models_dir.glob("*.bin")) if models_dir.exists() else []
    if models:
        _ok(f"Found {len(models)} model(s):")
        for model in models:
            print(f"   - {model.name} ({model.stat().st_size // 1024}K)")
    else:
        _err("No models found in models/")
        print("   curl -L https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin -o models/ggml-medium.en.bin")
        errors += 1

    print()
    print("=== Checking Configuration ===")
    conf = _read_conf(root / "config" / "default.conf")
    if conf:
        _ok("Configuration file exists")
        for key in ("MODEL", "WHISPER_CMD", "ENABLE_CRASH_RECOVERY", "RUN_PREFLIGHT"):
            if key in conf:
                print(f"   {key}: {conf[key]}")

    print()
    print("=== Checking System Resources ===")
    os_name = platform.system()
    print(f"Operating System: {os_name}")
    print(f"CPU Cores: {os.cpu_count() or 1}")
    usage = shutil.disk_usage(root)
    free_gb = int(usage.free / 1024 / 1024 / 1024)
    print(f"Free Disk Space: {free_gb}GB")
    if free_gb < 5:
        _warn("Low disk space (<5GB) - may have issues with large files")
        warnings += 1

    print()
    print("=== Checking Permissions ===")
    if os.access(root / "ultransc.sh", os.X_OK):
        _ok("ultransc.sh is executable")
    else:
        _warn("ultransc.sh not executable")
        warnings += 1
    test_file = root / ".write_test"
    try:
        test_file.touch()
        _ok("Directory is writable")
    except OSError:
        _err("Directory not writable")
        errors += 1
    finally:
        if test_file.exists():
            test_file.unlink()

    print()
    print("=== Validation Summary ===")
    if errors == 0 and warnings == 0:
        print("Perfect! ULTRANSC is ready to use.")
        return 0
    if errors == 0:
        print(f"Setup complete with {warnings} warning(s)")
        return 0
    print(f"Setup incomplete: {errors} error(s), {warnings} warning(s)")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
