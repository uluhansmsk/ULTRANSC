from __future__ import annotations

import re
import sys
from pathlib import Path


DEFAULT_BEFORE = 5
DEFAULT_AFTER = 5
SIM_THRESHOLD = 80


def similarity(a: str, b: str) -> int:
    max_len = max(len(a), len(b))
    if max_len == 0:
        return 0
    same = sum(1 for left, right in zip(a, b) if left == right)
    return int(100 * same / max_len)


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if len(argv) < 3 or "--" not in argv:
        print("Usage: ice.sh <lecture-pattern...> -- <keyword...>")
        return 1
    sep = argv.index("--")
    patterns = argv[:sep]
    keywords = argv[sep + 1 :]
    root = Path(__file__).resolve().parents[1]
    workspace = root / "workspace"
    block_dir = root / "blocks"
    block_dir.mkdir(exist_ok=True)
    if not workspace.is_dir():
        print(f"ERROR: workspace/ not found in {root}")
        return 1
    print("[INFO] Searching transcripts...")
    search_regex = ".*".join(re.escape(part) for part in patterns)
    matched_file = None
    lecture_name = ""
    for job_path in workspace.iterdir():
        if not job_path.is_dir():
            continue
        if re.search(search_regex, job_path.name):
            transcript = job_path / "transcript.txt"
            if transcript.exists():
                matched_file = transcript
                lecture_name = job_path.name
                break
    if not matched_file:
        print(f"ERROR: No transcript matches lecture pattern: {' '.join(patterns)}")
        return 1
    print(f"[INFO] Using transcript: {matched_file}")
    out_txt = block_dir / f"{lecture_name}.txt"
    out_md = block_dir / f"{lecture_name}.md"
    out_txt.touch(exist_ok=True)
    out_md.touch(exist_ok=True)
    lines = matched_file.read_text(encoding="utf-8", errors="replace").splitlines()
    for keyword in keywords:
        print()
        print(f"[INFO] Searching keyword: {keyword}")
        matches = [idx + 1 for idx, line in enumerate(lines) if keyword in line]
        if not matches:
            print(f"[WARN] No occurrences for keyword: {keyword}")
            continue
        for line_number in matches:
            before = DEFAULT_BEFORE
            after = DEFAULT_AFTER
            while True:
                start = max(line_number - before, 1)
                end = line_number + after
                block_content = "\n".join(lines[start - 1 : end])
                if out_txt.stat().st_size > 0:
                    existing = out_txt.read_text(encoding="utf-8", errors="replace")
                    score = similarity(existing, block_content)
                    if score >= SIM_THRESHOLD:
                        print(f"[SKIP] Block @ line {line_number} is {score}% similar to existing. Auto-skipped.")
                        break
                print()
                print(f"=== MATCH @{line_number} for \"{keyword}\" ===")
                print(f"----- Preview ({before}/{after}) -----")
                print(block_content)
                print("------------------------------------")
                print("[ENTER] accept")
                print("[w] widen")
                print("[n] narrow")
                print("[m] manual")
                print("[s] skip")
                print("[q] quit")
                choice = input("> ")
                if choice == "":
                    with out_txt.open("a", encoding="utf-8") as handle:
                        handle.write(f"===== {lecture_name} (line {line_number}) =====\n{block_content}\n\n")
                    with out_md.open("a", encoding="utf-8") as handle:
                        handle.write(f"## {lecture_name} - Line {line_number}\n\n```text\n{block_content}\n```\n\n")
                    print("[SAVED] Block added.")
                    break
                if choice == "w":
                    before += 3
                    after += 3
                elif choice == "n":
                    if before > 2 and after > 2:
                        before -= 2
                        after -= 2
                    else:
                        print("Can't narrow further.")
                elif choice == "m":
                    raw = input("Enter BEFORE AFTER: ")
                    parts = raw.split()
                    before, after = int(parts[0]), int(parts[1])
                elif choice == "s":
                    print("[SKIP] Block skipped.")
                    break
                elif choice == "q":
                    print("[QUIT]")
                    return 0
                else:
                    print("Invalid.")
    print()
    print("[DONE] All keywords processed.")
    print(f"[OUT] TXT -> {out_txt}")
    print(f"[OUT] MD  -> {out_md}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
