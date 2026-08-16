# Acceptance ledger — Navigation & transient menus

Binding brief: `docs/plans/navigation-and-menus-brief.md` (2026-08-16).
Gate block: `tools/lune/gate_manifest.luau` → `["navigation-and-menus"]`.
Evidence ladder and status meanings: `docs/plans/agent-execution-contract.md` §2–§3.

A row cannot pass through a different, easier row. A headless focus test does not pass a
real gamepad row; a screenshot does not pass an input-routing row.

Statuses: `PASS_AUTOMATED` · `PASS_PHYSICAL` · `PASS_HUMAN` · `FAIL_PRODUCT` ·
`FAIL_ENVIRONMENT` · `PENDING_PHYSICAL` · `PENDING_HUMAN` · `PENDING` (not started).

---

## D0 — sweep economy and grep integrity

| ID | User-visible behaviour | Risk while a lower test still passes | Evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| **NM-0.1** | A sweep runs each suite once, not once per gate. A warm serve costs 0.14 s against an 83.4 s run | A cache that never invalidates makes 1127 gate greps unfalsifiable — the purest example of a check that cannot fail | E1 | `lune run tools/lune/gate navigation-and-menus` → `d0-one-run-per-sweep` | `artifacts/navigation-and-menus/sweep-economy.md` | **PASS_AUTOMATED** |
| **NM-0.2** | A red, failing, truncated, empty, fast-tier or on-disk-mutated transcript is refused, printing nothing and exiting non-zero | Refusing with a zero exit reddens nothing; refusing with a non-empty stdout still feeds a FORM B pipeline | E1 | `tools/suite_cache_selftest.sh` (27 assertions, each guard broken on purpose) | `artifacts/navigation-and-menus/suite-cache-selftest.md` | **PASS_AUTOMATED** |
| **NM-0.3** | A renamed spec case is caught in the commit that renamed it, not three stages later by hand | Anchoring is syntactic: a renamed case leaves its grep perfectly anchored and matching nothing | E1 | `python3 tools/check_manifest_integrity.py --transcript` | `artifacts/navigation-and-menus/grep-match-check.md` | **PASS_AUTOMATED** |
| **NM-0.4** | A Rascal Rally suite result is invalidated by a LuauUI `src/` edit | RR's specs require LuauUI modules directly; a fingerprint that misses them serves a stale green over a broken consumer | E1 | `tools/suite_cache_selftest.sh` §RascalRally | same | **PASS_AUTOMATED** |

## D1 — anchored surface seam

| ID | User-visible behaviour | Risk | Evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| **NM-1.1** | A surface presents against a source view's **screen rect**, on a preferred edge with an alignment along it | A parent-corner anchor looks identical in a fixture whose parent happens to be the source | E1 + E3 | pure placement solver specs + a mounted fixture dump | TBD | PENDING |
| **NM-1.2** | It **flips** to the opposite edge rather than crossing a safe-area inset, and never flips into a worse place | A flip rule with no "is the other side actually better" test trades a clipped surface for a clipped surface | E1 | solver specs over synthetic safe boxes | TBD | PENDING |
| **NM-1.3** | It **shifts** along the edge rather than crossing a side, and the arrow stays over the source | Shift and flip interact; testing them separately misses the corner case that needs both | E1 | solver specs | TBD | PENDING |
| **NM-1.4** | The arrow tail is **suppressed** when the shift took it off the source | An arrow pointing at nothing is worse than no arrow, and only appears at extreme viewports | E1 + E3 capture | solver specs + capture | TBD | PENDING |
| **NM-1.5** | A surface anchored to a scrolling row follows it, on the existing `syncGeometry` cadence and with no new watcher | A per-frame watcher passes every correctness test and costs frame budget forever | E1 + E3 | contribution `syncGeometry` spec; Studio scroll canary | TBD | PENDING |
| **NM-1.6** | Tap-away, focus scope and modal layering are the shipped ones, not forks | Two catchers can both be live and fight; two focus stacks desynchronise on dismiss | E1 | reuse asserted in spec; `check_registration` | TBD | PENDING |
| **NM-1.7** | `f1`'s callout reproduces: anchored under a top-right `+`, arrow up, body shifted left to stay on screen | — | E3 | gallery fixture + capture | TBD | PENDING |

## D2 — `Menu` (freestanding action menu)

| ID | User-visible behaviour | Risk | Evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| **NM-2.1** | Items are verbs with icons, dividers and submenus, attachable to **any** blueprint | `popup_button.Option` (`{id, label}`) cannot express a verb, and a value picker silently becomes the answer | E1 | spec + `dump()` | TBD | PENDING |
| **NM-2.2** | Opens on primary activate, pointer **right-click**, touch **long-press**, a gamepad button and a keyboard chord | A menu that only opens on right-click is a defect on two of three input classes | E1 + E3 + **E4** | four-input conformance proofs | TBD | PENDING (touch/gamepad → PENDING_PHYSICAL) |
| **NM-2.3** | Submenus nest without a structural cap; depth ≥ 2 emits a diagnostic | A hard cap forbids what SwiftUI allows; no diagnostic permits twice what the HIG advises | E1 | spec asserting depth 3 builds AND diagnoses | TBD | PENDING |
| **NM-2.4** | A menu whose every item is disabled still **opens** | Swallowing the trigger is the "silently does nothing" class, and only shows up in a rare state | E1 | spec | TBD | PENDING |
| **NM-2.5** | Under `sheet` presentation a submenu **replaces** contents with a back affordance rather than stacking panels | Stacked panels on touch is the shape that made this a device-only defect last time | E1 | spec over both presentations of one tree | TBD | PENDING |
| **NM-2.6** | Cancel / gamepad B closes **one** level; tap-away closes **all**; ←/→ leave and enter a submenu | One-level vs all-levels is invisible until a submenu is open, which no smoke test does | E1 | spec | TBD | PENDING |
| **NM-2.7** | `resolvePresentation` lives in ONE place, consumed by both menus | Two copies drift, and the drift shows up only on the input class nobody tested | E1 | grep + spec | TBD | PENDING |
| **NM-2.8** | `icon` joins `popup_button.Option`; icons are per-group all-or-nothing | A half-iconned group is the HIG violation that looks fine in the one fixture it was authored in | E1 | authoring-time lint spec | TBD | PENDING |

## D3a — `help` (player-pulled)

| ID | User-visible behaviour | Risk | Evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| **NM-3a.1** | Shows on pointer hover after a dwell, and on keyboard/gamepad focus; hides on leave/blur/activate | A dwell timer that never cancels leaves a plate over the control the player just clicked | E1 + E3 | spec + Studio pointer canary | TBD | PENDING (hover → PENDING_PHYSICAL) |
| **NM-3a.2** | **Nothing appears on touch**, and `help` binds **no** long-press anywhere | D2 owns long-press on the one input class where neither construct has an alternative; a collision here is silent | E1 | a spec that FAILS if `help` binds long-press | TBD | PENDING |
| **NM-3a.3** | A `help` string that appears nowhere else is findable at build time | Touch players cannot read it, so `help`-only information is unreachable for them | E1 | build check | TBD | PENDING |

## D3b — `Callout` (app-pushed coach mark)

| ID | User-visible behaviour | Risk | Evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| **NM-3b.1** | Blueprint content with an arrow tail, on D1's surface | — | E1 + E3 | fixture + capture | TBD | PENDING |
| **NM-3b.2** | **Never blocks**: focus is not trapped and the control underneath stays operable | A non-blocking claim is invisible in a screenshot and only fails under a real tap | E1 + E3 + **E4** | non-consuming catcher spec; Studio tap-through canary | TBD | PENDING (→ PENDING_PHYSICAL) |
| **NM-3b.3** | At most one on screen; the rest queue | A pile passes every single-callout test | E1 | spec presenting three | TBD | PENDING |
| **NM-3b.4** | Dies permanently on feature-use, dismissal or explicit invalidate; **persistence is the caller's** | A framework save layer is scope this library must not grow | E1 | spec over a caller-held Readable | TBD | PENDING |

## D4 — sliding selection indicator

| ID | User-visible behaviour | Risk | Evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| **NM-4.1** | The indicator animates from the previous child's rect to the new one, in both axes | Interpolating an index instead of a rect is correct only while segments are equal width | E1 | rect-interpolation specs | TBD | PENDING |
| **NM-4.2** | Underline and filled pill are two skins of **one** mechanism | Two mechanisms drift, and D6's "segmented as a tab bar" becomes a second tab construct | E1 | spec + `dump()` | TBD | PENDING |
| **NM-4.3** | **Reduced motion snaps** — no intermediate frames | Reading the flag proves the branch exists, not that the frames stopped | E1 | a spec that COUNTS writes, not one that reads a flag | TBD | PENDING |
| **NM-4.4** | The geometry memo is compared **by value**; a fresh table each pass does not re-fire forever | An identity-compared memo is correct and quietly re-solves every frame | E1 | solve-count spec, the `8560f2b` shape | TBD | PENDING |
| **NM-4.5** | The indicator is never a Tab stop | It sits between every pair of tabs, so the defect is one extra stop per tab and reads as "Tab is broken" | E1 | focus-order spec | TBD | PENDING |

## D5 — `TabView`

| ID | User-visible behaviour | Risk | Evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| **NM-5.1** | Owner-held `selection` Signal; placement from `adaptive.navPlacement` | — | E1 | spec across the four placements | TBD | PENDING |
| **NM-5.2** | **Two levels nest** without fighting over focus scope, `back()` or placement; an inner TabView never claims the app-level placement | One TabView passes every test; the bug is entirely in the second | E1 + E3 | two-level spec + Studio canary | TBD | PENDING |
| **NM-5.3** | An overflowing strip autoscrolls the selection into view | Only reproduces past a viewport width nobody defaults to | E1 + E3 | spec + capture at 320 px | TBD | PENDING |
| **NM-5.4** | Content is lazy and the previous tab's subtree is **really disposed** — scopes disposed, effects stopped, Instances pooled | A hide passes every visual test and leaks every switch | E1 | switch-N-times memory-neutrality spec (`core:counters()` returns to baseline) | TBD | PENDING |
| **NM-5.5** | The **strip is never evicted** — every tab's label, icon and badge stay live | A badge on an unselected tab is the whole point of a badge | E1 | spec | TBD | PENDING |
| **NM-5.6** | Gamepad shoulders page tabs; the strip is reached in document order; every tab is a 44 px target | — | E1 + **E4** | four-input proofs | TBD | PENDING (gamepad → PENDING_PHYSICAL) |
| **NM-5.7** | At least one reference app is migrated onto the construct | An unconsumed construct is unproven | E1 + E3 | reference-app spec + capture | TBD | PENDING |

## D6 — segmented `Picker`

| ID | User-visible behaviour | Risk | Evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| **NM-6.1** | `Option` gains `icon`; icon-only and icon+label both render | An icon-only segment with no semantic label is unreadable to the dump and to assistive tech | E1 | spec + `dump()` semanticText | TBD | PENDING |
| **NM-6.2** | A real **vertical pill**, distinct from today's `axis = "y"` inline row list | Overloading `axis="y"` silently changes every existing caller | E1 | spec asserting both shapes coexist | TBD | PENDING |
| **NM-6.3** | Selection is D4's sliding indicator, not a static style tag | — | E1 | spec | TBD | PENDING |

## D7 — elision must disclose, not delete

| ID | User-visible behaviour | Risk | Evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| **NM-7.1** | `Region` states what becomes of content its chosen form stops showing; `recover = "none"` must be written explicitly | Silence is not consent: a default of "nothing is lost" is exactly the bug | E1 | normalize-time spec | TBD | PENDING |
| **NM-7.2** | `RegionResolution` gains `elided`; `Resolution` publishes the currently-unshown regions | Without the list every consumer re-derives elision by hand and gets it subtly wrong | E1 | resolver spec | TBD | PENDING |
| **NM-7.3** | A region with a recovery route whose last-standing form has no focusable element is an **authoring error** | `TasksChip` renders "Tasks 1/3" and cannot be tapped — it looks fine in a screenshot | E1 | normalize-time spec | TBD | PENDING |
| **NM-7.4** | Dropped content is reachable through an overflow sink in a rank-1 region | Rank-1 never drops, so a host always exists — but only if something puts the list there | E1 + E3 | fixture + capture | TBD | PENDING |
| **NM-7.5** | The ladder is re-ranked: a team score outranks an FPS readout | — | E1 | fixture spec | TBD | PENDING |
| **NM-7.6** | The URL bar's modelled **steal** and drawn **height** are separate, re-measured facts | One number doing two jobs paints an absurd box AND over-states the steal, at once | E1 | fixture spec + measurement note | TBD | PENDING |
| **NM-7.7** | **At every viewport in the device matrix, every elided or dropped region has a live recovery route** | This is the only row that keeps the defect from coming back | E1 sweep | device-matrix gate check | TBD | PENDING |

## D8 — playlist sort + resize, retiring `table_columns`

| ID | User-visible behaviour | Risk | Evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| **NM-8.1** | Tapping a sortable header cycles an owner-held `sortOrder`; filter and sort compose over one source list | Sorting the filtered list and filtering the sorted list differ the moment both are active | E1 | `playlist sort: the owner sorts, and the sort composes with the filter` (5 cases) — sort over the SOURCE, filter over the sorted view; Rating sorts by the live signal; ties break on the source index | artifacts/navigation-and-menus/d8-playlist-sort-resize.md §3 | PASS_AUTOMATED |
| **NM-8.2** | A manual reorder clears the sort (the iTunes rule) | Leaving it undefined means a drag silently re-sorts itself away | E1 | `playlist sort: a manual reorder wins, and takes the sort with it` (6 cases) — a drop and a Top BAKE the displayed order into the source; Remove does not; the filter refusal is unchanged | artifacts/navigation-and-menus/d8-playlist-sort-resize.md §3 | PASS_AUTOMATED |
| **NM-8.3** | Name and Artist resize through all three routes; Rating **refuses** | Pinning the sole `fill` column leaves nothing to absorb the remainder and the row under-fills | E1 | `playlist columns: the three routes all move the same column` (5 cases) + `pinning one column leaves a SIBLING to absorb the remainder`. Measured 800x600: two columns leave 424px of dead space, three fill the region | artifacts/navigation-and-menus/d8-playlist-sort-resize.md §2 | PASS_AUTOMATED |
| **NM-8.4** | Three columns fit at **320×640 in edit mode** with explicit `minWidth`s, re-measured — or the fixture falls back to two and says so | A third fixed 70 px column left the Name cell 6 px there; "a `fill` column is different" is a hypothesis until measured | E1 | `the 320x640 edit-mode measurement that kept the third column` (2 cases). KEPT: name 46/30, artist 30/14, **0** collapse diagnostics, against 6/0 and **3** for the deleted fixed column. minWidth 90/72, never the 24px default | artifacts/navigation-and-menus/d8-playlist-sort-resize.md §1 | PASS_AUTOMATED |
| **NM-8.5** | The live width readout and the selected-column hint survive the merge | `api.selectedColumn` paints nothing, so after a gamepad Activate the stick silently means something new | E1 | `/Playlist/Page/Widths` reads `api.columnWidthOverrides` (never a copy) and `/Playlist/Page/Hint` reads `api.selectedColumn`; both added to `example_readouts.spec`'s swept readout list | artifacts/navigation-and-menus/d8-playlist-sort-resize.md §4 | PASS_AUTOMATED |
| **NM-8.6** | ~700 lines of `table_columns` spec are green **on the playlist fixture before** the scenario is deleted | Deleting the fixture first is the named failure mode | E1 | `tests/playlist_columns.spec.luau` green at 38/38 and `hit_expander_overhang` re-pointed off the direct require BEFORE the delete; suite 5618 → **5685** | artifacts/navigation-and-menus/d8-playlist-sort-resize.md §4, §7 | PASS_AUTOMATED |

## Riders

| ID | User-visible behaviour | Risk | Evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| **NM-R1** | Rascal Rally consumes the new source unchanged: callers surveyed, a game-side contract test proves the live consumer is current, both Rojo mappings build, a Studio canary runs | A LuauUI gate cannot pass while its consumer is stale, failing or unaudited | E1 + E3 | RR suite + canary | TBD | PENDING |
| **NM-R2** | `swiftui-parity.md` rows for `.contextMenu`, `.popover` and `Picker`, and audit rows 14–15, reflect what shipped | A stale parity table is worse than none | E0 | `check_docs` | TBD | PENDING |
| **NM-R3** | GuiObject count holds against the 43 %-elided baseline | These constructs add surfaces; a silent elision regression is the likeliest way this round does net harm | E1 | elision benchmark | TBD | PENDING |

## Honest pendings — physical and human

| ID | What | Why nothing cheaper closes it | Status |
|---|---|---|---|
| **NM-X1** | Touch **long-press** opens a Menu on a real device | Studio cannot synthesize a real touch input class, and an injected event arrives as `Touch` rather than `MouseButton1` — filtering it wrong manufactures a false positive that agrees with you | PENDING_PHYSICAL |
| **NM-X2** | Pointer **right-click** and **hover-dwell** on real hardware | A script-fired binding proves the downstream action path only, never native arbitration | PENDING_PHYSICAL |
| **NM-X3** | Gamepad menu/tab paging with `PreferredInput == Gamepad` | Synthetic gamepad KeyCodes do not prove input classification or Button A contention | PENDING_PHYSICAL |
| **NM-X4** | The reduced-motion snap and the sliding indicator **feel** right | Frame counts prove the frames stopped, not that the motion reads well | PENDING_HUMAN |
| **NM-X5** | A Callout reads as help rather than as an ad | Apple's own warning — *"Use tips sparingly… Don't use tips to guide people through your app, or for advertising and promotion purposes"* — is a judgement, not an assertion | PENDING_HUMAN |
