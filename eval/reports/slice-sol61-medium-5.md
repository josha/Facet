# Sol 6.1 Medium slice, fifth pair

Facet passed 13/13 universal checks and 40/49 diagnostic checks. Plain's
required universal pass failed when the Studio MCP connection closed; its
universal scores are missing. This pair cannot establish a valid universal
quality or runtime comparison. Both authors completed, but Facet used 1.995
times Plain's tokens and 1.380 times its author wall time. Efficiency and
memory targets remain unmet.

Both arms ran fresh at source `7b421a9ef4addd9efdef4b81798b7f3e8307c6f7`,
one task, seed 1, with Sol 6.1 Medium. Evidence is under
`artifacts/facetbench/slice-sol61-medium-5`. Historical results are unchanged.

| Measurement | Plain | Facet |
| --- | ---: | ---: |
| Author status | completed | completed |
| Required run checks and budgets | fail | pass |
| Universal scores | missing: host failure | 13 / 13 |
| Diagnostic spec checks | 22 / 49 | 40 / 49 |
| Desktop diagnostic checks | 11 / 24 | 20 / 24 |
| Phone portrait diagnostic checks | 10 / 24 | 19 / 24 |
| Strict type errors | 0 | 0 |
| Author wall time | 1064.971 s | 1469.828 s |
| Total tokens | 3,857,716 | 7,695,934 |
| Uncached input tokens | 109,162 | 195,545 |
| Cached input tokens | 3,709,952 | 7,464,960 |
| Output tokens | 38,602 | 35,429 |
| Completed CLI turns | 1 | 1 |
| Observable CLI turn duration | 1063.539472 s | 1468.572455 s |
| Tool calls | 134 | 145 |
| Tool time, union | 350.256 s | 875.462 s |
| Tool errors | 10 | 10 |

The turn duration spans `turn.started` to `turn.completed`, including tools
and waits. It does not measure isolated model thinking. Facet's interval is
1.381 times Plain's. One turn per arm is not a latency distribution. The
token ratio misses the 0.5 target and the wall-time ratio misses 0.6. One
task cannot establish the five-task headline or confidence bounds.

Plain's universal log records 1 passed and 12 failed, but setup and subsequent
cases report a closed Studio MCP connection. The required producer exits
with a host error and publishes no universal scores or dumps. That log count
must not be presented as measured UI quality. Missing universal audit inputs
also fail closed. Contract and optional strict type checks pass.

Plain's 27 diagnostic failures include 16 reveal or route failures, four
dependent balance or income assertions, four copy-sensitive boost or offer
assertions, one phone price-visibility assertion and two coherence failures.
The coherence scores omit return-control spread. These categories do not
establish that all failures are false positives; failed navigation can also
leave later checks in the wrong state. Facet still fails nine diagnostics.

## Native measurement limits

These are separate diagnostic `spec.perf` observations, not replacement
universal measurements. Both diagnostic returned flags are true on both
devices, despite Plain's failed Close and hub-reachability cases. The flags
do not prove that every tested navigation path succeeded.

| Device | Diagnostic metric | Plain | Facet |
| --- | --- | ---: | ---: |
| Desktop | Mount, s | missing: timed out | 3.007 |
| Desktop | Final Lua heap, KB | 692 | 968 |
| Desktop | Final GUI memory, MB | 30.678 | 34.171 |
| Desktop | Heap return ratio | 1.144 | 1.131 |
| Desktop | GUI return ratio | 1.005 | 1.020 |
| Desktop | Idle / active frame p50, ms | 4.175 / 4.137 | 4.097 / 4.099 |
| Phone portrait | Mount, s | 2.240 | 2.773 |
| Phone portrait | Final Lua heap, KB | 744 | 773 |
| Phone portrait | Final GUI memory, MB | 32.303 | 32.997 |
| Phone portrait | Heap return ratio | 1.401 | 1.071 |
| Phone portrait | GUI return ratio | 0.930 | 0.936 |
| Phone portrait | Idle / active frame p50, ms | 4.104 / 4.092 | 4.076 / 4.074 |

Diagnostic desktop Facet heap and GUI memory exceed Plain by 39.9% and
11.4%. All four diagnostic heap-return ratios exceed the per-arm 1.05 bound.
Phone Facet mount is 1.238 times Plain, above 1.10. Plain's desktop mount
times out with one sampled frame in the bounded settling window, so it
provides no successful mount-time denominator. Finite memory differences
do not establish an unbounded leak.

Facet's separate universal final heap is 901 KB desktop and 678 KB phone;
GUI memory is 34.790 and 34.037 MB. Its desktop heap-return ratio is 1.739,
above 1.05, while phone is 0.959. Plain has no matching universal values.
Do not substitute diagnostic values to manufacture that comparison.

Frame values measure `RenderStepped` cadence, not isolated UI CPU or GPU
cost. Earlier pairs switched between roughly 60 Hz and 240 Hz. The desktop
mount timeout and host failure further limit interpretation here. No causal
rendering-cost claim follows from these samples.

## Forfeits and separate visual diagnostic

The standard judge command exits zero with two Facet wins by forfeit because
Plain produced no universal screenshots. Both records have empty
`presentations`; no blind model comparison occurred. These are not visual
quality or polish wins.

A separate visual diagnostic completed under
`artifacts/facetbench/slice-sol61-medium-5-spec-visual`. Its predeclared inputs
use only the same saved `shop-1-hud` and `shop-2-shop` captures on both arms
and devices. Both arms passed shop opening on both devices. Every later
stage is excluded symmetrically because Plain navigation failed. Input image
hashes and the original brief are recorded before judging. Verify's public
judge compares both orders with Sol 6.1 Medium and the default rubric.

| Device | Image order | Overall | Polish |
| --- | --- | --- | --- |
| Desktop | Facet, Plain | Plain | Facet |
| Desktop | Plain, Facet | Plain | Facet |
| Phone portrait | Facet, Plain | Facet | Facet |
| Phone portrait | Plain, Facet | Facet | Facet |

Both device comparisons are consistent across order. Facet wins 1/2 overall
comparisons in this reduced scope, with polish favored in all four
presentations. On desktop, the judge favors Plain's HUD hierarchy, labeled
navigation, shop typography and currency colors, while crediting Facet's
denser part browsing and explicit shortfalls. Plain's footer obscures part of
its bottom shop row. On phone, the judge favors Facet's simultaneous display
of items, prices, ownership, actions and shortfall information; Plain clips
category tabs and shows little of the next item. Facet's shop still occupies
nearly the full screen. Plain retains HUD-grouping strengths and preserves
more world visibility in a judged view. One presentation notes that both
outputs lack a clearly distinct disabled state for an unaffordable purchase.

This reduced hub-and-shop comparison is separate from universal evidence.
It cannot establish quality across boosts, quests, offers or completed
purchase flows, replace the original forfeits, or repair the failed host
run. These screenshot judgments do not prove transaction behavior or general
library quality. This fifth pair does not establish the full or extended
suite goals.

## Follow-up: outgoing Sheet input

A disposable copy of the Facet workspace removed the four authored `C.show`
wrappers to test persistent Sheets. The saved evaluation workspace and scores
were not changed. Studio was maximized.

The default Shop-to-Close preview completed in 0.1254 seconds. The outgoing
modal remained parented with `Interactable = false`. Its dismissal button
still had `Interactable = true` and appeared first in native hit-test results.
An immediate native click activated Boosts once and the dismissal button zero
times. The old modal was still parented after that click. The reported
`action-covered` finding therefore did not describe native input blocking.

The probe now checks ancestor interactivity when classifying a blocker. With
the exact patched probe loaded in a fresh play session, an open modal still
blocked Boosts. Close followed by Boosts succeeded with no added wait or change
to settlement policy. The follow-up does not establish a new paired score or
measure a reduction in author time.

Native traces are in the isolated diagnostic worktree under
`artifacts/sheet-short-settle/native-hit-and-census.json` and
`artifacts/sheet-short-settle/native-patch-and-plateau.json`.

In that modified workspace, visiting four routes increased native StyleRules
from 29 to 59 and retained four disabled activation contexts. GUI class counts
returned to their initial values. Counts stayed constant over a further
12.2 seconds. Removing the authored wrappers changes ownership, so these
counts do not attribute the original pair's memory difference. They establish
a bounded retention lead, not a leak or a measured memory improvement.

## Follow-up: setup failure propagation

Required mount and idle probes now propagate their original error into the
host's existing device-failure handling. A native integration check injected
one failed response at the public session boundary. The first entry preserved
the exact error; a second entry was blocked with no additional execute call.
No idle or scene probe ran after the injected failure. A separate normal
native run completed mount, idle and scene sampling. Both owned Studios closed.

Evidence is in
`artifacts/facetbench/sol61-preflight/perf-required-boundary-35544/result.json`.
The injected response tests error handling. It does not reproduce or resolve
the original 120-second transport timeout.
