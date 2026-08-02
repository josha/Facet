# Milestone: exact text measurement (per-string engine premeasurement)

> **DELIVERED 2026-07-24** (stamp `51881654-858914`). Suite **936 -> 965**; gate
> `authoring-adaptive-ui` **19 PASS / 1 PENDING**, the PENDING being
> `physical-and-human-rows` only; five-view matrix re-driven and re-captured,
> `tools/check_matrix_rows.py` green. Result and everything found along the way
> are in **"What actually happened"** at the bottom of this file — read that
> before re-reading the plan, because two of its assumptions turned out to be
> wrong.

**Use this file as the opening prompt for a fresh session.** Everything needed to start is here;
nothing below needs re-deriving.

---

## The goal

Make LuauUI's text boxes match what the engine actually draws, without ever risking a clip.

Today the solver estimates text width from an average glyph fraction. It is deliberately
conservative so it can never under-reserve, and the cost is visible: action buttons reserve
**68px** for labels the engine draws in **46px**, because the estimator predicts a wrap that
never happens. Attempts to tighten the average clip real strings. The fix is to stop averaging
and measure.

---

## What is already true (verified live 2026-07-24, do not re-derive)

**The estimator's error is variance, not font.** The engine really is drawing BuilderSans —
`TextService:GetTextBoundsAsync` against BuilderSans matches rendered bounds exactly. Rendered
per-glyph widths at the shipped size:

| string | em/glyph |
|---|---|
| `Brightness` | 0.391 |
| `Save changes` | 0.422 |
| `Download` | 0.455 |
| `Volume` | **0.469** |

`src/client/text_calibration.luau` measures ONE long reference sentence, whose per-glyph average
regresses to the mean, and rides a `SAFETY = 1.08` margin. It applies **0.395**. Short UI labels
do not regress to the mean, so `Volume` got a 38px box for 38px of text and `TextFits` went false.
**An average-glyph model cannot bound a specific short string within 8%.** Raising the margin is
guesswork that trades clipping risk against fat boxes — that is why this milestone exists instead.

**The seam is designed but unbuilt.** `src/layout/text_metrics.luau`'s header already says:

> "The engine premeasurement queue (TextService) lives behind the same interface in the Roblox
> platform adapter, NOT here."

and its `Metrics` type already carries `state: "ready" | "pending" | "failed"` and `requestKey`.
**Nothing consumes any of it.** `requestKey` is produced and read only by one test asserting it is
non-nil. There is no queue, no cache, no re-solve. The only injection point is
`text_metrics.calibrate(font, fraction)` — **per-font, not per-string** — so today there is
nowhere to put an exact measurement even if you had one.

**Calibration is switched off on purpose.** `examples/gallery/client/init.client.luau` carries a
long comment explaining why, with these numbers in it. Do not re-enable it as a shortcut; it is
the thing that clipped text. It can be deleted once this milestone lands.

---

## Constraints that shape the design

1. **The solver must stay synchronous and pure.** `GetTextBoundsAsync` yields.
   `tests/layout.spec.luau` has "solves a frozen snapshot without mutation and double-solve dumps
   are identical" — measuring inline breaks both purity and determinism.
2. **`src/layout/` must stay engine-free.** The whole 936-test suite runs headless under Lune. No
   Roblox API may appear under `src/layout/`.
3. **Never under-reserve.** The conservative estimate stays as the first-frame fallback. Exactness
   is an improvement layered on top of safety, never a replacement for it.

---

## The design

Measure **words**, not laid-out strings.

The existing sketch keys a request as `font/size/maxWidth/text`. **Do not do that** — including
`maxWidth` means a cache miss on every resize and every device profile, turning a per-vocabulary
cost into a per-layout cost.

Wrapping is greedy over words. Exact word widths plus an exact space width give you exact wrapping
at *any* width, measured once and stable across every resize and every profile. Key the cache on
`(font, size, word)`.

Shape of the work:

1. **`src/layout/text_metrics.luau`** — add a per-string cache and an injection seam
   (`setMeasured(font, size, word, width)` or similar), consulted before falling back to the
   average. Keep it pure data, like `calibrate` is. Emit `pending` + the request set when a word is
   not yet known.
2. **Adapter-side queue** (client only, `src/client/`) — after a solve, collect the pending words,
   measure them with `GetTextBoundsAsync` off the render path, feed them back, and trigger exactly
   one re-solve. Batch; do not measure per node.
3. **Ordering** — first frame uses the conservative estimate (safe, slightly fat), the re-solve is
   exact. If a one-frame reflow is objectionable for a given screen, premeasure before `present`.

---

## Done means

- The action buttons in `adaptive_controls` reserve what the engine draws (~46px where the label
  fits one line), on every device row.
- `TextFits` is true for every painted node on all five rows. The only acceptable `false` values
  belong to the hidden `ViewThatFits` candidate, which has a zero rect and paints nothing.
- The five-view matrix is re-driven and re-captured; `tools/check_matrix_rows.py` passes.
- `lune run tools/lune/gate authoring-adaptive-ui` still reports **19 PASS / 1 PENDING**, the
  PENDING being `physical-and-human-rows` only.
- Suite grows from **936**; every new test verified to FAIL against the pre-fix source before being
  kept.

---

## Instrument setup

```
cd GameStudio/ui/LuauUI
lune run tools/lune/studio_sync              # serves current source on :8642
# then, in Studio via the MCP, Edit datamodel: run tools/studio/inject.luau
# set workspace.LuauUI_Scenario = "adaptive_controls", press Play
./run-tests.sh                                # headless suite
lune run tools/lune/gate authoring-adaptive-ui
python3 tools/check_matrix_rows.py
lune run tools/lune/check_prop_parity_cli     # if you touch any public prop
./tools/studio/capture_viewport.sh <out.png>  # real PNG of the Studio viewport
```

`workspace.LuauUIScenarioAPI` exposes `freezeEnv`, `setEnv`, `step`, `report`, `reset` as
BindableFunctions. `report()` returns geometry, `TextBounds`, `TextFits` and the solver's own
`diagnostics`.

---

## Traps that have already cost time — do not rediscover these

- **Do not read `instance.FontFace` to learn what is drawn.** It reads `LegacyArial` because it is
  never written, while `GetStyled("FontFace")` returns the sheet's BuilderSans and the engine draws
  BuilderSans. Compare `GetTextBoundsAsync` against candidate fonts instead.
- **Captures: window-only, never region.** `tools/studio/capture_viewport.sh` uses
  `screencapture -l<windowId>`, which reads Studio's own backing store. Never switch it to `-R` or
  full-screen — those read screen pixels and will pull in whatever else is on the display.
- **A 1×1 viewport means a blind instrument.** Check `workspace.CurrentCamera.ViewportSize` first.
  `open -a "RobloxStudio"` is the recovery that works; `activate` / `set frontmost` / a Play
  restart do not.
- **`adapter.create(rootHandle, path, class)` has no `props` parameter.** Style props arrive only
  through `setProp`, which the renderer calls at creation for everything in `STYLE_PROP_ORDER`.
- **Adding a public prop touches seven views** and `check_prop_parity_cli` enforces every one:
  schema, exported spec type, `render/authority.luau`, the adapter's create default, the adapter's
  `setProp` branch, and two places in `docs/reference/api.md`.
- **A green suite is not completion.** Eleven MAJOR defects have been found under a green suite in
  this stage alone. Prove each new regression fails against the unfixed source before keeping it.
- **Look at the picture.** Several of these were pure geometry sitting in a report nobody rendered.

---

## Context worth reading first

- `artifacts/authoring-adaptive-ui/NEXT-SESSION.md` — where the stage stands
- `artifacts/authoring-adaptive-ui/a-al4-preferred-text-sweep.json` — the full defect ledger,
  including every fix from the three director capture reviews
- `artifacts/authoring-adaptive-ui/matrix/five-view-matrix.json` — `textCalibration` records why
  calibration is off, with the measured numbers
- `src/layout/text_metrics.luau` and `src/client/text_calibration.luau` — the two ends of the seam

---

## What actually happened (2026-07-24)

**The result.** Every intrinsic text box now reserves exactly what the engine
draws: worst over-reservation across all five device rows is **0.5px**, which is
the `ceil()` on a half-pixel engine bound. Under the estimator the same nodes
were over by up to ~35px (`Settings`@22 reserved 109px for 66.5px of glyphs;
`Brightness`@16 reserved 100px for 62.5px). `TextFits` is true for all 38 painted
text nodes on all five rows; the only `false` values belong to the hidden
`ViewThatFits` candidate, which has a zero rect and paints nothing. Zero solver
diagnostics on every row.

**Built as designed, with one deliberate deviation.** Words, not laid-out
strings; cache keyed `(font, size, word)`; conservative estimate as the
first-frame fallback; one batched re-solve. The deviation: the plan said to emit
`pending` for an unmeasured word. `state` already means "the ESTIMATOR does not
know this font, so the box carries the full-em fallback" — every headless solve
depends on that and the layout dump records it — so overloading one field with
two unrelated facts was the wrong trade. Exactness rides its own `exact` flag and
the request set drains through `beginCollect`/`endCollect`.

Requests are collected **per solve by the surface that owns the solve**, not into
a module-level queue. A shared queue lets one surface drain the words another
surface asked for, and the surface that never sees its own measurement never
re-solves — a real bug in any app with more than one screen up.

### The thing the plan could not have known

`GetTextBoundsAsync` returns **different answers during the first moments of a
session** than once it has settled. It gives them without complaint, and it
gives them *stably*. The first premeasure batch runs on the very first solve —
the worst possible moment — and because a measured word is cached for the session
and never re-requested, the wrong widths were **permanent**.

Stored at boot: `Volume@16 = 47`, `Brightness@16 = 65`, `Download@14 = 54`. The
same call through the same module moments later: 45, 62.5, 51.

Ruled out, in this order: the MCP command VM disagreeing with the client VM (both
return 45 — this needed a `measureNow` instrument inside the runner to separate);
the font not being loaded (a never-used font measures identically on its first
and its hundredth read); a font-weight fallback (the boot values match none of
Regular / Medium / SemiBold / Bold). A stability gate — "measure a probe until
two consecutive reads agree" — was written first and **passed straight through
the bad window**, because the wrong answer is stable.

The fix is to re-ask: every batch is re-measured 1.5s later and any width that
moved is corrected, costing one more re-solve. After it, all 46 stored widths
match the engine's own answers exactly, including the space (3.5px at size 16,
derived as `bounds("x x") - bounds("xx")` because lone whitespace does not
survive into `TextBounds`).

It happened to over-reserve, which is the safe direction. Nothing guaranteed
that: a narrower wrong answer would have clipped every label in the UI.

### The thing the picture found

Exact measurement removes slack that was doing invisible work. The Slider row
used the generic 8px step and read fine only because every label's box was far
wider than its glyphs. With the box now equal to the glyphs, the round thumb —
which sits at the track's leading edge at value 0 — landed against the final "s"
of "Brightness". The director caught it in the capture. The row now declares its
own 16px clearance, because the shape it has to clear is its own; measured live
at 16.5px glyph-to-track on every row, and pinned by a regression that fails at
the old 8px.

### Standing lessons this run adds

- **An engine API can be wrong and stable at the same time.** "Wait until it
  stops changing" is not a readiness test. Ask again later and compare.
- **A cached measurement is a permanent one.** Anything cached for the session
  needs a verification pass, not just a plausible-looking first answer.
- **A measurement fix can expose a spacing bug the measurement error was
  hiding.** Look at the picture after tightening anything.
- **Separate "stale in time" from "different in context" before theorising.**
  Four wrong hypotheses died the moment the same code path was run twice in the
  same VM at two different times.

### No pop (director question, answered in the same session)

> "How do we handle the timing in practice with a real game? I don't want UI to
> pop. A lot of times the UI might not even be visible at first."

That last sentence is the design. Nothing should be measured while a player is
looking at it, and the loading window is exactly when nothing is visible. Two
halves shipped:

**1. Session warm-up.** `screen_target.new()` settles the engine's text pipeline
once, at construction — during loading, before any UI exists. After it, every
measurement is trusted on its first read, so no screen presented after loading
pays a delayed correction. Proven live (stamp `51881654-858914`): 74 words in one
session, all 42 corrections at the boot vocabulary's sizes (12/14/16/18/22),
**zero** at the ten-foot sizes (24/27/33) first measured after the warm-up
completed — and all 74 stored widths match the engine exactly.

**2. A reveal gate.** `present(screen, { revealWhenTextExact = true })` mounts and
solves with the root hidden and reveals the surface once the text round closes.
The adapter marks an untrusted early answer `final = false`, so the words stay in
flight and a gated surface cannot be revealed and *then* corrected. Bounded by
`revealTimeout` (default 2s) — a UI that never appears is a worse failure than
one that jumps — and an adapter without `setRootVisible` is simply not gated
rather than hidden forever.

The warm-up removes the pop for the common case with no per-screen opt-in; the
gate makes "never pops" a property a screen can rely on.

### Left open (unchanged by this milestone)

The Slider's `fillWidth`/`thumbOffset` memos read `trackRect`, which is a plain
upvalue rather than a signal, so they do not recompute when the solved track
geometry first arrives: at rest the accent fill is missing and the thumb sits at
offset 0 regardless of value. Verified **pre-existing** — the same behaviour is
visible in the pre-milestone baseline capture `D-4_desktop-standard_rest.png` —
and deliberately not fixed here, because it is a reactivity bug in a control, not
a measurement one.
