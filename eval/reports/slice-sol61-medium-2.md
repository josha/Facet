# Sol 6.1 Medium slice, second attempt

This attempt does not establish the efficiency or overhead goals. The Facet
author stopped with a provider capacity error before a completed turn. Its
reported zero tokens mean missing usage, not zero cost. Do not advance to the
full suite from this result.

Both arms ran fresh at Facet `1b092c70`, one task, seed 1, sequentially, with
Sol 6.1 Medium. Author and check Studios were maximized. Source and kits stayed
fixed throughout the attempt. Other local tests and benchmarks stayed idle.

Evidence: `artifacts/facetbench/slice-sol61-medium-2`. The saved results and
transcripts are unchanged. The first complete pair remains separate in
[its report](slice-sol61-medium.md).

| Measurement | Plain | Facet |
| --- | ---: | ---: |
| Universal checks | 1 / 13 | 13 / 13 |
| Diagnostic spec checks | 27 / 49 | 32 / 49 |
| Author wall time | 902.75 s | 488.10 s to failure |
| Total tokens | 4,404,469 | Missing |
| Completed author turns | 1 | 0 |
| Tool calls | 125 | 69 |
| Tool time, union | 366.94 s | 249.98 s |

Plain completed its author turn in 901.51 seconds. Facet's transcript ends
with `Selected model is at capacity. Please try a different model.` followed
by `turn.failed`. It has no completed-turn usage or latency evidence.

The saved Facet result incorrectly reports `status = "completed"` and
`passed = true`. Verify's adapter ignored the explicit transcript error,
then the runner accepted the passing required checks. This is an adapter
classification bug. Passing UI checks do not prove author completion. The
Facet headline already rejects missing token or latency evidence.

## Native measurements

These are raw universal-check measurements of the saved outputs. Facet's
output is partial author work. Both arms reported successful return to root.

| Device | Metric | Plain | Facet | Facet / Plain |
| --- | --- | ---: | ---: | ---: |
| Desktop | Final Lua heap, KB | 677 | 583 | 0.861 |
| Desktop | Final GUI memory, MB | 30.188 | 33.794 | 1.119 |
| Phone portrait | Final Lua heap, KB | 637 | 831 | 1.305 |
| Phone portrait | Final GUI memory, MB | 32.907 | 33.496 | 1.018 |

Desktop GUI memory and phone heap exceed the 1.05 limit. Facet's phone heap
also grows 30.25% from its own idle baseline. These samples do not prove an
unbounded leak. Plain hides panels while retaining their children; its UI
census grows from 61 to 221 instances on both devices. Facet's GUI count
grows from 71 to 72.

Plain's desktop idle window contains 120 frames in two seconds; its final
window contains 480. Phone and active-screen windows also switch between
about 60 Hz and 240 Hz. The collector observes `RenderStepped` deltas. These
values measure frame pacing and cannot by themselves establish UI frame-cost
overhead. The saved metadata does not identify the cause of the cadence changes.

## Follow-up

Verify the native CPU and GPU rendering counters before using them as cost
evidence. Preserve the existing pacing and memory limits. Then run another
fresh pair with the same requested model and effort.

Verify [PR #5](https://github.com/voidmeld/verify/pull/5), commit `741c6d0c`,
now rejects terminal author errors through one live and replay classifier.
Its focused tests and 19 portable producers pass. Native producers are deferred
because the change does not alter native execution. Its documented configured
Claude turn-limit exception remains explicit.

Replaying this attempt's actual Facet transcript through that public adapter
returns `failed` with the capacity error, even with an assumed child exit code
of zero. The exit code was not saved in the original result. The derived receipt
records that assumption and input SHA256
`52de4ac7b8b2e2107621d878156e06388f77825f522ddead3420096600d7dcd9`.
It is in `artifacts/facetbench/sol61-preflight/replay-capacity-receipt.json`.

The short collection recipe now uses the existing `mode = "all"` API. A separate
native probe ran 18 cold-start and empty-transition variants at three widths.
The previous windowed, content-sized recipe stayed at zero height with no rows.
The corrected recipe rendered both rows, collapsed when empty and recovered on
refill. A bounded windowed control continued to work. Large collections still
use bounded windowed viewports; no collection implementation changed.

The Sheet recipe now distinguishes an intrinsically sized short body from a
full-height NavigationStack. The latter uses a bounded detent. The exact recipe
passed native desktop and portrait open, child-page, Back and Close checks with
no offscreen or safe-area findings. Applying `hug` to that full-height stack
filled the available room in a separate diagnostic, so that option is not in
the NavigationStack example.
