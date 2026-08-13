# Proposal — a small rendered canary set in Studio

**Status: PROPOSAL. Nothing here is built.** Written for
[`swiftui-parity-round2.md`](swiftui-parity-round2.md) §Phase 6 step 4. It asks
for one decision: approve, shrink, or decline.

## The gap it closes

The headless suite (4569 cases, 42 s) proves what the *solver and the fake
adapter* agree on. Four defect classes this year got past it because they live
below that line, and each was found by a human looking at a screen:

| found | class | what the suite saw |
|---|---|---|
| RS-A16-D2 | an ornament's `overhang` reserved by nobody — a nameplate painted through the row above | every rect correct |
| device round 2026-08-12 | a padded `UI.Text` drawn flush against its plate's leading edge | the box included the padding |
| the same round | a scroll host's engine window narrower than its frame, so correct layout clipped | reserve = 0, as designed |
| 2026-08-04 | role-pick pop from a 1×1 first-frame viewport | nothing — the frame does not exist headlessly |

`tools/studio/visual_diff.luau` already reads what the **engine** resolved
(`AbsolutePosition/AbsoluteSize/Visible/ZIndex`/text) rather than what LuauUI
asked for, and is self-checked for stability. What is missing is a *standing,
small, gated* set that runs it — today every one of those numbers is captured by
hand during a mission and then goes stale.

## What exists already (nothing new is invented)

- `tools/studio/matrix_capture.sh <row-id>` → `artifacts/<gate>/captures/<row-id>.png`,
  printing `{capture, captureSha256_16, bytes}`. The rect is the Studio game-view
  pane, deliberately, so a phone capture cannot be a badly cropped desktop one.
- `tools/check_matrix_rows.py` — asserts a row's *invariants* (scroll canvas not
  short, zero solver diagnostics, action bar pinned and on-screen, 44 px floor,
  no content under the scrollbar, centring parity) **and that its capture is a
  real file with the recorded hash**. A row cannot claim visual evidence it
  cannot produce.
- `tools/studio/device_matrix.luau` — the driver that puts Studio into a row's
  device state and reports live geometry.

The proposal is a **fourth caller of these three**, not a new pipeline.

## The set: 6 canaries, 8 captures

Chosen so that each one would have caught a defect that actually shipped, and
no two would catch the same one.

| # | canary | viewport | why this one |
|---|---|---|---|
| C1 | gallery **All controls** | phone portrait 320×640 | every control on one screen at the narrowest supported width — the padded-text and text-fit classes |
| C2 | gallery **Playlist table** | desktop 1232×1067 | table chrome, header, scrollbar reserve — the content-under-the-bar class |
| C3 | **Sponsor results** (`sponsor_scenarios`) | phone landscape 640×320 | the production consumer, in the orientation that hid a whole table below the fold |
| C4 | **ornate theme** row set (`theme_matrix_audit` row config) | desktop | chrome overhang, `contentInsets`, bar geometry — RS-A16-D2/D3/D4 are all here |
| C5 | **row actions** open tray (`row_actions_scenario`) | phone portrait | the slide is painted by the presentation channel, which the fake adapter models but does not draw |
| C6 | **large text** — C1 again at preferred-text-size 14 | phone portrait 320×640 | the accessibility swing, where reserved-vs-drawn disagreements surface |

Eight captures: C1 and C6 are the same surface at two text sizes (2), C2–C5 one
each (4), plus **two `visual_diff` self-check pairs** (C1 and C4 captured twice
in one session, required to diff to zero) — because an instrument that has not
been shown stable under no change reports every real comparison as a failure.

**Per canary, the evidence row is:** the `visual_diff` engine-geometry dump, the
PNG plus its sha256, `controller.diagnostics()` (must be empty), and the row
identity (place build id, viewport, preferred text size, theme package).

## What the gate checks — and what it does not

A new `tools/check_canary_rows.py`, shaped exactly like `check_matrix_rows.py`:

1. all six rows present, each with a capture file whose hash matches;
2. `solverDiagnostics == 0` on every row;
3. **engine geometry equals the headless solve** for every node, within 0.5 px —
   this is the assertion the suite structurally cannot make;
4. the two self-check pairs diff to zero;
5. the row's build identity matches the committed `.rbxl` build stamp, so a
   stale capture fails instead of passing quietly.

**It is not a pixel-diff.** Pixels tell you *that* something moved; the geometry
dump tells you *which node* and *by how much*. The PNGs are for the human review
packet and for the hash chain, not for an automated comparison — a pixel
baseline across Studio versions, GPUs and font packs is a flake generator, and a
flaky gate check gets disabled, which is worse than not having it.

**It closes no physical row.** Studio emulation is Studio emulation; the standing
`phone-physical` / `console-physical` pendings stay open and unclaimed.

## Cadence: gates only

Not on `./run-tests.sh`, not on commit, not in the fast tier — it needs a running
Studio and a human-started session, and a check that cannot run headlessly must
never be in the path that everyone runs.

**Refresh at:** every mission gate that touches the renderer, the solver's arrange
branches, chrome/theme paint, or a shipped screen. Roughly one session per
mission. Between refreshes the committed rows stand as evidence, and rule 5 above
means a stale row fails rather than lying.

## Cost

- Build: ~1 session (the checker plus one recorded run to establish the rows).
- Per refresh: ~15 minutes of Studio time (the driver already automates the
  device-state switch; captures are one command each).
- Standing cost to the suite: **zero** — nothing here runs headlessly.

## The honest risks

1. **A stale set is worse than none.** Mitigated by check 5 (build-identity
   binding) — a row that no longer matches the committed build fails.
2. **Six rows is a sample, not a proof.** They are chosen against defects that
   really shipped; they will not catch the seventh class. The claim is "these six
   surfaces render as the solver says", never "the UI is correct".
3. **Studio-version drift** can move engine geometry under the 0.5 px tolerance.
   Then the run fails, a human looks, and the baseline is re-recorded with a
   written reason — the same discipline the device matrix already uses.

## Decision requested

Approve as scoped (6 canaries / 8 captures / gates-only), shrink to C1+C2+C4
(the three that map to shipped defect classes with no overlap), or decline and
keep relying on per-mission manual capture.
