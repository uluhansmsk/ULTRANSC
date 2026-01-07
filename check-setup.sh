#!/usr/bin/env bash
# ULTRANSC v0.5 Installation Validator
# Run this to check if your system is ready

set -euo pipefail

echo "================================================"
echo "  ULTRANSC v0.5 Installation Validator"
echo "================================================"
echo

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

ERRORS=0
WARNINGS=0

check_command() {
    local cmd="$1"
    local required="$2"
    
    if command -v "$cmd" &>/dev/null; then
        echo "✅ $cmd: $(command -v "$cmd")"
        return 0
    else
        if [ "$required" = "yes" ]; then
            echo "❌ $cmd: NOT FOUND (REQUIRED)"
            ((ERRORS++))
        else
            echo "⚠️  $cmd: NOT FOUND (optional)"
            ((WARNINGS++))
        fi
        return 1
    fi
}

check_file() {
    local file="$1"
    local required="$2"
    
    if [ -f "$file" ]; then
        echo "✅ $file: EXISTS"
        return 0
    else
        if [ "$required" = "yes" ]; then
            echo "❌ $file: MISSING (REQUIRED)"
            ((ERRORS++))
        else
            echo "⚠️  $file: MISSING (optional)"
            ((WARNINGS++))
        fi
        return 1
    fi
}

check_dir() {
    local dir="$1"
    
    if [ -d "$dir" ]; then
        echo "✅ $dir/: EXISTS"
        return 0
    else
        echo "⚠️  $dir/: MISSING (will be created)"
        ((WARNINGS++))
        return 1
    fi
}

echo "=== Checking System Requirements ==="
echo

check_command "bash" "yes"
check_command "ffmpeg" "yes"
check_command "whisper-cli" "yes"
check_command "curl" "yes"
check_command "bc" "no"
check_command "jq" "no"

echo
echo "=== Checking ULTRANSC Structure ==="
echo

check_file "ultransc.sh" "yes"
check_file "ice.sh" "no"
check_file "config/default.conf" "yes"

echo
echo "=== Checking Directories ==="
echo

check_dir "queue/incoming"
check_dir "queue/processing"
check_dir "queue/done"
check_dir "models"
check_dir "workspace"
check_dir "logs"
check_dir "bin"

echo
echo "=== Checking Whisper Models ==="
echo

MODEL_COUNT=$(find models/ -name "*.bin" 2>/dev/null | wc -l | tr -d ' ')

if [ "$MODEL_COUNT" -gt 0 ]; then
    echo "✅ Found $MODEL_COUNT model(s):"
    for model in models/*.bin; do
        if [ -f "$model" ]; then
            size=$(du -h "$model" | cut -f1)
            echo "   - $(basename "$model") ($size)"
        fi
    done
else
    echo "❌ No models found in models/"
    echo "   Download a model:"
    echo "   curl -L https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin -o models/ggml-medium.en.bin"
    ((ERRORS++))
fi

echo
echo "=== Checking Configuration ==="
echo

if [ -f "config/default.conf" ]; then
    echo "✅ Configuration file exists"
    
    # Check for key settings
    if grep -q "MODEL=" config/default.conf; then
        MODEL_SETTING=$(grep "^MODEL=" config/default.conf | cut -d= -f2)
        echo "   MODEL: $MODEL_SETTING"
    fi
    
    if grep -q "ENABLE_CHUNKING=" config/default.conf; then
        CHUNK_SETTING=$(grep "^ENABLE_CHUNKING=" config/default.conf | cut -d= -f2)
        echo "   ENABLE_CHUNKING: $CHUNK_SETTING"
    fi
    
    if grep -q "ENABLE_CRASH_RECOVERY=" config/default.conf; then
        RECOVERY_SETTING=$(grep "^ENABLE_CRASH_RECOVERY=" config/default.conf | cut -d= -f2)
        echo "   ENABLE_CRASH_RECOVERY: $RECOVERY_SETTING"
    fi
fi

echo
echo "=== Checking System Resources ==="
echo

OS=$(uname -s)
echo "Operating System: $OS"

if [ "$OS" = "Darwin" ]; then
    RAM_GB=$(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024))
    CPU_CORES=$(sysctl -n hw.ncpu)
elif [ "$OS" = "Linux" ]; then
    RAM_GB=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024))
    CPU_CORES=$(nproc)
else
    echo "⚠️  Unknown OS: $OS"
    RAM_GB=0
    CPU_CORES=0
fi

echo "RAM: ${RAM_GB}GB"
echo "CPU Cores: $CPU_CORES"

if [ "$RAM_GB" -lt 4 ]; then
    echo "⚠️  Low RAM (<4GB) — recommend small model only"
    ((WARNINGS++))
fi

FREE_GB=$(df -Pk "$ROOT_DIR" | awk 'NR==2 {print int($4/1024/1024)}')
echo "Free Disk Space: ${FREE_GB}GB"

if [ "$FREE_GB" -lt 5 ]; then
    echo "⚠️  Low disk space (<5GB) — may have issues with large files"
    ((WARNINGS++))
fi

echo
echo "=== Checking Permissions ==="
echo

if [ -x "ultransc.sh" ]; then
    echo "✅ ultransc.sh is executable"
else
    echo "⚠️  ultransc.sh not executable"
    echo "   Run: chmod +x ultransc.sh"
    ((WARNINGS++))
fi

if touch ".write_test" 2>/dev/null; then
    echo "✅ Directory is writable"
    rm -f ".write_test"
else
    echo "❌ Directory not writable"
    ((ERRORS++))
fi

echo
echo "=== Validation Summary ==="
echo

if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo "🎉 Perfect! ULTRANSC is ready to use."
    echo
    echo "Quick start:"
    echo "  1. cp your_file.mp4 queue/incoming/"
    echo "  2. ./ultransc.sh"
    echo "  3. Check workspace/ for results"
    echo
    exit 0
elif [ "$ERRORS" -eq 0 ]; then
    echo "⚠️  Setup complete with $WARNINGS warning(s)"
    echo "   ULTRANSC should work, but review warnings above."
    echo
    exit 0
else
    echo "❌ Setup incomplete: $ERRORS error(s), $WARNINGS warning(s)"
    echo "   Fix errors above before running ULTRANSC."
    echo
    exit 1
fi
