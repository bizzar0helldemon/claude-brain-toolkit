---
title: pytest Sub-Package Import Fix (no top-level __init__.py)
type: prompt-pattern
domain: coding
interaction-mode: automation
ai-fluency-dimensions: [diligence, discernment]
tags: [prompt, coding, pytest, python, imports, fastapi, testclient]
effectiveness: high
created: 2026-04-07
last-used: 2026-04-07
related: []
---

# pytest Sub-Package Import Fix (no top-level __init__.py)

## When to Use

When writing pytest fixtures or tests for a Python project where:
- Tests live in `<pkg>/tests/`
- The parent directory (e.g., `mcp/`) is **not** a proper Python package (no top-level `__init__.py` at the repo root level for that directory)
- You need to import a sub-module like `dashboard.routes` from within the test fixture

Common scenario: FastAPI project with `mcp/dashboard/routes.py`, tests in `mcp/tests/`, and no `mcp/__init__.py` at the repo root.

## The Pattern

In the fixture that needs to import the sub-module, add `sys.path.insert` before the import:

```python
import os
import sys

@pytest.fixture
def {{client_fixture}}({{db_fixture}}):
    mcp_dir = os.path.join(os.path.dirname(__file__), "..")
    if mcp_dir not in sys.path:
        sys.path.insert(0, mcp_dir)

    from fastapi import FastAPI
    from fastapi.testclient import TestClient
    import {{submodule}}.routes as routes_mod  # e.g. dashboard.routes

    app = FastAPI()
    app.include_router(routes_mod.router)
    return TestClient(app)
```

**Do NOT use:** `import mcp.dashboard.routes` — this fails with `ModuleNotFoundError: No module named 'mcp.dashboard'` when `mcp/` has no `__init__.py` at the repo root.

**Use instead:** `import dashboard.routes` after inserting `mcp/` onto `sys.path`.

## Why It Works

When `mcp/` has no repo-root `__init__.py`, Python does not treat it as a package. The existing test files in the suite already use this convention (`from capital import register`, `import db as db_module`) — they work because `conftest.py` or pytest's rootdir logic adds `mcp/` to `sys.path`. Making the fixture explicit with `sys.path.insert` ensures the path is set regardless of pytest's rootdir detection.

## Variations

- If `conftest.py` already has a top-level `sys.path.insert` for the package dir, you don't need to repeat it in the fixture — just use the direct import.
- For `importlib.reload()` cases (where you need a fresh module state), do the path insert before the reload call.

## What Doesn't Work

- `import mcp.dashboard.routes` — fails when `mcp/` is not a proper package
- `from mcp.dashboard import routes` — same failure
- Relying on pytest's rootdir to add `mcp/` automatically without explicit `sys.path` manipulation in the fixture — fragile, depends on rootdir detection

## Examples

**Brookside Trading Post (2026-04-07):** Adding `dash_client` fixture to `mcp/tests/conftest.py` for FastAPI TestClient hitting `mcp/dashboard/routes.py`. First attempt with `import mcp.dashboard.routes` raised `ModuleNotFoundError`. Fix: added `sys.path.insert(0, mcp_dir)` then `import dashboard.routes as routes_mod`. All 6 smoke tests passed immediately after.
