#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
MAX_CHARACTERS = 200_000


def main():
    failures = []
    for directory in ("src", "examples"):
        for path in sorted((ROOT / directory).rglob("*")):
            if path.suffix not in (".luau", ".lua") or not path.is_file():
                continue
            size = len(path.read_text())
            if size >= MAX_CHARACTERS:
                failures.append(f"{path.relative_to(ROOT)}: {size} characters; Studio Source assignments require fewer than {MAX_CHARACTERS}")
    for failure in failures:
        print(failure)
    print(f"source-size: {'FAIL' if failures else 'PASS'}")
    return int(bool(failures))


if __name__ == "__main__":
    sys.exit(main())
