#!/usr/bin/env python3
from pathlib import Path
from snapshot_sync import SnapshotSync

if __name__ == "__main__":
    SnapshotSync(
        "Compose",
        Path(__file__).resolve().parent.parent,
        "src/vendor/compose",
        ".agents/skills/compose",
        "skills/compose",
        ("src/core", "src/roblox", "LICENSE"),
        "src/",
        relocate_docs=True,
    ).main()
