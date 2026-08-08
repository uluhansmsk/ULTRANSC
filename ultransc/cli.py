from __future__ import annotations

from pathlib import Path

from .core import run_pipeline


def main() -> int:
    return run_pipeline(Path(__file__).resolve().parents[1])
