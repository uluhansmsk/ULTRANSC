# Contributing to ULTRANSC

Thank you for your interest in contributing to ULTRANSC! We welcome contributions of all kinds: bug fixes, feature proposals, documentation improvements, and tests.

---

## Code of Conduct

This project adheres to the Contributor Covenant [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

---

## Development Setup

1. **Fork and clone the repository:**
   ```bash
   git clone https://github.com/<your-username>/ULTRANSC.git
   cd ULTRANSC
   ```

2. **Create and activate a virtual environment:**
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install the package in editable mode with development dependencies:**
   ```bash
   pip install -e ".[dev]"
   ```

4. **Ensure system dependencies are installed:**
   - `ffmpeg` and `ffprobe`
   - `whisper-cli` (from [whisper.cpp](https://github.com/ggerganov/whisper.cpp))

---

## Development Workflow

1. **Create a new feature branch:**
   ```bash
   git checkout -b feat/my-new-feature
   ```

2. **Make your changes:**
   - Keep code clean, modular, and well-documented.
   - Follow existing architecture under `ultransc/`.
   - Preserve backward compatibility for CLI arguments and configs.

3. **Format and lint your code:**
   We use [Ruff](https://github.com/astral-sh/ruff) for linting and code formatting:
   ```bash
   ruff check .
   ruff format .
   ```

4. **Run the test suite:**
   ```bash
   python tests/run.py
   ```
   Ensure all tests pass before opening a pull request.

---

## Commit Guidelines

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

- `feat: add markdown and html export formats`
- `fix: resolve windows path resolution in test suite`
- `docs: update docker compose instructions`
- `test: add unit tests for watch mode`
- `chore: bump version to 0.8.0`

---

## Pull Request Guidelines

1. Ensure all tests and linter checks pass locally.
2. Provide a clear description in your Pull Request detailing what changes were made and why.
3. Link any related issues (e.g. `Closes #12`).
4. Update `README.md` and `CHANGELOG.md` if your change introduces new features, flags, or configuration keys.
