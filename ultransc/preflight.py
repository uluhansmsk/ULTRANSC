from __future__ import annotations

import subprocess
from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    print("[PREFLIGHT] Running tests")
    result = subprocess.run(["bash", str(root / "tests" / "run.sh")])
    if result.returncode == 0:
        print("[PREFLIGHT] Tests passed")
        return 0
    print("[PREFLIGHT] Tests failed, running autofix")
    subprocess.run(["bash", str(root / "tests" / "autofix.sh")], check=True)
    print("[PREFLIGHT] Re-running tests")
    subprocess.run(["bash", str(root / "tests" / "run.sh")], check=True)
    print("[PREFLIGHT] Preflight complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
