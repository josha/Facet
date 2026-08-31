# The public-clone run, and what it is evidence of (DR-26/27/28)

**Taken 2026-08-31 at `db00d43`.** `git clone` of this repository into a
directory with no parent workspace — no sibling game checkout, no private
archive, no git-ignored evidence — followed by `tools/verify.sh full` with an
empty result store.

The machine record of that run is beside this file as
`public-clone-full-run.json`, verbatim and unedited, and it is what the three
rows below actually read. This document explains it; the JSON is the evidence.

## What it says

| | |
|---|---|
| Tier | `full`, cold store |
| Wall | 314.5 s |
| Rows | 205 PASS · **0 FAIL_RECOVERABLE** · 260 FAIL_ENVIRONMENT · 13 NOT_EVALUATED · 28 PENDING · 2 RETIRED |
| Producers | 131 traced, **0 failed** |
| `build_places` / `build_reference_places` | PASS — the example places rebuild from the clone |
| `package-verify` | PASS — build, tree inspection, purity and the packaged canary, from the clone |
| `build_model` | PASS |
| `suite` | PASS |

## What it is NOT evidence of

**The clone was taken from this repository on disk, not fetched over the network
from the renamed remote.** Every byte is the same and every check ran the same
way, but the network path — credentials, transport, the redirect the rename
leaves behind — is not exercised here and is not claimed. The rename itself is
recorded separately, and reaching the remote is the owner's action.

The 260 environment rows are the recorded Studio, device, performance and
external evidence a clone cannot reach; each is counted and named rather than
folded into a verdict. The 13 unjudged rows are the perf rows whose producers
are declared for the release tier, which `full` never promised to run.
