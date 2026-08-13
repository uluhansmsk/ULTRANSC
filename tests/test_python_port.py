from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path
from unittest.mock import patch

from ultransc.cli import main as cli_main
from ultransc.core import App, _read_conf, run_pipeline
from ultransc.ice import main as ice_main


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

    def install_fake_media_tools(self, root: Path, duration: int = 42, whisper_sidecars: bool = True) -> Path:
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
                if [ "%s" = "true" ]; then
                    printf '{"segments":[]}\n' > "${out}.json"
                    printf '1\n00:00:00,000 --> 00:00:01,000\nhello world\n' > "${out}.srt"
                fi
                """
            )
            % ("true" if whisper_sidecars else "false"),
        )
        return fake_bin

    def test_config_parser_strips_comments(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            conf = Path(tmp) / "default.conf"
            conf.write_text(
                "MODEL=auto # comment\nTARGET_LOUDNESS=\"-18\"\nWHISPER_ARGS='--prompt \"hello world\"'\n",
                encoding="utf-8",
            )
            self.assertEqual(_read_conf(conf)["MODEL"], "auto")
            self.assertEqual(_read_conf(conf)["TARGET_LOUDNESS"], "-18")
            self.assertEqual(_read_conf(conf)["WHISPER_ARGS"], '--prompt "hello world"')

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

    def test_missing_whisper_sidecar_fails_job_cleanly(self) -> None:
        root = self.make_root()
        fake_bin = self.install_fake_media_tools(root, whisper_sidecars=False)
        app = App(root)
        app.init_folders()
        (app.paths.models / "ggml-small.en.bin").write_text("model", encoding="utf-8")
        app.cpu_cores = 2
        app.threads_value = "2"
        app.ffmpeg_threads_value = "2"
        app.fast_mode_value = "true"
        app.whisper_bin = "whisper-cli"
        app.model = "ggml-small.en.bin"
        source = app.paths.incoming / "missing-sidecar.mp4"
        source.write_text("media", encoding="utf-8")
        with patch.dict(os.environ, {"PATH": f"{fake_bin}:{os.environ.get('PATH', '')}"}):
            self.assertFalse(app.process_file(source))
        self.assertTrue((app.paths.failed / "missing-sidecar.mp4").exists())

    def test_stage2_runs_when_blank_ratio_is_high(self) -> None:
        root = self.make_root()
        app = App(root)
        app.init_folders()
        (app.paths.models / "ggml-small.en.bin").write_text("model", encoding="utf-8")
        app.threads_value = "2"
        app.ffmpeg_threads_value = "2"
        app.fast_mode_value = "false"
        app.whisper_bin = "whisper-cli"
        app.model = "ggml-small.en.bin"
        source = app.paths.incoming / "blank-heavy.mp4"
        source.write_text("media", encoding="utf-8")
        conversions = []
        whispers = []

        def fake_convert(input_file: Path, output: Path, audio_filter: str, tag: str) -> bool:
            conversions.append(tag)
            output.write_text("wav", encoding="utf-8")
            return True

        def fake_whisper(wav: Path, out: Path) -> bool:
            whispers.append(out.name)
            if out.name == "transcript_stage1":
                text = "\n".join(["[BLANK_AUDIO]"] * 4 + ["audible speech"])
            else:
                text = "stage two recovered speech"
            out.with_suffix(".txt").write_text(text + "\n", encoding="utf-8")
            out.with_suffix(".json").write_text('{"segments":[]}\n', encoding="utf-8")
            out.with_suffix(".srt").write_text("1\n00:00:00,000 --> 00:00:01,000\nspeech\n", encoding="utf-8")
            return True

        with patch.object(app, "_duration", return_value=42):
            with patch.object(app, "get_mean_volume", return_value="-30.0"):
                with patch.object(app, "convert_with_filter", side_effect=fake_convert):
                    with patch.object(app, "run_whisper", side_effect=fake_whisper):
                        self.assertTrue(app.process_file(source))
        jobs = list(app.paths.workspace.glob("blank-heavy_*"))
        self.assertEqual(conversions, ["Stage 1", "Stage 2"])
        self.assertEqual(whispers, ["transcript_stage1", "transcript"])
        self.assertEqual((jobs[0] / "transcript.txt").read_text(encoding="utf-8"), "stage two recovered speech\n")

    def test_failed_url_download_is_preserved_for_retry(self) -> None:
        root = self.make_root()
        app = App(root)
        app.init_folders()
        write_exe(app.paths.bin / "yt-dlp", "exit 1\n")
        app.paths.links.write_text("https://example.test/video\n", encoding="utf-8")
        app.process_url_queue()
        self.assertEqual(app.paths.links.read_text(encoding="utf-8"), "https://example.test/video\n")

    def test_successful_url_download_uses_audio_format_and_detects_extension(self) -> None:
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
        write_exe(
            app.paths.bin / "yt-dlp",
            textwrap.dedent(
                """
                out=''
                format=''
                extractor_args=''
                while [ $# -gt 0 ]; do
                    case "$1" in
                        --extractor-args)
                            shift
                            extractor_args="$1"
                            ;;
                        -f)
                            shift
                            format="$1"
                            ;;
                        -o)
                            shift
                            out="$1"
                            ;;
                    esac
                    shift
                done
                test "$format" = "bestaudio" || exit 2
                test "$extractor_args" = "youtube:skip=dash" || exit 3
                out="${out//%(ext)s/webm}"
                mkdir -p "$(dirname "$out")"
                printf media > "$out"
                """
            ),
        )
        app.paths.links.write_text("https://example.test/video\n", encoding="utf-8")
        with patch.dict(os.environ, {"PATH": f"{fake_bin}:{os.environ.get('PATH', '')}"}):
            app.process_url_queue()
        self.assertEqual(app.paths.links.read_text(encoding="utf-8"), "")
        self.assertTrue(any(app.paths.done.glob("download_*.webm")))

    def test_interrupted_url_download_preserves_queue_and_cleans_partials(self) -> None:
        root = self.make_root()
        app = App(root)
        app.init_folders()
        app.paths.links.write_text("https://example.test/current\nhttps://example.test/next\n", encoding="utf-8")
        with patch("ultransc.core._run", side_effect=KeyboardInterrupt):
            with self.assertRaises(SystemExit) as raised:
                app.process_url_queue()
        self.assertEqual(raised.exception.code, 130)
        self.assertEqual(
            app.paths.links.read_text(encoding="utf-8"),
            "https://example.test/current\nhttps://example.test/next\n",
        )
        self.assertFalse(list(app.paths.incoming.glob("download_*")))

    def test_queue_metadata_files_are_ignored(self) -> None:
        root = self.make_root()
        app = App(root)
        app.init_folders()
        (app.paths.incoming / ".DS_Store").write_text("metadata", encoding="utf-8")
        (app.paths.incoming / "download_123.mp4.part").write_text("partial", encoding="utf-8")
        (app.paths.incoming / "download_123.mp4.ytdl").write_text("state", encoding="utf-8")
        app.process_incoming_queue()
        self.assertFalse((app.paths.incoming / ".DS_Store").exists())
        self.assertFalse((app.paths.incoming / "download_123.mp4.part").exists())
        self.assertFalse((app.paths.incoming / "download_123.mp4.ytdl").exists())

    def test_active_lock_exits_without_removing_lock(self) -> None:
        root = self.make_root()
        app = App(root)
        app.init_folders()
        app.paths.lock_dir.mkdir()
        (app.paths.lock_dir / "pid").write_text(str(os.getpid()), encoding="utf-8")
        with self.assertRaises(SystemExit) as raised:
            app.acquire_lock()
        self.assertEqual(raised.exception.code, 1)
        self.assertTrue(app.paths.lock_dir.exists())

    def test_cli_preflight_flags_override_config_default(self) -> None:
        root = self.make_root()
        with patch("ultransc.cli.run_pipeline", return_value=0) as pipeline:
            self.assertEqual(cli_main(["--root", str(root), "--preflight"]), 0)
        pipeline.assert_called_once_with(root, preflight=True)

        with patch("ultransc.cli.run_pipeline", return_value=0) as pipeline:
            self.assertEqual(cli_main(["--root", str(root), "--no-preflight"]), 0)
        pipeline.assert_called_once_with(root, preflight=False)

    def test_run_pipeline_skips_preflight_by_default(self) -> None:
        root = self.make_root()
        with patch("ultransc.core.run_preflight") as preflight:
            with patch.object(App, "check_environment"), patch.object(App, "init_whisper"), patch.object(App, "init_model"), patch.object(App, "clean_incomplete_jobs"), patch.object(App, "run_queue"):
                self.assertEqual(run_pipeline(root), 0)
        preflight.assert_not_called()

    def test_run_pipeline_honors_preflight_env_opt_in(self) -> None:
        root = self.make_root()
        with patch("ultransc.core.run_preflight") as preflight:
            with patch.dict(os.environ, {"ULTRANSC_RUN_PREFLIGHT": "1"}):
                with patch.object(App, "check_environment"), patch.object(App, "init_whisper"), patch.object(App, "init_model"), patch.object(App, "clean_incomplete_jobs"), patch.object(App, "run_queue"):
                    self.assertEqual(run_pipeline(root), 0)
        preflight.assert_called_once()

    def test_ice_uses_regex_for_patterns_and_keywords(self) -> None:
        root = self.make_root()
        job = root / "workspace" / "lecture_A"
        job.mkdir(parents=True)
        (job / "transcript.txt").write_text("foo bar\n", encoding="utf-8")
        with patch("builtins.input", return_value="s"):
            self.assertEqual(ice_main(["lecture_[A-Z]", "--", "foo|bar"], root=root), 0)

    def test_generated_audio_smoke_uses_real_ffmpeg_when_available(self) -> None:
        if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
            self.skipTest("ffmpeg/ffprobe not available")
        root = self.make_root()
        fake_bin = root / "fake-bin"
        fake_bin.mkdir()
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
                printf 'generated audio smoke\n' > "${out}.txt"
                printf '{"segments":[]}\n' > "${out}.json"
                printf '1\n00:00:00,000 --> 00:00:01,000\ngenerated audio smoke\n' > "${out}.srt"
                """
            ),
        )
        app = App(root)
        app.init_folders()
        (app.paths.models / "ggml-small.en.bin").write_text("model", encoding="utf-8")
        app.threads_value = "1"
        app.ffmpeg_threads_value = "1"
        app.fast_mode_value = "true"
        app.whisper_bin = "whisper-cli"
        app.model = "ggml-small.en.bin"
        source = app.paths.incoming / "generated.wav"
        subprocess.run(
            [
                "ffmpeg",
                "-f",
                "lavfi",
                "-i",
                "sine=frequency=440:duration=0.25",
                "-ar",
                "16000",
                "-ac",
                "1",
                str(source),
                "-y",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        with patch.dict(os.environ, {"PATH": f"{fake_bin}:{os.environ.get('PATH', '')}"}):
            self.assertTrue(app.process_file(source))
        jobs = list(app.paths.workspace.glob("generated_*"))
        self.assertEqual((jobs[0] / "transcript.txt").read_text(encoding="utf-8"), "generated audio smoke\n")


if __name__ == "__main__":
    unittest.main()
