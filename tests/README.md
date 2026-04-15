# Tests

These tests are lightweight and safe. They do not execute the full pipeline.

Run:

```bash
bash tests/run.sh
```

Preflight (auto-fix on failure):

```bash
bash tests/preflight.sh
```

What it checks:

- Shell syntax for key scripts
- Module exports in lib/
- Required config keys
- Executable permissions for key scripts
