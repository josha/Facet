# Release-candidate review — final report to the director (2026-08-21)

**Verdict: the stage gate PASSES.** Framework suite **6892**, Rascal Rally
**3449**, gate green on every row except the two device-only rows that are
non-blocking by design (`df7-modifier-sink-measured`,
`haptics-device-similarity` — both on your device list below). Nothing has been
published; publishing remains your manual click.

## What this stage shipped

- **The rename**: LuauUI → Facet, history-preserving, drift-guarded
  (check_brand_drift with link-graph scope), RR consumer moved in lockstep,
  attribute migration isolated with its manifest.
- **~250 review findings** fixed or dispositioned across five independent
  review dimensions, two fresh-agent exercises, and a whole-campaign final
  review whose NOT-READY list is now fully closed.
- **Your eight live bug reports** (DIR1–4) fixed with regression guards, each
  round independently reviewed and re-reviewed to "all findings addressed":
  device clipping, themed HUD overflow/overlap, table column loss, rotation
  loss, empty expand pills, opaque-over-screen transients, bezel-eaten console
  chips, shoulder discoverability + one-press-one-action.
- **Input**: IAS authoritative (FACET_BASE_SCREEN_PRIORITY ceiling,
  check_input_authority guard); chrome doors on the bumpers with painted LB/RB
  hints; ButtonY returned to the menu verb (R20).
- **Adaptation**: the full default-paradigm audit + fixes (tables collapse by
  priority into a disclosure; carousels snap with peek; the Apple-TV-style
  ten-foot metric ladder at 1.5× with overscan, lane caps, distance rungs —
  verified live on the console row this session).
- **Sensory**: original Custom-waveform haptics (contact/settle/tick),
  engine-owned press, calibration surface — wiring proven live; feel stays
  PENDING_DEVICE.
- **Memory/API**: lazy Controls (228 KB [131..313] deferred) with a
  require-interception pin that actually bites; typed surface gated by
  luau-lsp + check_types; themes unbundled from the library into loadable
  packages; docs rebuilt (vendor 724→0; comment codes 531→25 resolvable).
- **Performance requalification**: headless complete + all 13 Studio capture
  rows landed this session (desktop-standard, profiler staleness-asserted):
  both owed re-captures confirm the incremental fixes on the engine
  (arrangePerEdit/PerGrow = 1), hosted beats unhosted 9.8 vs 12.9 µs/leaf
  (ADR-0032 answered), 12-cycle soak byte-identical counters,
  require(Facet) = 4.7 MB Studio heap. Remaining: .gprx dumps (no scripted
  route; LibMP aggregates recorded) and the low-end Android row.

## Rulings — every one open to your veto

| # | Ruling | Cost if you veto |
|---|---|---|
| R1 | Work in-place on main, both repos (gate system can't run in a worktree) | none now — historical |
| R2 | Your six modified docs/plans files committed as the plan-freeze commit | historical |
| R3 | No `skills/use-luauui` existed; Step 14 creates `use-facet` fresh | Step 14 scope |
| R4 | Freeze reorder: baselines, collision, inventory before edits | historical |
| R5 | RR Studio canary captured in the same session as the RR-side rename | historical |
| J-2 | Two tracked `__pycache__` .pyc files untracked | none |
| R6 | Step 14 packet is the one holder of the pre-rename URL | doc indirection |
| R7 | T6 (drift guard/ADR/packet) executed by controller, audited by final review | historical |
| R8 | No ScreenInsets/SafeAreaCompatibility property flips in the sweep | re-open sweep |
| R9 | VALUE-bearing text follows the standing localization rule | re-style pass |
| **R10** | menu.luau pinned as DK-16's third file (platform menu keys) | unpin + retest |
| R11 | `luau-*` tags → `facet-*` outright (pre-public window, no alias) | alias pass |
| R12 | world.luau: substrate + drift-hazard files only | broaden scope |
| **R13** | ~~radii/strokes must-NOT-scale at ten-foot~~ **fully superseded by the director (2026-08-21): radii AND strokes scale in lockstep with metricScale via sheet generation (the exact seam R13 pointed at)** | — |
| **R14** | Ten-foot measure cap = 900px (tablet 600 × 1.5 proportion doctrine) | one-liner + re-verdict |
| **R15** | Pre-release breaking changes ride unreleased 0.10.0 with an ADR-0040 record, no compat shims | shim work |
| R16 | Vendor scope = link-reachable from the shipped doc surface | broaden scan |
| R17 | RC-18: unexplained internal shorthand is a defect in maintained comments | relax check |
| **R18** | The 44px hit-floor is EXEMPT over passive content, BANNED over interactive; fence reads both rects; solver-side reserve booked to the extraction charter | fence redesign |
| **R19** | The bumpers are the chrome's pad doors; framework Adjust yields. TRUE COST (measured): a legacy-state adjust target (TabView, Table) keeps NO pad step keys while showcase chrome is mounted — D-pad stepping only applies to non-legacy targets | rebind chrome |
| **R20** | ButtonY leaves the chrome entirely — menus own Y (platform convention); keyboard keeps Backquote; TOGGLE_GAMEPAD deleted under R15 (ADR-0040 B-14) | re-add a pad toggle key |

## Design calls that are yours, not mine

1. **Modal ties the chrome band (3500)**: a modal demo with a focused adjust
   target still double-fires a shoulder. Fix is a framework band re-spacing —
   deliberately not made mid-stage. (Also note `TOGGLE_PRIORITY = 3501` exists
   as an example escape hatch.)
2. **Native-style default flip** (`native_style.DEFAULT_ENABLED`): your call at
   the Step 14 checkpoint; the promotion tracker now names you as owner.
3. **Should TV chrome radii/strokes scale?** (§13f) — **DECIDED, both halves
   (2026-08-21): radii and hairline strokes scale in lockstep with
   metricScale**, via sheet generation; implementation round queued behind
   the native-default flip.
4. **Is 1.5× right at three metres?** (§13g) The zoomed console capture is
   banked; a different answer is one line at `themes.metricScale`.
5. **Celebration-Space** design note (from the earlier waves) stands open.
6. **ADR-0040's 0.10.0-boundary question** as written in that ADR.

## Your device half (the packet, updated)

Republish the showcase first (it now includes everything above). Then: the
DIR1–4 device rechecks (chips inside your TV's bezel; expand plate over live
screen + X close), carousel flick/peek, adaptive_controls at Largest, the
haptics paired-iPhone packet (feel the three profiles; press row), DF-7 real
keyboard modifier sink, RR sponsor on pad + touch driving §7c, the ten-foot
1.5× judgment on the real television, **the shoulder raw-delivery check on a
real pad** (L1/R1 open/switch/close; one press = one action; Y opens the menu
demo's menu, not the chrome; B closes — injection can prove none of these),
and the low-end Android §12.5 capture when convenient.

## The debt, owned

The extraction charter (post-stage): presenter/solver/renderer/virtual_list/
table seams, with every booked rider in
`artifacts/release-candidate-review/t16-triage.md` — including the solver-side
hit-floor reserve (R18's ban is fixture-enforced until then) and the
presenter.raise/displayLayer seam (the layer-climb horizon is halved and
documented until it lands).

## Step 14

The remote packet (`step14-remote-packet.md`) is ready: remote creation,
distribution artifacts, `use-facet` skill, the default-flip checkpoint.
Nothing has been pushed, published, or packaged — those are yours.

---

# Post-close addendum — the two days after the gate (2026-08-21 → 22)

**The gate re-passed at the end of it all: 23 rows green, the same two
device-only rows environmental by design.** Suites Facet **7,062** / Rascal
Rally **3,470** (from 6,892 / 3,449 at close), every round independently
reviewed, every review finding fixed or ruled.

## What landed

- **All three size-frozen files split free** (solver 197.8k→188k, renderer
  199k→182.5k, plus the plate/table seams), each with byte-identical
  differential proof and zero test edits. The freed room paid for:
- **Containment by construction**: hug arithmetic composed in one solver seam;
  a settle-time containment diagnostic; the harness invariant on by default in
  every test (calibrated: it reds on the historical "9" bug verbatim and found
  a second unseen overflow); sweeps now open popups/menus before judging.
- **The hit-floor law, finished** (ADR-0041): grows-until-pressable, stops only
  at AUTHOR-declared sinks (R23), covers and the corner close both in the
  class, blast radius pinned at matrix scale — zero framework tap-theft.
- **Director decisions built**: style-sheets default (with the rollback flag
  proven un-deletable), radii+strokes on the metric ladder by derivation (both
  paint doors verified on glass), plate Option B tangent-exact on both
  presentations, ButtonY back to menus, primary-input-gated shoulder hints
  with the house deadzone.
- **The purity work**: the teaching corpus now 12.6% raw literals (was 39.4%,
  game is 22%) under a standing lint; 353 swaps proven value-identical; the
  ten-foot drift class caught, fixed, and detector-guarded; 7 live defects
  fixed; the 34 MOVE gaps ranked for the phase-2 pick.
- **Gate infrastructure hardened**: every run string bash-parsed (a dropped
  quote had hidden 22 checks), four proves-nothing calls replaced, one lint
  that had never run now runs, the flat-theme baseline reconciled by
  characterization (not re-pinning), the nav gate 14/14, prior sweep 28 PASS.

## New rulings for veto (joining R1–R17)

| # | Ruling |
|---|---|
| R18 | Hit floors: exempt over passive content, banned over interactive |
| R19 | Bumpers are the chrome's pad doors; Adjust yields (its true cost documented) |
| R20 | ButtonY belongs to menus; the chrome's pad toggle is gone |
| R21 | RR's tri-state nativeStyle flag (rollback preserved) |
| R22 | Source pins guard accidents, not sabotage; the behavioral canary is the terminator |
| R23 | A floor stops only at author-declared sinks; framework affordances arbitrate by z |

## Still yours

1. **The RR Studio canary** — a gate row now formally demands it (this week
   changed visible behavior); open the RR place once and I run it.
2. **The device packet** (unchanged list + the shoulder raw-delivery check).
3. **The phase-2 pick**: the 34 framework gaps, top six ranked in the audit.
4. Republish the showcase when you want the current build on devices.
