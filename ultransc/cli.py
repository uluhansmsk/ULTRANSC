from __future__ import annotations

import argparse
from pathlib import Path

from .core import run_pipeline


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Run the ULTRANSC local transcription queue.")
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Repository/runtime root containing config, queue, models, logs, and workspace.",
    )
    preflight = parser.add_mutually_exclusive_group()
    preflight.add_argument("--preflight", action="store_true", help="Run preflight checks before processing.")
    preflight.add_argument("--no-preflight", action="store_true", help="Skip preflight even if config enables it.")
    args = parser.parse_args(argv)

    preflight_value = None
    if args.preflight:
        preflight_value = True
    elif args.no_preflight:
        preflight_value = False
    return run_pipeline(args.root, preflight=preflight_value)
