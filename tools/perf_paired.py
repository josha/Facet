#!/usr/bin/env python3

import argparse
import glob
import json
import os
import shutil
import statistics
import subprocess
import sys
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "tools" / "lune" / "perf_paired_scene.luau"
SCENES = [
    "hud-binding-storm",
    "settings-churn",
    "scroll-focus-traversal",
    "collection-mutation",
    "animation-interruption",
    "locale-textsize-change",
    "async-image-burst",
    "shadow-storm",
    "virtual-list-scroll",
    "native-scroll-drag",
    "dense-hud",
    "stylesheet-state-churn",
    "async-image-grid",
    "screen-lifecycle-churn",
    "theme-swap-flat",
    "theme-swap-metrics",
    "dense-motion",
    "control-motion",
    "theme-swap-assets",
    "lab-dense-scroll",
    "lab-collection-churn",
    "adaptive-navigation-images",
    "navigation-customization",
    "alert-present-dismiss",
    "picker-menu-open-close",
    "picker-segmented-textsize",
    "radial-menu-open-close",
]


def environment():
    env = dict(os.environ)
    env["PATH"] = os.pathsep.join([str(Path.home() / ".rokit" / "bin"), "/opt/homebrew/bin", "/usr/local/bin", env.get("PATH", "")])
    return env


def load_average():
    try:
        return " ".join(f"{value:.2f}" for value in os.getloadavg())
    except OSError:
        return "unknown"


def run_scene(tree, scene, env):
    result = subprocess.run(
        ["lune", "run", "tools/lune/perf_paired_scene", scene],
        cwd=tree,
        env=env,
        capture_output=True,
        text=True,
    )
    for line in result.stdout.splitlines():
        if line.startswith("@@"):
            return json.loads(line[2:])
    return {"scene": scene, "status": "crashed"}


def run(arguments):
    out = Path(arguments.out)
    out.mkdir(parents=True, exist_ok=True)
    trees = []
    for pair in arguments.trees:
        label, _, tree = pair.partition("=")
        trees.append((label, Path(tree).resolve()))
    scenes = arguments.scenes.split(",") if arguments.scenes else SCENES
    env = environment()
    with open(out / "log.txt", "a") as log, open(out / "scenes.jsonl", "a") as rows:
        for round_number in range(1, arguments.rounds + 1):
            for label, tree in trees:
                target = tree / "tools" / "lune" / "perf_paired_scene.luau"
                if target.resolve() != RUNNER.resolve():
                    shutil.copyfile(RUNNER, target)
                print(f"round {round_number} {label} start {datetime.now():%H:%M:%S} load {load_average()}", file=log, flush=True)
                for scene in scenes:
                    row = run_scene(tree, scene, env)
                    rows.write(json.dumps({"label": label, "round": round_number, "row": row}) + "\n")
                    rows.flush()
                if not arguments.skip_bench:
                    with open(out / f"bench-{label}-{round_number}.log", "w") as bench_log:
                        subprocess.run(["bash", "tools/bench.sh"], cwd=tree, env=env, stdout=bench_log, stderr=subprocess.STDOUT)
                    shutil.copyfile(tree / "artifacts" / "bench.json", out / f"bench-{label}-{round_number}.json")
                print(f"round {round_number} {label} end {datetime.now():%H:%M:%S}", file=log, flush=True)
        print("DONE", file=log, flush=True)


def median(values):
    return statistics.median(values) if values else None


def number(value, digits=4):
    return "n/a" if value is None else f"{value:.{digits}f}"


def consistent_slower(ratio, paired):
    return ratio is not None and ratio > 1.05 and paired and all(value > 1 for value in paired)


def report(arguments):
    out, first, second = Path(arguments.out), arguments.first, arguments.second
    data, order = {}, []
    for line in open(out / "scenes.jsonl"):
        if not line.strip():
            continue
        entry = json.loads(line)
        row = entry["row"]
        if row["scene"] not in order:
            order.append(row["scene"])
        data.setdefault(row["scene"], {}).setdefault(entry["label"], {})[entry["round"]] = row
    print(f"| Scene | {first} p50 | {second} p50 | p50 ratio | p50 paired range | {first} p95 | {second} p95 | p95 ratio | p95 paired range | {first} p95 spread | {second} p95 spread | Flag |")
    print("|---|---:|---:|---:|---|---:|---:|---:|---|---|---|---|")
    for scene in order:
        left = {k: v for k, v in data[scene].get(first, {}).items() if v.get("status") == "ok"}
        right = {k: v for k, v in data[scene].get(second, {}).items() if v.get("status") == "ok"}
        values = {}
        for field in ("p50", "p95"):
            a = median([v[field] for v in left.values()])
            b = median([v[field] for v in right.values()])
            ratio = b / a if a and b is not None else None
            paired = [right[k][field] / left[k][field] for k in sorted(left) if k in right and left[k][field] > 0]
            values[field] = (a, b, ratio, paired)
        flag = ""
        if not left:
            statuses = sorted({v.get("status", "?") for v in data[scene].get(first, {}).values()})
            flag = f"{first} unavailable ({'/'.join(statuses)})"
        elif not right:
            flag = f"{second} unavailable"
        else:
            slower = [field for field in ("p50", "p95") if consistent_slower(values[field][2], values[field][3])]
            if slower:
                flag = f"{second} slower ({', '.join(slower)})"

        def spread(rows):
            xs = [v["p95"] for v in rows.values()]
            return f"{min(xs):.4f}-{max(xs):.4f}" if xs else "n/a"

        def paired_range(paired):
            return f"{min(paired):.2f}-{max(paired):.2f}" if paired else "n/a"

        a50, b50, r50, p50 = values["p50"]
        a95, b95, r95, p95 = values["p95"]
        print(
            f"| {scene} | {number(a50)} | {number(b50)} | {number(r50, 3)} | {paired_range(p50)} | {number(a95)} | {number(b95)} | "
            f"{number(r95, 3)} | {paired_range(p95)} | {spread(left)} | {spread(right)} | {flag} |"
        )

    def benches(label):
        results = {}
        for path in glob.glob(str(out / f"bench-{label}-*.json")):
            round_number = int(path.rsplit("-", 1)[1].split(".")[0])
            for entry in json.load(open(path)).get("results", []):
                if isinstance(entry, dict) and entry.get("p50_ms") is not None:
                    results.setdefault(entry["name"], {})[round_number] = entry
        return results

    left_bench, right_bench = benches(first), benches(second)
    if left_bench or right_bench:
        print()
        print(f"| Microbenchmark | {first} p50 | {second} p50 | p50 ratio | p50 paired range | {first} p95 | {second} p95 | p95 ratio | Flag |")
        print("|---|---:|---:|---:|---|---:|---:|---:|---|")
        for name in sorted(set(left_bench) | set(right_bench)):
            left, right = left_bench.get(name, {}), right_bench.get(name, {})
            cells = {}
            for field in ("p50_ms", "p95_ms"):
                a = median([v[field] for v in left.values()])
                b = median([v[field] for v in right.values()])
                ratio = b / a if a and b is not None else None
                paired = [right[k][field] / left[k][field] for k in sorted(left) if k in right and left[k][field] > 0]
                cells[field] = (a, b, ratio, paired)
            slower = [field[:3] for field in ("p50_ms", "p95_ms") if consistent_slower(cells[field][2], cells[field][3])]
            flag = f"{second} slower ({', '.join(slower)})" if slower and not name.startswith("zz-") else ""
            a50, b50, r50, p50 = cells["p50_ms"]
            a95, b95, r95, _ = cells["p95_ms"]
            paired = f"{min(p50):.2f}-{max(p50):.2f}" if p50 else "n/a"
            print(f"| {name} | {number(a50)} | {number(b50)} | {number(r50, 3)} | {paired} | {number(a95)} | {number(b95)} | {number(r95, 3)} | {flag} |")
        print()
        print("| Bench run | Yardstick p95 ms | Yardstick drift % |")
        print("|---|---:|---:|")
        for label in (first, second):
            for path in sorted(glob.glob(str(out / f"bench-{label}-*.json")), key=lambda p: int(p.rsplit("-", 1)[1].split(".")[0])):
                document = json.load(open(path))
                print(f"| {Path(path).stem[6:]} | {document.get('yardstickP95Ms', 0):.4f} | {document.get('yardstickDriftPct', 0):.1f} |")


def main():
    parser = argparse.ArgumentParser(prog="perf_paired")
    commands = parser.add_subparsers(dest="command", required=True)
    runner = commands.add_parser("run")
    runner.add_argument("--out", required=True)
    runner.add_argument("--rounds", type=int, default=5)
    runner.add_argument("--scenes", default="")
    runner.add_argument("--skip-bench", action="store_true")
    runner.add_argument("trees", nargs="+", help="label=worktree, run in the given order each round")
    reporter = commands.add_parser("report")
    reporter.add_argument("out")
    reporter.add_argument("first")
    reporter.add_argument("second")
    arguments = parser.parse_args()
    if arguments.command == "run":
        run(arguments)
    else:
        report(arguments)
    return 0


if __name__ == "__main__":
    sys.exit(main())
