import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description="Run the committed Verify corpus through isolated Lune workers.")
    parser.add_argument("--tier", choices=("one", "fast", "affected", "full", "release"), default="one")
    parser.add_argument("--jobs", type=int, default=8)
    parser.add_argument("--timeout", type=float, default=600)
    parser.add_argument("--json", default="artifacts/verify/workers.json")
    parser.add_argument("--only", nargs="*")
    parser.add_argument("--log")
    args = parser.parse_args()
    if args.only == []:
        parser.error("an explicit source selection must not be empty")
    if args.jobs < 1 or args.timeout <= 0:
        parser.error("jobs and timeout must be positive")
    directory = Path(args.log) if args.log else ROOT / "artifacts/verify/workers"
    output = Path(args.json)
    if not output.is_absolute():
        output = ROOT / output
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="facet-verify-workers-") as temporary:
        input_path = Path(temporary) / "input.json"
        input_path.write_text(json.dumps({"tier": args.tier, "jobs": args.jobs, "timeout": args.timeout, "only": args.only, "directory": str(directory), "output": str(output)}))
        return subprocess.call([os.environ.get("LUNE", "lune"), "run", "tools/lune/verify_workers", str(input_path)], cwd=ROOT)


if __name__ == "__main__":
    sys.exit(main())
