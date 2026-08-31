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
| 233 rows, each spending one cached suite transcript and grepping it for a sentence — 1,421 patterns in all | 193 rows looking up 9,341 case ids in ONE structured suite result (`facet-suite-results/1`, written by `tests/lib/testkit.luau`) |
| 266 scanner invocations of 124 distinct commands, many byte-identical | 133 producers, each run at most once per exact input identity |
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
| `tools/lune/verify/run.luau` | producer execution: reuse or run, parallel batch then the serialized ones in dependency order, a settle before anything that measures AND is about to run |
| `tools/lune/verify_cli.luau` + `tools/verify.sh` | the coordinator |
| `tools/lune/verify/selftest.luau` | the store's own negative controls — 32 checks, each refusal made on purpose |
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

| Tier | Cold | Warm | Producers | Reused warm |
|---|---:|---:|---:|---:|
| `full` | 308.4 s | 23.4 s | 128 | 121 / 128 |
| `release` | **534.7 s (8 m 55 s)** | 146.5 s | 133 | 119 / 133 |

The release run is 55 % of the twenty-minute budget. `timings.md` carries the
`/usr/bin/time` lines, the ten slowest producers, the per-evidence-class split,
the invocation trace's own answer to "did any producer run twice" (no), and the
two irreducible producers with owner, class, cost and trigger.

## What the conversion produced

| Class | Rows |
|---|---:|
| converted to case-id lookups | 193 |
| exit-zero on a producer | 98 |
| evidence pins kept verbatim | 128 |
| recorded-evidence receipts (content hash) | 47 |
| prior-phase re-evaluation | 16 |
| declared evidence (device / human) | 16 |
| pending (the registration block and honest device rows) | 57 |
| retired with their subject | 2 |
| archived as records of past decisions | 57 |

1,421 transcript greps resolved into 9,341 case-id references. Four greps match
no case in this suite — they were red before this workstream began, they are
named in `graph-census.md`, and they keep their grep against the ONE recorded
transcript so their verdict is unchanged.

## Triage of every failing row (release run, 2026-08-30)

404 PASS, 31 FAIL_RECOVERABLE, 56 PENDING, 16 FAIL_ENVIRONMENT, 2 RETIRED.

| Rows | What | Attribution |
|---:|---|---|
| 16 | `prior-gates-unregressed` | **red by design**: they are red exactly because an earlier phase is, which is the row doing its job |
| 8 | `bench` produced no result | the benchmark measures wall clock against a frozen p95 on a machine running six agents; **pre-existing at stage open**, and a failed producer is never stored, so its rows follow it |
| 4 | the product-language guard and its selftest | **another workstream**: two matches in `docs/plans/facet-consolidated-roadmap.md`, the owner's uncommitted plan prose, in a tree that is leaving. The selftest cannot complete on a tree that carries any pre-existing match |
| 2 | an evidence receipt no longer hashes | **a sibling agent edited the file** after the receipt was taken; regenerating the receipts clears it, and the row naming it is the mechanism working |
| 1 | `examples-no-input-boilerplate` | **pre-existing at stage open**: `examples/gallery/examples/07_match3.luau` uses one of the navigation properties the lint forbids; verified red in the working tree independently of the graph |

None is caused by the conversion. The two that are one-line fixes in files this
workstream owns were made (a verdict checker's argument parsing, and the receipt
refresh); the rest are named above with their owner.

## What is red, and why

A full run in the live tree reports **398 PASS and 25 FAIL_RECOVERABLE** (a
release run in the frozen copy reported 401 and 34; the difference is the
producers that are red for reasons other workstreams own moving under it). None of the failures is
caused by the conversion, and each is named in the run report with the smallest
command that reproduces it:

- **the product-language guard and its selftest** (4 rows) — the guard cannot
  complete its selftest on a tree that carries pre-existing matches, and the two
  that remain are the owner's uncommitted plan edits. Recorded by the workstream
  that owns the guard;
- **the public-allowlist check** (1 row) — its 615 strays await the director's
  archival step;
- **four stale transcript greps** (3 rows) — cases renamed before this stage
  opened;
- **one example lint** (1 row) — a tutorial example acquired a navigation
  property the lint forbids; red in the working tree too, and older than this
  work;
- **`bench`** (perf class) — measures wall clock against a frozen p95 on a
  machine running six agents;
- **one evidence receipt whose file changed** after the receipt was taken — a
  sibling agent edited the artifact, and the row said so by name, which is the
  receipt mechanism working rather than failing;
- the rest are the **prior-phase rows**, which are red exactly because an
  earlier phase is: that is the row doing its job.

## Two release-graph producers have no row

`check_no_fusion` and `check_links_cli` both run at release and both were seen to
go from PASS to FAIL when their defect was planted — naming the planted require
in the source AND in the built model, and naming the dead link and its line. But
no row in the graph asserts either one, because the rows that will are two of the
thirty-four PENDING registration rows the director owns. Until those are given a
`run`, both producers report into the run's status and neither reddens a phase.

## The deletion proof, and the thirteen producers it found

The pre-archival question is whether `tools/verify.sh release` returns the same
verdicts before and after the stage record is deleted. It was asked in the frozen
copy, not here — six agents share this tree — by moving every `artifacts/<stage>/`
directory aside (keeping only `artifacts/verify/`, which the run owns and
recreates) along with `docs/plans`, `docs/handoff`, `docs/research`,
`.superpowers` and `ui_todo.md`: 77 paths, held and then restored.

**The rows are clean**: no row's check reads any of those trees any more. The
first run of the proof found that the PRODUCERS were not — 77 of them failed and
192 rows changed verdict. Seventy of those validate the record itself and are now
declared-evidence producers, each carrying its verdict and the sha256 of every
file it read.

**Twelve producers still need the record** after two rounds of fixes (63 were
served from receipts in the second round; a verdict checker that names its file
before an `=` was declaring no evidence at all and has been corrected since).
Four of them need it for a reason only the director can settle: they compare a
LIVING artefact against a FROZEN operand that lives in a tree that is leaving.

| Producer | Frozen operand it needs | What is lost if it goes |
|---|---|---|
| `check_surface_ledger` | `artifacts/api-architecture-consistency/surface-ledger.md` | the public surface is no longer reconciled against a ledger |
| `check_flat_baseline` | `artifacts/theme-packages-and-skinning/final-neutral-dump.json` | the byte-compatibility claim for the flat render. **`.gitignore` already makes this call**: that one file is the single exception to the ignore rule, "because it is NOT regenerable" |
| `check_reuse_ledger` | `artifacts/release-candidate-review/reuse-ledger.md` | the consolidation ledger's own audit |
| `check_source_size` | `docs/handoff/SOURCE_CAP_LEDGER.md` | the source-cap ledger's audit |

Each operand is one small file. The decision is to keep those four in the public
tree or to accept losing those four checks; nothing in this workstream can make
it. The other eight are `bench` (a measurement on a loaded machine), `stylua`,
`suite_cache_selftest`, `check_brand_drift-selftest`, `check_public_allowlist`
and the two manifest checkers — all red for reasons recorded below, none of them
a dependency on the record.

**The proof is therefore not yet green, and this is where it stands**: the rows
survive the deletion, 63 of the 77 producers that did not now do, and the twelve
that remain are named above with the file each one needs. The proof itself is
`bash /tmp/holdproof.sh` — it rsyncs the tree into the frozen copy, runs
release, moves 77 paths aside, runs release again, diffs the row verdicts by id,
and restores. Re-run it after the four operands are settled.

## Left for the director

- `tools/lune/gate_manifest.luau` stays for the archival step. The graph is
  regenerated from it, so the manifest remains the conversion source until it is
  archived; `tools/lune/gate_legacy.luau` is deleted with this workstream's last
  commit, once the mutation corpus has been recorded.
- 57 rows are archived as records of past decisions and 128 evidence pins remain
  as text; both lists are in `coverage-map.md` for the archival pass.
- `UI-LAYOUT-003` (text premeasurement) has no living row. It had none before
  this conversion either — the coverage map says so in its own column.
- `tools/lune/gate_legacy.luau` is KEPT, not deleted. The plan says to delete it
  once parity is proven, and parity is proven for three mutations on both paths —
  but one mutation did not reproduce its defect at all (M3) and one was caught
  only by the new path (M4), so the old path is still the only way to re-ask the
  question. It reads the manifest, which is staying for the archival step anyway,
  and it writes `gate-legacy.json` so it cannot overwrite a live verdict. The
  call to delete it belongs with the archival pass.
