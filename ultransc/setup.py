from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from urllib.request import urlretrieve


def info(message: str) -> None:
    print(f"[setup] {message}")


def warn(message: str) -> None:
    print(f"[setup][warn] {message}")


def ensure_dirs(root: Path) -> None:
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


def install_deps() -> None:
    os_name = os.uname().sysname
    if os_name == "Darwin":
        if not shutil.which("brew"):
            warn("Homebrew not found. Install Homebrew first, then run: brew install ffmpeg whisper-cpp")
            return
        info("Installing dependencies with Homebrew...")
        subprocess.run(["brew", "install", "ffmpeg", "whisper-cpp"], check=False)
    elif os_name == "Linux":
        if shutil.which("apt-get"):
            info("Installing dependencies with apt (sudo required)...")
            subprocess.run(["sudo", "apt-get", "update"], check=True)
            subprocess.run(["sudo", "apt-get", "install", "-y", "ffmpeg", "curl", "ca-certificates", "build-essential", "cmake", "git"], check=True)
        elif shutil.which("dnf"):
            info("Installing dependencies with dnf (sudo required)...")
            subprocess.run(["sudo", "dnf", "install", "-y", "ffmpeg", "curl", "ca-certificates", "gcc-c++", "cmake", "git", "make"], check=True)
        elif shutil.which("pacman"):
            info("Installing dependencies with pacman (sudo required)...")
            subprocess.run(["sudo", "pacman", "-Sy", "--noconfirm", "ffmpeg", "curl", "base-devel", "cmake", "git"], check=True)
        else:
            warn("No supported package manager detected. Install ffmpeg, ffprobe, curl, cmake, and build tools manually.")


def build_local_whisper_if_missing(root: Path) -> None:
    if shutil.which("whisper-cli") or shutil.which("whisper-cpp") or (root / "bin" / "whisper-cli").exists():
        info("Whisper command already available.")
        return
    info("Building local whisper.cpp binary into bin/...")
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "whisper.cpp"
        subprocess.run(["git", "clone", "--depth", "1", "https://github.com/ggerganov/whisper.cpp", str(src)], check=True)
        subprocess.run(["cmake", "-S", str(src), "-B", str(src / "build"), "-DBUILD_SHARED_LIBS=OFF"], check=True)
        subprocess.run(["cmake", "--build", str(src / "build"), "-j"], check=True)
        built = src / "build" / "bin" / "whisper-cli"
        if built.exists():
            target = root / "bin" / "whisper-cli"
            shutil.copy2(built, target)
            target.chmod(0o755)
            info("Installed local bin/whisper-cli")
        else:
            warn("whisper-cli build output not found. Install whisper.cpp manually.")


def download_default_model_if_missing(root: Path) -> None:
    models = root / "models"
    if any(models.glob("*.bin")):
        info("Model already present in models/.")
        return
    info("Downloading default model ggml-medium.en.bin...")
    urlretrieve(
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin",
        models / "ggml-medium.en.bin",
    )


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    ensure_dirs(root)
    install_deps()
    build_local_whisper_if_missing(root)
    download_default_model_if_missing(root)
    for rel in ("ultransc.sh", "ice.sh", "check-setup.sh"):
        path = root / rel
        if path.exists():
            path.chmod(path.stat().st_mode | 0o111)
    info("Running setup validation...")
    from .preflight import main as preflight_main
    from .check_setup import main as check_setup_main

    if preflight_main() != 0:
        return 1
    previous = os.environ.get("ULTRANSC_SKIP_PREFLIGHT")
    os.environ["ULTRANSC_SKIP_PREFLIGHT"] = "1"
    try:
        if check_setup_main() != 0:
            return 1
    finally:
        if previous is None:
            os.environ.pop("ULTRANSC_SKIP_PREFLIGHT", None)
        else:
            os.environ["ULTRANSC_SKIP_PREFLIGHT"] = previous
    info("Setup complete. Run ./ultransc.sh to start processing.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
