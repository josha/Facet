# Paired performance comparison

Use paired runs to compare two source trees on the same host. The runner
interleaves the trees in each round. Ratios compare Luau workload cost. They
do not measure Roblox layout, paint, or physical device frame time.

## Run

Prepare two source trees with the same toolchain. Close Studio and other
heavy processes. Run from the repository root:

```sh
lute run tools/facet perf paired run --out artifacts/paired --rounds 5 base=<base-tree> candidate=<candidate-tree>
lute run tools/facet perf paired report artifacts/paired base candidate --rounds 5 --gate
```

Use `--scenes dense-hud,screen-lifecycle-churn` to select scenes. Pass the same
selection to `run` and `report`. Use `--skip-bench` on both commands only when
microbenchmarks are outside the selected scope. The report names that omission;
it does not prove complete performance coverage. The default scene list is
`tools/facet/lib/perf_paired.luau`.

The runner copies `bench/paired_scene.luau` into each target tree. Each scene
runs in a new Lute process. Each round also runs the target tree's
`lute run tools/facet bench` unless `--skip-bench` is set.

Results stay in the output directory. `scenes.jsonl` holds scene rows.
`bench-<label>-<round>.json` holds benchmark data. `log.txt` records progress.
Use an empty output directory for a new comparison.

The report requires the expected round count. Missing rounds, failed commands,
unstable benchmark reports and unavailable measurements fail with exit 2.
Only complete measurements can reach the relative slowdown gate, which exits 1
for a consistent slowdown. CI requires all scenes and microbenchmarks. It
rechecks the full suite with six rounds only after a statistical slowdown;
an execution or measurement failure cannot become a narrowed passing recheck.

## Read the report

The report starts with a summary. The summary gives the verdict (PASS or
FAIL), the number of measured scenes and microbenchmarks, and a table of each
consistently slower measurement with its p50 and p95 change in percent. The
full tables follow. `--summary FILE` appends the summary and the full tables
to `FILE` as Markdown. The CI job writes them to the job summary page.

- `p50` and `p95` are medians of the per-run percentiles, in milliseconds.
- `ratio` divides the second tree's median by the first tree's median.
- `paired range` is the minimum and maximum ratio within matching rounds.
- `spread` is the minimum and maximum p95 across rounds.
- A flag requires a ratio above 1.05 and every paired ratio above 1.

A ratio below 1 means the second tree takes less time. A failed scene has no
usable timing. Do not estimate its missing result. Review host load and the
benchmark yardstick before making a performance claim. Shared host load can
change paired results. Headless results require separate Studio evidence for
engine behavior.

## Profile a saved racing hub

```sh
lute run --profile --profile-output artifacts/mount-profile.json tools/engine/profile_racing_hub_mount.luau <workspace> phone-portrait
```

Use `desktop` for the desktop viewport. An optional fourth argument selects a
Facet source directory. The default is `src`.

The profiler loads the saved Interface, Theme and Model modules. It uses the
native engine double, fixed game state and no background tasks. It measures
Luau construction work. It does not measure native layout, asynchronous text
measurement or reveal readiness.

Use `lute run tools/facet perf capture --workspace <workspace> --out <output>`
for Studio evidence. Its mount time includes client startup and geometry
settling. Live readouts and progress bars can keep geometry changing after
construction completes. Read the geometry trace with the mount time.
