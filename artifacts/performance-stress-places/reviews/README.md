# Fresh-context reviews — performance stress places (roadmap Step 9)

Four independent reviews, each given the goal, the acceptance ledger, the changed
source and the raw artifacts — and **not** the implementer's conclusions. Dispositions
are in [`../decisions.md`](../decisions.md) as **PLN-8** (architecture, reactive
runtime, platform) and **PLN-9** (phase gate).

| Review | Authority it covers | Report |
|---|---|---|
| **Phase-gate** | The claimed status of every PL row against what the artifacts actually show; whether any gate check can fail | [`phase-gate.md`](phase-gate.md) |
| **Architecture** | The new `src/core/profile.luau` and its containment; the nine call sites; **the per-solve measure memo**; the example surface and the `ctx.host` / `ctx.lab` passthrough | [`architecture.md`](architecture.md) |
| **Reactive runtime** | The flush-body hoist and `transaction`'s span; the resource-provider wrapping; mount/dispose ordering; the lab's cell-scope and data-scope ownership | [`reactive-runtime.md`](reactive-runtime.md) |
| **Roblox platform** | `debug.profilebegin`/LibMP against current first-party guidance; the mobile-MicroProfiler procedure; the place's publish safety; whether the native reference is a fair floor; the device matrix | [`roblox-platform.md`](roblox-platform.md) |

## What they changed

**They earned their keep.** The architecture review found a **BLOCKER** the whole
automated apparatus missed — a 3 366-case suite, a headless perf gate and six live
Studio sessions were all green over it — and it did so by building a differential
oracle (two copies of `src/`, one with the memo bypassed, 800 seeded trees diffed
node by node) rather than by reading harder.

> `cases=800  rectDiff=0  textFactsDiff=12  compactDiff=3`
>
> Geometry byte-identical. `compact` flipped on 3 trees, `textFacts` on 12 — including
> `truncated` going **true → false**, which is what gates full-value disclosure. A cut
> label would have silently lost its accessible full value, with nothing looking wrong.

That is now fixed (the cache replays its verdicts), verified with the reviewer's own
fuzz (`textFactsDiff=0 compactDiff=0`), and pinned by
`tests/measure_memo.spec.luau` — built from the review's auto-shrunk trees and
mutation-proved to redden when the replay is removed.

The platform review corrected four more things that would otherwise have shipped
wrong: profiling defaulting **on** in production (truncating tracebacks in every game
that consumes LuauUI), a `LuauUI/scenario` scope held open across sixty Heartbeat
waits, a mobile-MicroProfiler procedure that was wrong in three places, and an
unproven "no private asset" claim.

## The second thing they caught

The phase-gate reviewer found a **gate check that had frozen a wrong fact into place**:
`check_perf_gate_evidence.py` asserted `len(timers) == 8` against an artifact claiming
eight scopes were "the whole closed set", while the module declared **nine**. Appending
the truthful ninth timer would have *reddened* the gate. The check now reads the
declared set out of the source. A check that asserts a magic number instead of reading
the source is not a weaker check — it is a check pointing the wrong way.

It also caught a "reused, not forked" assertion that compared a file to itself, a
developer path hardcoded inside the tool that refuses developer paths, and an
admissibility rule that refused `"unknown"` but accepted `"uncapped/unknown"` — which,
once tightened, immediately exposed that every capture row carried a non-answer for its
frame target.

## The one methodological lesson

The measured cause was right, the fix direction was right, the gates were green, and
the change was **still** wrong in a way only a differential oracle could see. A cache
placed in front of a function with *published side effects* needs a differential
check, not a spot assertion — and this repository's own rule about tests that cannot
fail applies to the regression written afterwards too: the first version of
`measure_memo.spec.luau` passed against the broken solver, because it transcribed the
tree's dimensions under the wrong field names. It was kept only once the mutation was
seen to redden it.
