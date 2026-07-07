#!/usr/bin/env python3
"""
Shared GitHub REST API helper for metrics.py and check_traction.py.

Both scripts query the same repo's stats/traffic/releases endpoints via
`gh api`; this module holds the one canonical `gh_api()` implementation
and the `REPO` constant so the two don't drift.

Not a standalone script — imported only.
"""

from __future__ import annotations

import json
import subprocess

REPO = "paulhkang94/markview"


def gh_api(path: str) -> dict | list | None:
    result = subprocess.run(["gh", "api", path], capture_output=True, text=True)
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None
