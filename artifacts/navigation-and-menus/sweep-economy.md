# D0.1 — one suite run per sweep instead of 301

## What it cost before

Measured 2026-08-16 on this machine, at the round's starting commit.

| Fact | Number | How |
|---|---|---|
| One full LuauUI suite run | **83.4 s** wall, 5618 passed | `/usr/bin/time -p ./run-tests.sh` |
| One full Rascal Rally suite run | **36.5 s** wall, 3280 passed | `time tools/suite_transcript.sh` on a cold cache |
| LuauUI suite invocations in the manifest | **234** | 164 `out="$(./run-tests.sh 2>&1)"` + 44 `… \| grep` + 23 `>/dev/null 2>&1`, plus 3 written with escaped quotes |
| Rascal Rally suite invocations | **67** | all reached through `cd ../../../games/RascalRally/code` |
| Suite greps riding those captures | **1127** | 1062 LuauUI, 65 Rascal Rally |
| Suite time in one full sweep | **≈ 4 h 05 min** | and every run produced a byte-identical transcript |

The suite is not the problem. Running it 301 times is. Nothing about the checks'
meaning wants a fresh run — they all assert against the same tree.

## What it costs now

`tools/test.sh` owns a cache keyed on a **content fingerprint**: a hash of every file
under `src/ tests/ examples/ vendor/`, plus `run-tests.sh`, `rokit.toml` and the `lune`
version. Computing it takes **0.23 s**. `tools/suite_transcript.sh` is the thin front
door every gate check greps; Rascal Rally has its own, whose fingerprint also covers
`GameStudio/ui/LuauUI/{src,tests}` because its specs require LuauUI modules directly.

| | Before | After |
|---|---|---|
| Suite runs per sweep | 301 | **2** (one per repo, on the first miss) |
| Warm serve | 83.4 s | **0.14 s** |
| Suite time per sweep | ≈ 4 h 05 min | **≈ 2 min** |

## Why this is the dangerous half of the change

A cache is exactly the shape that turns a real check into one that cannot fail. A helper
that printed a cached transcript and exited 0 over a red suite would convert 1127 gate
greps into decoration in a single commit. The guards are the deliverable, not caveats on
it, and every one of them is broken on purpose in `tools/suite_cache_selftest.sh` —
27 assertions, plus two mutations of the implementation itself that reddened 6 and 2
assertions respectively. See `suite-cache-selftest.md`.

`tools/check_manifest_integrity.py` now also **refuses** a run string that invokes
`./run-tests.sh` directly, so a single re-introduced direct call fails the gate rather
than quietly costing 83 s a sweep.

## Not in scope

Making the suite itself faster. 83 s for 5618 specs is fine, the `--fast` tier already
exists for the inner loop, and the settle-between-gates policy in `tools/prior_gates.sh`
stays exactly as it is — it exists because bench checks measure the previous gate's tail,
which caching does not change.
