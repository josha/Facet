# `UI.Foreign` — what a surface that uses none of it pays

**ADR-0034.** The claim under test: *a surface using no `UI.Foreign` must not pay
for it.* This file is the measurement and, for the two seams a headless
instrument cannot reach, the structural argument with its reason.

## Every place an off-path node meets this feature

| Site | Before | After | Frequency |
|---|---|---|---|
| `renderer.ensureTree` decoration-hint pin | `if node.class == "Stage" then` (one string compare) | `if NO_DECORATION_CLASSES[node.class] then` (one table index) | **per node created** |
| `screen_target.buildHandle` | — | `if class == "Foreign" then` (one string compare) | **per node created**, engine only |
| `screen_target.parkEligible` | — | `if handle.foreignBox ~= nil then` (one field read) | per park attempt |
| `blueprint_schema` `CLASSES` | 26 entries | 27 entries | **once, at module load** |
| `schema.refusal` | one table index | two table indexes | **only on the error path** — reached from `unknownPropError`, i.e. never in a working program |

Two of those are not measurable in principle: a table entry built once at load,
and a branch that only executes while constructing an error message. The rest are
below.

## The measured one: the hot mount path, A/B/B/A/A/B/B/A

The renderer's per-node pin is the only change on a path an off-path surface
actually runs. **Control first.** Scene: 301 nodes (60 rows × swatch/label/button/
image), **zero of them `UI.Foreign`**; mount + attach + `initialRender`; 200
samples per run; 20-iteration warm-up; alternated ABBAABBA so linear machine drift
cancels in both directions.

```
  A  p50=3.8046ms  p95=4.3011ms
  B  p50=3.7887ms  p95=4.1779ms
  B  p50=3.8721ms  p95=4.3259ms
  A  p50=3.7392ms  p95=4.0772ms
  A  p50=3.8221ms  p95=4.2588ms
  B  p50=3.7759ms  p95=4.1452ms
  B  p50=3.8803ms  p95=4.4041ms
  A  p50=3.7790ms  p95=4.2208ms

A = CONTROL  `if node.class == "Stage" then`
B = SHIPPED  `if NO_DECORATION_CLASSES[node.class] then`

A: p50 median-of-runs = 3.7918 ms   runs 3.7392 – 3.8221  (2.2% spread)
B: p50 median-of-runs = 3.8304 ms   runs 3.7759 – 3.8803  (2.8% spread)

DELTA p50  +1.02%   (+0.0386 ms over 301 nodes = +0.128 us/node)
DELTA p95  +0.29%
```

**Verdict: indistinguishable from zero at this instrument's resolution.** The two
arms' run ranges overlap — B's fastest run (3.7759) is faster than A's slowest
(3.8221) — so the +1.02% median difference is smaller than the within-arm spread
and cannot be attributed to the change. It is reported rather than rounded to zero
because a directional reading inside the noise band is still the honest number.

**One instrument note, because it cost a run.** The first attempt normalised each
scene against the bench harness's LuauUI-free CPU yardstick. One run's yardstick
came in at 1.3432 ms against a ~0.56 ms baseline — a 2.4× machine-load spike — and
the normalisation *amplified* it into a fictitious +34% delta, because the
yardstick is pure arithmetic while `mount` is allocation-heavy and the two do not
respond to load the same way. Raw milliseconds under balanced alternation is the
correct instrument for a change this small. (Superseded run kept in
`offpath-headless.txt` history; the file now holds the ABBAABBA output above.)

## The two the headless instrument cannot see

**`buildHandle`'s new `if class == "Foreign" then`.** Engine-only, so Lune cannot
reach it. It is one string equality against a constant, inside a function that
already performs an `Instance.new` plus ~6–20 property writes — measured on this
project's own performance lab at **~12.4 µs per inert container** (the number that
justified instance elision). One compare is on the order of tens of nanoseconds:
roughly **0.2% of one node's cheapest construction**, and `buildHandle` is not the
cheapest thing in a frame. The Studio A/B for this is recorded in
`live-verification.md`.

**`parkEligible`'s new field read.** One `~= nil` on a table field, in a function
that already performs eight of them, and it runs only when the recycler considers
a node — not per frame and not per node.

## Why the shipped form is not *more* expensive than the control

The natural way to add a second never-decorated class is `if node.class == "Stage"
or node.class == "Foreign" then`, which makes the off-path node pay **two** string
compares where it paid one. The table lookup pays **one index** whatever the table
holds — so the change is flat in the number of members, and the `Stage` compare it
replaced became an index too. A third class costs nothing further.
