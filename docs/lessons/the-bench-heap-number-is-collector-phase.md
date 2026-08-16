# The bench heap number is collector phase, not retention

**Measured 2026-08-16, on `billboard-nameplate-storm`.**

`tools/lune/bench.luau` used to report `heapDeltaKb` — one `gcinfo()` before the
300 samples, one after, subtracted. It reads exactly like retained memory. It is
not, and cannot be, because **Lune has no forced collection**: `collectgarbage`
on this host accepts only `"count"`. `"collect"`, `"step"`, `"stop"` and
`"restart"` all raise *invalid option*. So the difference between two
uncollected readings is where the collector happened to be at two instants.

## What it cost

A `heapΔ=2659KB` reading on a nameplate scene was carried into a bug report as
"+2.6 MB of retained memory", with the reasoning that the harness also reports
*negative* deltas (`collection-mutation-custom` at `-3234KB`) and therefore the
sign must be meaningful. The negative numbers are not corroboration. They are
the other half of the same sawtooth.

## What the scene actually does

Thirty consecutive identical 300-sample windows, in one process, same source:

```
+1281, +678, -2050, +2163, -2397, +1942, +2012, -3055, +1954, -2437,
+1799, +1721, -2627, +1853, +922, -3653, +1117, +1175, +1283, -3409, ...
```

- mean **144 KB/window** (151 KB on the repeat run) — the single-window number
  overstated it about **17x**, and its **sign was noise**;
- swing **±3.7 MB**, roughly 25x the quantity it was supposed to report;
- the adapter's node count never moved off **3** for 9000 iterations;
- absolute heap ended at 8.5 MB. Retaining 2.6 MB per 300 iterations would have
  meant ~78 MB.

The tell that it is phase and not allocation: across a bisect scan the value
walked *smoothly* down — 2032, 1377, 1006, 840, 738, 443, 263, -581, -770 — then
**wrapped** to +2971 and walked down again. Retention does not wrap.

Sharpest demonstration: **the same commit, byte-identical source, read +2714KB
in one checkout and -580KB in another.** The only difference between them was
the directory path, which changed module-load string allocation just enough to
shift where the collector sat when the two samples were taken.

## The rule

- A heap number from a host that cannot force a collection is **allocation churn
  plus collector phase**. Never read one as retention, and never read its sign.
- Compare **nets across many runs**, or measure the thing that actually answers
  the question — here, the live node census, which was flat.
- The harness now publishes `heapNetKb` **with** `heapSwingKb` beside it, and
  prints a note naming how many scenes have swing exceeding net (it is usually
  most of them). A number whose uncertainty is larger than itself has to say so
  where it is read, not in a doc nobody opens.

## The sibling trap, same day

Two measurement harnesses in this investigation returned confident false data
the same way — by reading a **stale artifact** as a fresh measurement:

1. An A/B script copied a variant in, ran the bench, and read
   `artifacts/bench.json`. When the variant failed to load, the file from the
   *previous* variant was still on disk, so ten paired runs reported ten
   identical numbers and a perfect 1.000 ratio. Fix: `rm` the artifact first and
   fail loudly if it does not come back.
2. A probe measured a worktree that still had a **leftover diagnostic mutation**
   from an earlier A/B — the mutation had deleted the very span the probe was
   trying to count, so the probe "proved" a module-instance bug that did not
   exist. Fix: assert the tree is clean (`git status --short`) before believing
   a probe, and re-run the probe after restoring.

Both produced a coherent, plausible story. Neither was true. **A measurement
harness needs a check that it measured *this* run.**
