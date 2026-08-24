#!/usr/bin/env python3
"""Shared filesystem helpers for generators."""

import os
import tempfile
from pathlib import Path
from typing import Tuple


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def validate_target_dir(path: str) -> Tuple[bool, str]:
    """Reject targets outside ~/workspaces/, ~/projects/, this repo, or /tmp/."""
    try:
        resolved = Path(path).resolve()
        if not resolved.is_dir():
            return False, f"Target directory does not exist: {resolved}"
        if not os.access(resolved, os.W_OK):
            return False, f"Target directory is not writable: {resolved}"

        allowed_parents = [
            Path.home() / "workspaces",
            Path.home() / "projects",
            Path("/tmp").resolve(),
            repo_root(),
        ]
        for parent in allowed_parents:
            try:
                resolved.relative_to(parent)
                return True, ""
            except ValueError:
                pass
        return (
            False,
            f"Target directory must be under ~/workspaces/, ~/projects/, {repo_root()}, or /tmp/",
        )
    except Exception as e:
        return False, f"Invalid target directory: {e}"


def atomic_write(
    target_path: Path, content: str, prefix: str = ".tmp-"
) -> Tuple[bool, str]:
    """Write content via temp file + replace. Returns (ok, error)."""
    try:
        target_path.parent.mkdir(parents=True, exist_ok=True)
    except Exception as e:
        return False, f"Cannot create directory: {target_path.parent}. {e}"

    tmp_path = None
    try:
        fd, tmp_path = tempfile.mkstemp(
            dir=target_path.parent, prefix=prefix, suffix=".tmp"
        )
        with os.fdopen(fd, "w") as f:
            f.write(content)
        os.replace(tmp_path, target_path)
        return True, ""
    except Exception as e:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
        return False, f"Cannot write to {target_path}. {e}"
