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
    parser.add_argument("--status", action="store_true", help="Display current queue status, models, and system info.")
    parser.add_argument(
        "--clean",
        nargs="?",
        const="done",
        choices=["done", "failed", "all"],
        help="Clean finished/failed queue items (default: done).",
    )
    parser.add_argument(
        "-w", "--watch",
        action="store_true",
        help="Run in continuous watch/daemon mode, checking for new queue items periodically.",
    )
    parser.add_argument(
        "--interval",
        type=int,
        default=5,
        help="Polling interval in seconds when using --watch mode (default: 5s).",
    )
    parser.add_argument("--model", type=str, default=None, help="Override transcription model (e.g. ggml-medium.en.bin).")
    parser.add_argument("--language", "--lang", type=str, default=None, dest="language", help="Override transcription language (e.g. en, tr).")
    parser.add_argument("--concurrency", "-c", type=int, default=None, help="Override maximum concurrent processing jobs.")
    parser.add_argument("--webhook", type=str, default=None, help="Override Discord/Slack notification webhook URL.")
    
    fast_group = parser.add_mutually_exclusive_group()
    fast_group.add_argument("--fast", action="store_true", default=None, help="Enable fast mode (skip Stage 2 audio recovery).")
    fast_group.add_argument("--no-fast", action="store_false", dest="fast", help="Disable fast mode.")

    preflight = parser.add_mutually_exclusive_group()
    preflight.add_argument("--preflight", action="store_true", help="Run preflight checks before processing.")
    preflight.add_argument("--no-preflight", action="store_true", help="Skip preflight even if config enables it.")
    
    args = parser.parse_args(argv)

    config_overrides = {}
    if args.model:
        config_overrides["model"] = args.model
    if args.language:
        config_overrides["language"] = args.language
    if args.concurrency is not None:
        config_overrides["max_concurrent_jobs"] = args.concurrency
    if args.webhook:
        config_overrides["webhook_url"] = args.webhook
    if args.fast is not None:
        config_overrides["fast_mode"] = "true" if args.fast else "false"

    preflight_value = None
    if args.preflight:
        preflight_value = True
    elif args.no_preflight:
        preflight_value = False

    return run_pipeline(
        root=args.root,
        preflight=preflight_value,
        config_overrides=config_overrides,
        status=args.status,
        clean=args.clean,
        watch=args.watch,
        watch_interval=args.interval,
    )
