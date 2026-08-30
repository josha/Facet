# Timings — cold, warm, and the twenty-minute budget

Workstream T, D10. Every number here was taken from a run in this session.

## The machine, and where the numbers were taken

| | |
|---|---|
| Model | `sysctl -n hw.model` → **Mac16,11**; `hw.ncpu` → **14** |
| Memory | 64 GB |
| OS | Darwin 25.6.0 |
| Lune | 0.10.4 |
| StyLua | 2.5.2 |
| Python | 3.14.4 |
| Concurrency cap | `min(4, floor(cores / 4))` = **3** parallel producers; serialized ones never overlap |

**The release timings were taken in a frozen copy of the tree, and that is not a
convenience — it is the only way the measurement means anything.** Six agents
share the working tree during this stage, and the suite's identity is a content
hash over `src/ tests/ examples/`: a sibling landing one commit mid-run moves the
identity, so every producer that reaches the suite through the old front door
re-runs it. Measured directly: one `tools/verify.sh full` in the live tree spent
**two** full suite runs inside `tools/suite_cache_selftest.sh` alone, because the
tree moved under it twice. The copy is at
`/tmp/facet-mutation-parity/GameStudio/ui/Facet`, laid out with that path prefix
and a `games` symlink beside it so `../../../games/RascalRally/code` still
resolves; it is `rsync -a --delete` of the working tree minus
`artifacts/verify/`, `artifacts/suite_cache/` and `build/`.

## Headline

<!--NUMBERS-->

## The ten slowest producers

<!--SLOWEST-->

## One run per producer per identity

`artifacts/verify/invocation-trace.json` is written one JSON line per producer
START, live, so a killed run still leaves its trace. The count below is that
file's own answer, not a claim from the design.

<!--TRACE-->

## Irreducible producers

<!--IRREDUCIBLE-->

## Against the Step 13.5 baseline

<!--REDUCTION-->
