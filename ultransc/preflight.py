from __future__ import annotations


def main() -> int:
    from tests.run import main as test_main
    from .autofix import main as autofix_main

    print("[PREFLIGHT] Running tests")
    if test_main() == 0:
        print("[PREFLIGHT] Tests passed")
        return 0
    print("[PREFLIGHT] Tests failed, running autofix")
    if autofix_main() != 0:
        print("[PREFLIGHT][FAIL] autofix failed")
        return 1
    print("[PREFLIGHT] Re-running tests")
    if test_main() != 0:
        print("[PREFLIGHT][FAIL] tests failed after autofix")
        return 1
    print("[PREFLIGHT] Preflight complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
