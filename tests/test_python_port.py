from __future__ import annotations

import os
import tempfile
import textwrap
import unittest
from pathlib import Path
from unittest.mock import patch

from ultransc.core import App, _read_conf


def write_exe(path: Path, body: str) -> None:
    path.write_text("#!/usr/bin/env bash\n" + body, encoding="utf-8")
    path.chmod(0o755)


class PythonPortTests(unittest.TestCase):
    def make_root(self) -> Path:
        root = Path(tempfile.mkdtemp(prefix="ultransc-test-"))
        (root / "config").mkdir()
        (root / "config" / "default.conf").write_text(
            textwrap.dedent(
                """
                MODEL=auto
                AUTO_DOWNLOAD_MODEL=false
                MAX_DURATION=10800
                MIN_FREE_DISK_MB=1
                TARGET_LOUDNESS=-18
                FAST_MODE=true
                THREADS=auto
                FFMPEG_THREADS=auto
                WHISPER_SPEED_PRESET=fast
                """
            ).strip()
            + "\n",
            encoding="utf-8",
        )
        return root

    def install_fake_media_tools(self, root: Path, duration: int = 42) -> Path:
        fake_bin = root / "fake-bin"
        fake_bin.mkdir()
        write_exe(fake_bin / "ffprobe", f"echo {duration}\n")
        write_exe(
            fake_bin / "ffmpeg",
            textwrap.dedent(
                """
                if printf '%s\n' "$@" | grep -q volumedetect; then
                    echo 'mean_volume: -30.0 dB' >&2
                    exit 0
                fi
                out=''
                prev=''
                for arg in "$@"; do
                    if [ "$arg" = "-y" ]; then
                        break
                    fi
                    out="$arg"
                    prev="$arg"
                done
                mkdir -p "$(dirname "$out")"
                printf wav > "$out"
                """
            ),
        )
        write_exe(
            fake_bin / "whisper-cli",
            textwrap.dedent(
                """
                out=''
                while [ $# -gt 0 ]; do
                    if [ "$1" = "--output-file" ]; then
                        shift
                        out="$1"
                        break
                    fi
                    shift
                done
                printf 'hello world\n' > "${out}.txt"
                printf '{"segments":[]}\n' > "${out}.json"
                printf '1\n00:00:00,000 --> 00:00:01,000\nhello world\n' > "${out}.srt"
                """
            ),
        )
        return fake_bin

    def test_config_parser_strips_comments(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            conf = Path(tmp) / "default.conf"
            conf.write_text("MODEL=auto # comment\nWHISPER_ARGS= --foo bar\n", encoding="utf-8")
            self.assertEqual(_read_conf(conf)["MODEL"], "auto")
            self.assertEqual(_read_conf(conf)["WHISPER_ARGS"], "--foo bar")

    def test_process_file_success_matches_queue_contract(self) -> None:
        root = self.make_root()
        fake_bin = self.install_fake_media_tools(root)
        app = App(root)
        app.init_folders()
        (app.paths.models / "ggml-small.en.bin").write_text("model", encoding="utf-8")
        app.cpu_cores = 2
        app.threads_value = "2"
        app.ffmpeg_threads_value = "2"
        app.fast_mode_value = "true"
        app.whisper_bin = "whisper-cli"
        app.model = "ggml-small.en.bin"
        source = app.paths.incoming / "Lecture File.mp4"
        source.write_text("media", encoding="utf-8")
        with patch.dict(os.environ, {"PATH": f"{fake_bin}:{os.environ.get('PATH', '')}"}):
            self.assertTrue(app.process_file(source))
        self.assertFalse(source.exists())
        self.assertTrue((app.paths.done / "Lecture File.mp4").exists())
        jobs = list(app.paths.workspace.glob("Lecture_File_*"))
        self.assertEqual(len(jobs), 1)
        self.assertTrue((jobs[0] / "raw_input").exists())
        self.assertTrue((jobs[0] / "transcript.txt").exists())
        self.assertTrue((jobs[0] / "transcript.json").exists())
        self.assertTrue((jobs[0] / "transcript.srt").exists())
        self.assertTrue((jobs[0] / "segments.json").is_symlink())

    def test_too_long_file_moves_to_failed_but_batch_continues(self) -> None:
        root = self.make_root()
        fake_bin = self.install_fake_media_tools(root, duration=20000)
        app = App(root)
        app.init_folders()
        source = app.paths.incoming / "too-long.mp4"
        source.write_text("media", encoding="utf-8")
        with patch.dict(os.environ, {"PATH": f"{fake_bin}:{os.environ.get('PATH', '')}"}):
            self.assertTrue(app.process_file(source))
        self.assertTrue((app.paths.failed / "too-long.mp4").exists())

    def test_failed_url_download_is_preserved_for_retry(self) -> None:
        root = self.make_root()
        app = App(root)
        app.init_folders()
        write_exe(app.paths.bin / "yt-dlp", "exit 1\n")
        app.paths.links.write_text("https://example.test/video\n", encoding="utf-8")
        app.process_url_queue()
        self.assertEqual(app.paths.links.read_text(encoding="utf-8"), "https://example.test/video\n")


if __name__ == "__main__":
    unittest.main()
