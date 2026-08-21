# Device capture — the third lever, `host-move` (2026-08-17)

ADR-0032 shipped the nested instance tree and, along the way, found and fixed a
real defect: moving a container inside a `ScrollView` used to cost **241 engine
`Position` writes** (120 descendants written once to a wrong value and once to
the right one) and now costs **1** (the host's own write — a hosted child's
`Position` is parent-relative, so it does not have to move when only its host
does). That number is measured, in Studio, with
`GetPropertyChangedSignal("Position")` — see
`artifacts/nested-instance-tree/live-probes.md` §4. It is a count of **engine
property writes, not milliseconds**, and the engine's own C++ descendant walk
— the work that still has to recompute every child's `AbsolutePosition` once
its host moves — is untouched and unmeasured. That is ADR-0032's own standing
risk: *"the engine still recomputes every descendant's `AbsolutePosition` in
the nested arm — that work moves from Luau into C++, it does not vanish."*

Nothing in the Performance Lab could press this question, because no workload
moved a container inside a host at all — the lab's existing `arrange-shapes`
lever isolates tree SHAPE, not hosting, and its `scroll`/`deepScroll` arms put
the *whole* tree inside a `ScrollView` with no unhosted control to compare
against. There is now a workload built for exactly this: **`host-move`**, five
arms, sitting right after `edit-locality` in the cycler. This is how to run it.

**Tier discipline, stated before anything else, because it governs how you
read every number below: headless Lune is a regression signal only, this lab
under Studio is the real engine, and a physical device is the only device
claim.** Everything the lab can assert on its own (headlessly and in Studio)
is that the workload provokes what it claims to provoke. Only a device dump
can turn that into a frame-time answer.

## First: reopen the place

`examples/places/Facet-PerformanceLab.rbxl` has been rebuilt from current
source (`python3 tools/check_perf_place.py`, which runs `rojo build
examples/performance.project.json -o examples/places/Facet-PerformanceLab.rbxl`
itself). **Close the copy you have open without saving and open the rebuilt
file.**

It now declares **seventeen** workloads. `host-move` is the third named
lever, sitting between `edit-locality` and `lifecycle-soak` at the end of the
cycler.

## The workload: `host-move`, five arms

Every arm reproduces the same shape `artifacts/nested-instance-tree/live-probes.md`
§4 measured: a list of fixed-height `UI.Box` cells (6 per row) with a header
above it whose height toggles **20 ↔ 60px every rep** — the commonest layout
event there is, something above a list grows — so the whole list's origin
moves every rep. What differs between arms is only whether that list sits
inside a `UI.ScrollView` (a host BY CONSTRUCTION — no `clipChildren` /
`opacity` / `scale` needed) or not, and how many rows it holds:

| arm | rows | leaves | hosted? |
|---|---:|---:|---|
| `hosted` | 20 | 120 | yes — the probe's own shape, for direct comparison to 241→1 |
| `hostedRepeat` | 20 | 120 | yes — the A/A control, byte-identically `hosted` run again |
| `unhosted` | 20 | 120 | **no** — same rows, same header, no `ScrollView` above them |
| `hostedLarge` | 100 | 600 | yes — 5× the rows |
| `unhostedLarge` | 100 | 600 | **no** — the same 5× rows, unhosted |

**`unhosted` is the control the number is worthless without.** A hosted-only
timing cannot say whether nesting bought anything; `unhosted` is the identical
tree with the one structural fact removed. **`hostedLarge`/`unhostedLarge` are
the N-sweep**: if the write-collapse is a real frame cost, `unhosted`'s
per-rep time should climb roughly with row count while `hosted`'s should not;
if neither arm separates from the other even at 5× the rows, that is the
answer, not a failed capture (see "the question" below).

Every arm carries its own structural oracle (`controller.scrollHostFor` on a
known leaf path, the same seam `src/controls/table.luau` uses to find the
`ScrollView` that actually moves a table's rows) — if an arm ever failed to
build the tree its name promises, it errors at `mount` rather than silently
handing back a tidy, meaningless number. You do not have to check this; it is
why the lab refuses to run instead of running wrong.

`Profile 1` defaults to arm **1/5: `hosted`**.

## The capture, step by step

1. Open the rebuilt place, press **Play**.
2. Cycle to **`host-move`**.
3. Press **Profile 1**. Watch the status line. It should read:

   ```
   PROFILING host-move/hosted · lap 2 · arrange=27 mount=0 react=NN resource=0 — DUMP NOW: ...
   ```

   (Until 2026-08-17 that line flashed past in milliseconds, because the
   counter-bearing version was written at the END of a lap and overwritten by a
   counter-less one at the START of the next. The counters now persist across
   the lap boundary and only `lap N` changes, so this is readable at a glance.
   If you are on an older build and it still flashes, that is the bug, not you.)

   **`arrange` IN THE TWENTIES is what matters before you spend a dump.** The
   lap is 24 reps at one arrange each, and the device read **27** on 2026-08-17
   — the extra few are the mount and settle solves the lap sits on top of. This
   note originally said "exactly 24" and that was over-specified; do not stop on
   27. **If it reads `arrange=0` or `arrange=1`, STOP.** The lap is inert (the scenario
   never cycled, the pass errored before its first rep, or Play was pressed
   before the place finished loading) and the capture would be worthless — the
   same failure mode that produced `asyncImage.html`'s twenty-nine
   byte-identical frames on 2026-08-15. Press Stop, re-cycle to `host-move`,
   and press Profile 1 again before spending a dump.
4. Let it run 3–4 laps, then **Ctrl+F6** (**Cmd+F6** where the keyboard has a Command key), **Ctrl+P** to
   pause, then **Dump → Dump in binary format**.
5. Press **Stop**. Press **Arm >** once — the status line reads
   `arm 2/5: hostedRepeat — press Profile 1`. Press **Profile 1**, dump again.
   This is the A/A control: state its spread before trusting anything below
   it, exactly as `flat`/`flatRepeat` and `editOffWindow`/`editOffWindowRepeat`
   do for the other two levers.
6. Press **Stop**. Press **Arm >** once — `arm 3/5: unhosted`. Press
   **Profile 1**, dump. **`hosted` vs `unhosted` at matched N is the whole
   point** — two dumps (step 4 and this one) is the minimum that answers
   anything.
7. Press **Stop**. Press **Arm >** once — `arm 4/5: hostedLarge`. Dump.
8. Press **Stop**. Press **Arm >** once — `arm 5/5: unhostedLarge`. Dump.
   This pair with `hostedLarge` is the N-sweep.

Five dumps is the full picture; two (`hosted` + `unhosted`) is the minimum
that answers anything, the same rule the other two levers use.

## What makes a capture worthless

**A dump taken while the status line reads `arrange=0` (or `arrange=1`)
answers nothing and should not be spent.** Concretely, on this workload that
means one of:

- you dumped before the first lap completed (the status line still reads the
  first `PROFILING host-move/hosted · lap 1 · ...` line with no `arrange=`
  segment yet — wait for a lap to finish, which is fast, well under a second);
- `Profile 1` was pressed on the wrong scenario (the status line names
  `host-move` explicitly — if it does not, you are profiling something else);
- the pass errored on its first rep and the loop broke (the status line would
  instead read `PROFILING host-move/<arm> FAILED on lap 1: ...` — if you see
  `FAILED`, that is itself the finding; report the error text, do not dump).

There is no version of this workload where a healthy dump reads `arrange=0` —
every rep provokes exactly one full solve by construction (mutation-tested;
see below), so `arrange=0` always means the lap never ran, never that the
effect being measured is zero.

## The question this capture is actually asking, framed honestly

**The effect may be small, and it may be at or below the noise floor — that
is itself the answer, not a failed capture.** The 241→1 number is a write
COUNT, unambiguous and already proven (Studio, this round). What is unproven
is whether that count difference is a *frame* cost, and the honest expectation
is modest:

- **At `hosted`/`unhosted` (120 leaves, the probe's own scale):** the
  per-rep delta a handset should show, if the write count is what dominates,
  is likely **well under a millisecond** — plausibly comparable to or smaller
  than this lab's own measured A/A noise band on similar per-node costs (2–4%
  on workloads of this size elsewhere in this lab). Do not be surprised if
  `hosted` and `unhosted` land inside each other's noise at this scale.
- **At `hostedLarge`/`unhostedLarge` (600 leaves, 5×):** if the mechanism is
  real and frame-relevant, `unhosted`'s per-rep cost should separate visibly
  from `hosted`'s here even where it did not at 120 — an unhosted list's
  absolute-position rewrite is O(N) in row count with nothing to cap it,
  while a hosted list's own write stays O(1) regardless of N. **A number
  worth writing down: does `unhostedLarge` cost roughly 5× `unhosted`'s
  per-rep delta over `hosted`, while `hostedLarge` stays close to `hosted`'s
  own number?** That ratio, not the absolute ms, is the falsifiable claim.
- **If `hostedLarge` and `unhostedLarge` still do not separate beyond
  noise:** that is ADR-0032's own stated risk landing exactly as written —
  *"if the engine's descendant walk turns out to cost what Luau's did, this
  ADR's headline shrinks to the compositing half."* The write collapse would
  still be real (it is not in question), but it would mean the engine's own
  C++ `AbsolutePosition` recompute — which runs for every descendant whose
  host moved, regardless of who wrote what — dominates the frame cost that
  the write count does not. That is a genuine, useful finding: the win is
  real but not frame-relevant, which is worth knowing precisely because it
  is the one outcome the Luau-side engine harness in ADR-0032 could not see.

Either outcome is a real answer. What would NOT be a real answer is a single
`hosted` dump reported alone — with no `unhosted` beside it at the same N,
there is nothing to compare the number to.

## Tier discipline, restated

**Headless Lune (`lune run tests/run`) is a regression signal only** — it
proves the five arms build the trees they declare (`scrollHosted` matches
`hosted`, both structurally and via the oracle) and provoke exactly one solve
per rep; every `*Ms` field is a synthetic 1ms-per-call stub there and means
nothing as a timing. **This lab under Studio is the real engine** — real
Instances, real property writes, real `Facet/*` MicroProfiler scopes — and
is where the numbers above should first be sanity-checked before a device is
spent. **A physical device is the only device claim.** A Studio number on a
desktop machine is not evidence about a phone or a console; it only proves
the workload is capable of being measured.

---

## RESULT — this capture was taken on 2026-08-17

Five dumps, four usable; `hostmove1.html` (arm 1, the A/A partner) came back with a
**zero-frame aggregate** and no timings, so **there is no A/A control spread** and the
N=20 numbers sit at the edge of the 6.7 % noise proxy.

**`Facet/commit` −18.9 % at 600 leaves (−2.05 ms/frame), −8.8 % at 120.** The scaling
prediction in this note held: hosted `commit` grows 2.94× over 5× the rows, unhosted
3.31×.

**The engine's relayout total is UNCHANGED** — the `Resizes = 3` on the Rendering root
is work re-attributed to the `ScrollView`'s own contexts, not removed. ADR-0032 §Risks
confirmed: the C++ descendant walk does not go away.

**And the arms carry a confound this note did not anticipate:** `unhosted` drops the
`ScrollView` entirely, so it is dearer in `commit` but much cheaper in `arrange`, and
the hosted arm is **more expensive overall** on this workload. Only the `commit` column
isolates hosting. The capture that would price this round's change properly is the same
hosted arm, **old build against new** — not another hosted-vs-unhosted pass.

Full analysis: `artifacts/nested-instance-tree/device-capture-2026-08-17.md`.
