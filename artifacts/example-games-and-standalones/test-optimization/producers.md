# What each gate producer actually costs

Measured at the current tree on the machine `baseline.md` documents. Raw table:
`producers.tsv`. Counts are invocations across one full 31-gate sweep, from the
manifest census.

| Producer | Once | × per sweep | Sweep total |
|---|---:|---:|---:|
| `./run-tests.sh` (via the cache) | **1587.0 s** | 1 | **1587.0 s** |
| `tools/bench.sh` | 11.7 s | 8 | 93.6 s |
| `lune run tools/lune/check_boundary` | 6.2 s | 14 | 86.2 s |
| `stylua --check src tests tools bench examples` | 1.8 s | 11 | 19.9 s |
| `lune run tools/lune/check_registration_cli` | 0.52 s | 26 | 13.5 s |
| `lune run tools/lune/check_docs_cli` | 0.28 s | 22 | 6.2 s |
| `lune run tools/lune/check_flat_baseline` | 0.42 s | 9 | 3.8 s |
| `lune run tools/lune/check_prop_parity_cli` | 0.24 s | 12 | 2.9 s |
| `lune run tools/lune/check_surface_ledger` | 0.26 s | 11 | 2.9 s |
| `lune run tools/lune/check_example_drift_cli` | 0.24 s | 8 | 1.9 s |
| `python3 tools/check_manifest_integrity.py` | 0.08 s | 12 | 1.0 s |
| `tools/suite_transcript.sh` (a cache read) | ~0.3 s | 261 | ~78 s |
| everything else (16 further checkers) | 0.03–0.74 s | 1–7 each | ~30 s |

Measured but not counted above because they are timing-sensitive and run rarely:
`tools/soak.sh` 0.4 s, `tools/faults.sh` 0.5 s, `tools/fuzz.sh <target>` 0.1 s.

## What this changes about the plan

**The static-analysis battery is not the problem.** It reads badly in the census —
`check_registration` twenty-six times, `check_docs` twenty-two — but every one of
those producers costs a fraction of a second, and the whole battery is about
**140 seconds** across a full sweep. A producer result cache would save perhaps two
minutes.

**One suite run is 1587 seconds.** It is 89 % of the sweep on its own, and the cache
cannot help: the budget requires the suite to run at least once at the final source
identity.

So the smallest safe change that materially reduces wall time is not a second cache.
It is the retention `baseline.md` measures. With the suite at the sum of its isolated
parts — about 200 s — the arithmetic becomes:

```
suite            ~200 s
bench.sh x8        94 s
check_boundary x14 86 s
transcript reads   78 s
stylua x11         20 s
the rest           ~60 s
                 -------
                 ~540 s   ≈ 9 minutes
```

inside a twenty-minute budget, with room for the settle waits. **A producer cache is
therefore not built.** The plan's instruction is "apply the smallest safe changes that
materially reduce wall time", and a second cache that saves two minutes buys a
permanent new way for a stale result to be served. If the post-fix measurement says
otherwise, the two candidates worth it — in order — are `check_boundary` (86 s, and it
is deterministic) and the transcript reads (78 s, already cached, so the cost is the
fingerprint recomputation on every one of 261 calls).

`bench.sh` stays uncached and always will: it measures wall clock against a frozen
p95, and a cached timing is not a timing.

## Changed here

**`tools/prior_gates.sh` settles only before the gates that measure.** The wait was
charged to every gate — up to 45 s each, so up to twenty-four minutes of deliberate
idling across thirty-two stages — while only twelve stages run
`bench`/`soak`/`perf`/`faults`/`fuzz`. The other twenty run source scanners, document
checks, transcript greps and file-existence assertions, none of which can answer
differently on a warm machine.

The set is **derived from the manifest** by `tools/lune/settle_gates`, never typed: a
hand-kept list is wrong the first time a stage gains a bench row, and wrong silently.
It fails towards settling — if the derivation cannot run, every gate settles exactly as
before, because the cost of an unnecessary wait is time and the cost of a missing one
is a red gate nobody can reproduce. The policy actually applied is written onto the
roll-up artifact, so a suspicious FAIL stays self-diagnosing.

**Negative control, run:** planting a `tools/bench.sh` row into a stage the derivation
calls FAST flips it to SETTLE, and removing the row flips it back.

```
$ lune run tools/lune/settle_gates -- --all | grep example-games-and-standalones
FAST    example-games-and-standalones          # baseline
SETTLE  example-games-and-standalones          # with a bench row planted
FAST    example-games-and-standalones          # restored
```
