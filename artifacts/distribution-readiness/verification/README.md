# The verification graph, as built

Workstream T of distribution readiness (execution plan §2 D7–D10). This is the
design as it actually stands in the tree, the commands, and the numbers. The
other documents beside it are the evidence: `graph-census.md` (what every
manifest row became), `coverage-map.md` (nothing removed without a home),
`mutation-parity.md` (old path and new path go red together), `timings.md`
(cold and warm, against the twenty-minute budget).

## What replaced what

| Was | Is |
|---|---|
| 233 rows, each spending one cached suite transcript and grepping it for a sentence — 1,425 patterns in all | 193 rows looking up 9,335 case ids in ONE structured suite result (`facet-suite-results/1`, written by `tests/lib/testkit.luau`) |
| 266 scanner invocations of 124 distinct commands, many byte-identical | 134 producers, each run at most once per exact input identity |
| 16 `prior-gates-unregressed` rows, each re-running every earlier gate, each of which re-ran ITS priors | one lookup: every earlier phase's rows, evaluated from the same run |
| 74 rows pinning a checked-in ledger of a closed stage by path and literal string | recorded machine evidence keeps its row as a content-hash receipt; a record of a past decision leaves the graph for `coverage-map.md` |
| `tools/lune/gate.luau` running a phase's rows as shell | `tools/verify.sh`, evaluating every phase view from one run |

## The pieces

| Path | What it is |
|---|---|
| `tests/lib/testkit.luau` | every case gets `<spec>::<describe>::<it>`; `run{ jsonOut = … }` writes the whole run as data. The human transcript is byte-identical to what it was |
| `tools/lune/verify/identity.luau` | a producer's identity: sha256 over LF-normalised input content ∥ command ∥ environment class ∥ toolchain pins ∥ declared fixtures |
| `tools/lune/verify/results.luau` | the result store, and every reason it refuses one |
| `tools/lune/verify/graph.luau` + `graph.json` | the graph: requirement → producer → result ids → phase view. `graph.json` is GENERATED — regenerate it, never hand-edit it |
| `tools/lune/verify/convert_manifest.py` | the generator: splits each manifest row on top-level `&&` (round trip asserted byte for byte), resolves greps to case ids, maps commands to producers, writes the census and the coverage map |
| `tools/lune/verify/run.luau` | producer execution: reuse or run, parallel batch then the serialized ones in dependency order, a settle before anything that measures |
| `tools/lune/verify_cli.luau` + `tools/verify.sh` | the coordinator |
| `tools/lune/verify/selftest.luau` | the store's own negative controls — 31 refusals, each made on purpose |
| `tools/lune/verify/evidence/*.json` | one content-hash receipt per row that pins recorded evidence |

## The commands

```
tools/verify.sh affected      producers whose declared inputs match your changed
                              paths, plus tests/run_one for each changed spec
tools/verify.sh fast          the deterministic inner-loop spine
tools/verify.sh full          every deterministic producer once; every phase view
tools/verify.sh release       …plus perf, builds, package and the Rascal Rally suite
tools/gate.sh <phase>         = tools/verify.sh full --gate <phase>
tools/verify.sh full --explain            why each producer was selected and reused
tools/verify.sh full --rerun <producer>   ignore one stored result
```

`affected` and `fast` print a banner saying they are not full or release
evidence, and their suite results are tier `fast`/`one`, which the full and
release reader refuses outright. That is the same defence `./run-tests.sh --fast`
has carried since a `printf | grep -q` under `pipefail` let a fast-tier
transcript through as a suite verdict in August.

## Identity, and every reason a result is refused

identity = sha256 over the producer id, its exact command, its environment class,
the toolchain pins (`rokit.toml` content plus `lune`, `stylua` and `python3`
versions), every file matching its declared input globs as
`path\0sha256(LF-normalised content)`, and its declared fixture inputs.

A stored result is refused when the identity differs, when `complete` is false,
when the status is FAIL (a failed producer is reported and rerun, never reused),
when the toolchain differs, when the environment class is not the one the row
requires, when `bodyHash` does not match a fresh canonical hash of the record,
and — for the suite — when the tier is not `full`, when any case failed, when
there is no summary, when fewer specs reported than the runner registered, or
when fewer cases passed than there are registered spec modules.

`lune run tools/lune/verify/selftest` makes all of those happen on purpose.

## Evidence classes

`deterministic`, `perf`, `studio`, `device`, `external`, `package`. A result in
one class satisfies only a row that asks for that class; no headless cache
upgrades one into another. Recorded Studio, device and performance evidence is
pinned by content hash in a receipt and verified against the file on disk, or
against `../Facet-private-archive/MANIFEST.json` when that archive is beside the
checkout; when neither is available the run reports it under "recorded evidence,
reported separately" rather than folding it into the headless verdict.

## Numbers

See `timings.md` for cold and warm release timings against the twenty-minute
budget, the ten slowest producers, and the irreducible ones.
