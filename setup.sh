#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

OS="$(uname -s)"

info() {
    echo "[setup] $*"
}

warn() {
    echo "[setup][warn] $*"
}

ensure_dirs() {
    mkdir -p queue/incoming queue/processing queue/done queue/failed
    mkdir -p models bin logs workspace config
    touch queue/links.txt logs/system.log logs/errors.log
}

install_macos_deps() {
    if ! command -v brew >/dev/null 2>&1; then
        warn "Homebrew not found. Install Homebrew first, then run: brew install ffmpeg whisper-cpp"
        return
    fi

    info "Installing dependencies with Homebrew..."
    brew install ffmpeg whisper-cpp || true
}

install_linux_deps() {
    if command -v apt-get >/dev/null 2>&1; then
        info "Installing dependencies with apt (sudo required)..."
        sudo apt-get update
        sudo apt-get install -y ffmpeg curl ca-certificates build-essential cmake git
    elif command -v dnf >/dev/null 2>&1; then
        info "Installing dependencies with dnf (sudo required)..."
        sudo dnf install -y ffmpeg curl ca-certificates gcc-c++ cmake git make
    elif command -v pacman >/dev/null 2>&1; then
        info "Installing dependencies with pacman (sudo required)..."
        sudo pacman -Sy --noconfirm ffmpeg curl base-devel cmake git
    else
        warn "No supported package manager detected. Install ffmpeg, ffprobe, curl, cmake, and build tools manually."
    fi
}

build_local_whisper_if_missing() {
    if command -v whisper-cli >/dev/null 2>&1 || command -v whisper-cpp >/dev/null 2>&1 || [ -x "bin/whisper-cli" ]; then
        info "Whisper command already available."
        return
    fi

    info "Building local whisper.cpp binary into bin/..."
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT

    git clone --depth 1 https://github.com/ggerganov/whisper.cpp "$tmp_dir/whisper.cpp"
    cmake -S "$tmp_dir/whisper.cpp" -B "$tmp_dir/whisper.cpp/build" -DBUILD_SHARED_LIBS=OFF
    cmake --build "$tmp_dir/whisper.cpp/build" -j

    if [ -x "$tmp_dir/whisper.cpp/build/bin/whisper-cli" ]; then
        cp "$tmp_dir/whisper.cpp/build/bin/whisper-cli" "bin/whisper-cli"
        chmod +x "bin/whisper-cli"
        info "Installed local bin/whisper-cli"
    else
        warn "whisper-cli build output not found. Install whisper.cpp manually."
    fi
}

download_default_model_if_missing() {
    if find models -maxdepth 1 -name '*.bin' | grep -q .; then
        info "Model already present in models/."
        return
    fi

    info "Downloading default model ggml-medium.en.bin..."
    curl -fL https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin \
        -o models/ggml-medium.en.bin
}

ensure_dirs

case "$OS" in
    Darwin)
        install_macos_deps
        ;;
    Linux)
        install_linux_deps
        ;;
    *)
        warn "Unsupported OS: $OS"
        ;;
esac

build_local_whisper_if_missing
download_default_model_if_missing

chmod +x ultransc.sh ice.sh check-setup.sh

info "Running setup validation..."
bash check-setup.sh

info "Setup complete. Run ./ultransc.sh to start processing."
