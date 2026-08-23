from __future__ import annotations

import compileall
import subprocess
import sys
import unittest
from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(root))
    if not compileall.compile_dir(root / "ultransc", quiet=1):
        print("[FAIL] python compile checks")
        return 1
    print("[PASS] python compile checks")
    suite = unittest.defaultTestLoader.discover(str(root / "tests"), pattern="test_*.py")
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        return 1
    import shutil
    if shutil.which("bash"):
        for script in (
            "ultransc.sh",
            "ice.sh",
            "check-setup.sh",
            "setup.sh",
            "tests/preflight.sh",
            "tests/autofix.sh",
            "legacy/transcribe.sh",
        ):
            subprocess.run(["bash", "-n", str(root / script)], check=True)
        print("[PASS] shell wrapper syntax checks")
    else:
        print("[SKIP] shell wrapper syntax checks (bash not available)")
    print("[PASS] all tests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
