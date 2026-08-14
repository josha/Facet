# SwiftUI parity round 3 — the owed ledger, status-anchored

The `Still owed, ranked` table of
[`docs/plans/swiftui-parity-round3.md`](../../docs/plans/swiftui-parity-round3.md)
carried into a form a gate can read. Every row of that table is here, in its
original rank order, plus the items round 3 itself created.

**What this file is for.** The round-3 gate's `owed-ledger-honest` check reads it
so that closing an item silently is a gate failure rather than an edit nobody
notices. The status vocabulary is the repo's:

| Status | Meaning |
|---|---|
| `CLOSED_ROUND3` | closed by this round, with live evidence named in the row — the check verifies the named evidence file exists |
| `OPEN` | still owed, headless-closable, nobody has taken it |
| `PENDING_HUMAN` | needs a human in a Studio session; cannot be closed from a desk |
| `PENDING_PHYSICAL` | needs real hardware (a phone, a pad); no emulator substitutes |

**What this file is NOT.** It is not a claim that the `OPEN` rows are still
broken. A check written that way goes red on the day somebody legitimately fixes
one — the failure mode `tools/check_traversal_evidence.py`'s own docstring was
written about — and would then be edited to agree with the change. The
`CLOSED_ROUND3` rows are the half that is asserted; the rest is a to-do list the
gate refuses to let anyone quietly shorten.

## The brief's ranked table (round-3 design, "Still owed, ranked")

| # | Item | Status | Evidence / blocked on |
|---|---|---|---|
| **O-1** | `traversal-document-order` re-record | `PENDING_HUMAN` | `tools/check_traversal_evidence.py` still exits 1 (`STALE EVIDENCE`). The fix is a re-record in Studio under Play, not an edit. Guarded by the gate's `traversal-evidence-red-carried` row; booked in `docs/plans/device-bug-round-2026-08-12.md` |
| **O-2** | Places were stale | `CLOSED_ROUND3` | all fifteen rebuilt; `examples/places/LuauUI-Showcase.rbxl`. The underlying defect (no build stamp; nothing compares a `.rbxl` to its sources) is booked, and O-15 is the one place this round left un-rebuilt |
| **O-3** | Studio device canary on the rebuilt showcase | `PENDING_PHYSICAL` | never run. Everything round 3 shipped is headless-green only. The gate's `studio-device-canary` row carries this as `FAIL_ENVIRONMENT` rather than pretending |
| **O-4** | Chrome unreachable by keyboard and gamepad | `CLOSED_ROUND3` | `tests/gallery_chrome.spec.luau` (38 cases, 27 mutations); `examples/gallery/client/showcase_chrome.luau` |
| **O-5** | `api.md` round-2 prose skim | `CLOSED_ROUND3` | `docs/reference/api.md`. Closed 2026-08-13 by the agent that owned the file, and the closure carries its own finding: the row's promised "12 concrete defects, listed below" **never existed** anywhere in the repo, so the skim was redone from scratch against a live schema dump and found **15**, including `recycleInstances` and `incrementalLayout` — ON BY DEFAULT and documented nowhere. D3's own documentation defect 1 (`rowSelectable`/`rowMovable`/`rowDeletable` absent from api.md) is closed with it |
| **O-6** | Shrink gap (a): a shrinkable label can land outside its box | `OPEN` | needs a ruling; measured in the round-3 design |
| **O-7** | Shrink gap (b): `shrinkWeight` flips the `ViewThatFits` winner at 10 of 28 widths | `OPEN` | needs a ruling; round 2's §2.4 claim is false and is recorded as such |
| **O-8** | Table tray-focus: trays are in no focus group | `OPEN` | headless; `buildFocusGroups` collects inside the Row node, trays are its siblings |
| **O-9** | Keyboard/pad Delete on an unswiped hosted row | `OPEN` | headless; the fix is priced (lazy engines mean no engine exists until a swipe) |
| **O-10** | A BLOCK table publishes a scroll path it has no host for | `OPEN` | headless + a ruling; the crash half is fixed, the design half is live in the playlist example |
| **O-11** | Reduced-motion settings surface | `CLOSED_ROUND3` | `examples/gallery/client/settings_panel.luau`, driven by `tests/gallery_chrome.spec.luau` groups (6)-(8); `LuauUIShowcaseAPI.motion("reduced")` |
| **O-12** | Row-actions menu not clamped to the viewport | `OPEN` | needs a ruling |
| **O-13** | The "Edit item" wrap rule (`renderer.luau:452`) | `OPEN` | needs a ruling |
| **O-14** | The overflow sweep could not see cross-axis findings | `CLOSED_ROUND3` | `tests/overflow_sweep.spec.luau`. The phrase FILTER was DELETED rather than widened (a second phrase would have been the same defect), so the sweep now asks about every solver finding at eight viewports and four text preferences; 697 findings, 393 of them previously invisible to the file whose job is to see them. All five recorded non-main-axis findings re-verified — five of five real, two worse than recorded, one drifted — plus eleven nobody had recorded |

## Owed by round 3's own work

| # | Item | Status | Evidence / blocked on |
|---|---|---|---|
| **O-15** | `demo_picker.DEMOS` registration for `lifecycle_hidden`, and the showcase place rebuilt after it | `OPEN` | `examples/gallery/client/**` belonged to a concurrently running agent; the exact entry to add is in the round-3 design, item D §5 |
| **O-16** | The always-on sweep cannot see the `virtualSlot` class | `CLOSED_ROUND3` | `tests/overflow_sweep.spec.luau` — closed by O-14's filter deletion, which was the general fix rather than adding this class's phrase to a list. Its `BREADTH CONTROL: a layered overlap and a lying itemExtent both reach the collector` case is the proof, and it is a control case rather than a coverage claim |
| **O-17** | `tests/lib/tiers.luau` records `overflow_sweep.spec` at 1036 ms / 37 surfaces / six viewports | `OPEN` | stale by construction after the text axis landed (~2.5 s, 42 surfaces, eight viewports, four preferences). Nothing is red — the tier spec only asserts `ms > 250` |
| **O-18** | A vertical pan that begins on a hosted row still fires that row's `onActivate` | `PENDING_PHYSICAL` | brief item E2, recorded and deliberately not fixed: the fix rests on an unverified engine premise (does a native `ScrollingFrame` drag cancel its child button's `Activated`?) that only a device can settle |
| **O-19** | The locale axis, and 390x844, are not swept | `OPEN` | measured 2026-08-13: `p4_foyer`'s `TopBar` is clean in English at every preference at 390x844 and overflows by 33px at +10 / 58px at +14 under the shipping 1.4x `xa` pseudo-locale |
| **O-20** | A presented modal still costs 2 solves per geometry change | `OPEN` | L-29 residual 2, measured with the probe recipe recorded. The Rascal Rally consumer rider asserts a CEILING of 2, so removing the second solve later does not move the check |
| **O-21** | The 35 large-text overflow defects the new axis found | `OPEN` | enumerated in the round-3 design with px, class and viewport; the sweep ships green over an enumerated waiver list under three rules (nothing waived at offset 0; a waiver is a ceiling, not a pardon; a waiver that fires nowhere fails) |

## The four PENDING_PHYSICAL device rows, named individually

The device ledger a Studio/physical session would close. None is claimed:

- **A (flow-wrap)** — the `flow_wrap` fixture has never been mounted in Studio under Play. The cross-axis rule it reproduces came from a live Studio probe on 2026-08-13; the fixture itself did not.
- **D2 (circular progress)** — whether the ENGINE crops a `Path2D` stroke inside a clip host is unanswered (`GetBoundingRect` reports geometry that knows nothing about a host's crop), and the per-frame `SetControlPoints` cost on a phone is unmeasured. `progress_ring` is the surface to drive.
- **D (`hidden` / lifecycle hooks)** — whether Roblox itself already refuses input to an invisible `GuiButton` is undocumented, which is why the framework holds the rule rather than relying on the engine.
- **E (the chrome)** — does a real `Backquote` reach IAS, and does a physical `ButtonY` fire `Activate` end to end. Injected keys are known-unreliable for some classes, and a real pad button cannot be pressed headlessly.
