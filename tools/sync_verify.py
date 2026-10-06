#!/usr/bin/env python3
from pathlib import Path
from snapshot_sync import SnapshotSync

if __name__ == "__main__":
    SnapshotSync(
        "Verify",
        Path(__file__).resolve().parent.parent,
        "tools/vendor/verify",
        ".agents/skills/verify",
        "tools/vendor/verify/.agents/skills/verify",
        (
            "src/core",
            "src/roblox",
            "src/lune",
            "src/gate",
            "src/evidence",
            "src/benchmark.luau",
            "src/benchmark-store.luau",
            "src/runtime",
            "LICENSE",
            "PROVENANCE.md",
            "docs",
        ),
        "",
    ).main()
