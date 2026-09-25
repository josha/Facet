#!/usr/bin/env python3

import argparse
import concurrent.futures
import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
LUNE = os.environ.get("LUNE", "lune")


def spec_names():
    out = []
    for p in sorted((ROOT / "tests").glob("*.spec.luau")):
        out.append(("tests", p.name[: -len(".spec.luau")]))
    for p in sorted((ROOT / "tests" / "reference").glob("*_spec.luau")):
        out.append(("reference", p.name[: -len(".luau")]))
    return out


REFERENCE_DRIVER = """local testkit = require("./lib/testkit")
require("./reference/{name}")
if not testkit.run({{ tier = "one", registeredSpecs = 1 }}) then
\tprocess_exit()
end
"""


def run_one(entry, timeout):
    kind, name = entry
    if kind == "tests":
        cmd = [LUNE, "run", "tests/run_one", name]
        cleanup = None
    else:
        fd, path = tempfile.mkstemp(suffix=".luau", dir=str(ROOT / "tests"))
        os.close(fd)
        driver = pathlib.Path(path)
        driver.write_text(
            '--!strict\nlocal process = require("@lune/process")\n'
            'local testkit = require("./lib/testkit")\n'
            f'require("./reference/{name}")\n'
            'if not testkit.run({ tier = "one", registeredSpecs = 1 }) then\n'
            "\tprocess.exit(1)\nend\n"
        )
        cmd = [LUNE, "run", f"tests/{driver.stem}"]
        cleanup = driver
    try:
        proc = subprocess.run(
            cmd, cwd=ROOT, capture_output=True, text=True, timeout=timeout
        )
        status = "PASS" if proc.returncode == 0 else "FAIL"
        tail = (proc.stdout + proc.stderr)[-2000:]
    except subprocess.TimeoutExpired:
        status, tail = "TIMEOUT", ""
    finally:
        if cleanup is not None:
            cleanup.unlink(missing_ok=True)
    return (kind, name, status, tail)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", type=int, default=8)
    ap.add_argument("--timeout", type=int, default=600)
    ap.add_argument("--json", default=None)
    ap.add_argument("--only", nargs="*", default=None)
    ap.add_argument("--log", default=None, help="directory for failure output")
    args = ap.parse_args()

    entries = spec_names()
    if args.only:
        wanted = set(args.only)
        entries = [e for e in entries if e[1] in wanted]

    results = {}
    logdir = pathlib.Path(args.log) if args.log else None
    if logdir:
        logdir.mkdir(parents=True, exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = [pool.submit(run_one, e, args.timeout) for e in entries]
        done = 0
        for fut in concurrent.futures.as_completed(futures):
            kind, name, status, tail = fut.result()
            key = name if kind == "tests" else f"reference/{name}"
            results[key] = status
            done += 1
            if status != "PASS":
                print(f"{status} {key}", flush=True)
                if logdir:
                    (logdir / (key.replace("/", "_") + ".log")).write_text(tail)
            if done % 50 == 0:
                print(f"... {done}/{len(entries)}", file=sys.stderr, flush=True)

    passed = sum(1 for v in results.values() if v == "PASS")
    print(f"\n{passed}/{len(results)} PASS")
    if args.json:
        pathlib.Path(args.json).write_text(json.dumps(results, indent=1, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
