#!/usr/bin/env python3
"""Deprecated wrapper around generate_agents.py --type senior-architect.

Existing scripts and aliases that call this file keep working. New usage:

    python3 generators/generate_agents.py . --type senior-architect
"""

from __future__ import annotations

import sys
from pathlib import Path


def rewrite_args(argv: list[str]) -> list[str]:
    """Map the old CLI onto generate_agents.py.

    Old: generate_senior_architect.py [dir] [--project-type TYPE] [-t TYPE] [--force]
    New: generate_agents.py [dir] --type senior-architect [--tech-stack TYPE] [--force]
    """
    out: list[str] = ["--type", "senior-architect"]
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in ("--type",) or arg.startswith("--type="):
            # Forced to senior-architect; drop caller --type.
            if arg == "--type":
                i += 2
            else:
                i += 1
            continue
        if arg in ("--project-type", "--project_type", "-t"):
            if i + 1 >= len(argv):
                print(f"error: {arg} requires a value", file=sys.stderr)
                sys.exit(2)
            out.extend(["--tech-stack", argv[i + 1]])
            i += 2
            continue
        if arg.startswith("--project-type="):
            out.append("--tech-stack=" + arg.split("=", 1)[1])
            i += 1
            continue
        out.append(arg)
        i += 1
    return out


def main() -> int:
    print(
        "DEPRECATED: generate_senior_architect.py is superseded by "
        "generate_agents.py --type senior-architect.\n"
        "Forwarding to the unified generator.",
        file=sys.stderr,
    )
    here = Path(__file__).resolve().parent
    sys.path.insert(0, str(here))
    import generate_agents

    sys.argv = [str(here / "generate_agents.py")] + rewrite_args(sys.argv[1:])
    return generate_agents.main()


if __name__ == "__main__":
    sys.exit(main())
