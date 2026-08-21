# Re-review — DIR4 fix round 1: `f19b6cb` + `1e76d5d`

Fresh-context scoped re-review, 2026-08-21. Reviewed as the union diff of the two commits
against `e4c8ac3` (`f19b6cb~`). Scope is the two commits only: the four findings the DIR4
review filed (MAJOR-1, MAJOR-2, and the MINORs) plus a new-breakage scan of these diffs.

**Verdict — ALL FINDINGS ADDRESSED. ✅**

Both MAJORs are fixed at the level the review asked for, not at the level of the sentence:
the raise guard now fires on a path `demo_picker.show`'s own `pcall` actually drives, and
`ButtonY` binds nothing in the chrome. All seven review MINORs are dispositioned, six
fixed and one (`isPanelPath` pinning) declared unpinned with an accurate reason. Every
mutation the report claims **bites**, and the three claims I could not take on trust
(the ~90px overscan overflow, the unchanged near rows, the recorded `bottom` null) each
reproduce exactly.

**Quality — 3 MINOR, 4 NIT.** None blocks. The MINORs are all of one shape, and it is the
shape this round exists to end: **a written claim the code or the measurement does not
carry.** They are small because the substance is right — but ADR-0040's B-14 row, the
record that makes R20's removal legal under R15, is not actually a row of the ledger.

## Measurement discipline

Everything below was measured in private `git archive` exports under the session
scratchpad (`head` = `1e76d5d`, `parent` = `e4c8ac3`, plus three mutation clones), one
`lune` process at a time. Nothing was written to the shared tree except this file.
`check_input_authority`, `check_call_shape_drift` and `check_brand_drift` walk a relative
path to the consumer, so the exports were placed at the depth those checks expect with the
real `games/RascalRally/code` symlinked read-only. Three untracked, `.gitignore`d
`*.rbxl.lock` files were present in the head export from the environment (they are in
neither commit — `git archive 1e76d5d | tar -t` carries no `.rbxl.lock`); removing them
made `check_brand_drift` pass, and every check below is reported head-vs-parent so an
environmental failure cannot be mistaken for a finding.

---

## 1. MAJOR-1 — the guard now fires on a real path ✅

**The fix.** `raisePanel`'s condition is now `if demoHandle == nil then return end`; the
unreachable `panelHandle.displayOrder > demoHandle.displayOrder` comparison is deleted
rather than kept with an excuse.

**Driven through the production call site, and it is the saving that was claimed.**
Case (15) sets `showcase{ failMount = flag }`, which makes the harness's `mountDemo`
throw — the same shape a missing scenario module has live — so `demo_picker.show`'s own
`pcall` fails, `mounted` stays nil, and `raise()` is called with no handle. Measured on
the *identical* probe at both revisions (I added the same `failMount` hook to the parent's
harness so the two are comparable):

```
parent e4c8ac3 : panel 10400 -> 10500   (the failed mount spent a slot)
head   1e76d5d : panel 10400 -> 10400   (it does not)
focus, both revisions: /ShowcasePanel/…/Options/Opt1 before AND after — unchanged
```

That is the review's recommended fix, measured end to end, on the one path the app can
actually take. The focus probe is there because the early return also skips
`pendingFocus = lastPanelFocus`; it makes no difference, because the panel is not
re-presented and so nothing disturbs the ring.

**The safety question the early return raises, answered.** `demo_picker`'s `raise()` on
the failed path exists so "a failed demo must not take the chrome down with it". I checked
what else that raise does: `opts.onRaise` in both `init.client.luau:666` and the spec
harness only re-applies the settings — it re-presents nothing — and `watchRaise` has
exactly one subscriber in the whole tree (`showcase_chrome.luau:901`). So on the
failed-mount path nothing climbs, and the panel really is still topmost. The guard is
correct, not merely cheap.

**Mutations, run.**

| # | mutation | result |
|---|---|---|
| N1 | the guard neutered (`if false then return end`) | **1 failed / 75** — (15) "a FAILED MOUNT raises for free" ✅ |
| N5 | `demo_picker` stops passing the handle (`local handle = nil`) | **4 failed / 72** — (15)'s SUCCESS control, plus three (10)-family swap cases ✅ |
| N5-inverse | the FAILED path passes a table instead of nil | **1 failed / 75** — (15) failed mount ✅ |

Both directions of the contract are pinned: the picker cannot stop passing the handle on
success, and it cannot start passing one on failure. (The report's ledger mis-attributes
N5's reddened case — see MINOR-3 below.)

**The fabricated harness and its export are gone.** `w.chrome.raise({ displayOrder = … })`
appears nowhere; `self.raise = raisePanel` is deleted; a tree-wide grep finds no `.raise(`
call outside two comments referring to the presenter API that does not exist. Nothing else
consumed it.

**The hazard-note sentence is now true.** `showcase_chrome.luau:844-851` claims only that a
raise naming **no** handle costs nothing, and states outright that "a successful swap
really has climbed and really does cost the second slot". Both halves measured above. The
spec's comment and the source comment now say the same thing, which is what failed last
round.

## 2. MAJOR-2 / R20 — `ButtonY` binds nothing in the chrome ✅

**The whole-tree grep.** `ButtonY` appears in `examples/` in seven places, every one of
them prose in `showcase_chrome.luau`'s §4/§5 explaining why the chrome does *not* bind it.
`showcase_chrome`'s only two `.bind(` calls are `TOGGLE_KEYBOARD` (`Backquote`) and the
`SECTION_GAMEPAD` pair. In `src/`, `ButtonY` exists only at `menu.luau:68` (prose) and
`:72` (`TRIGGER_KEYS.gamepad`). No chrome-side binding survives anywhere.

**Case (16) uses the real menu scenario.** The second `it` mounts
`examples/gallery/scenarios/menu` through a `buildDemo` hook and presses `ButtonY`: 1 menu
opens, chrome stays closed. The first `it` is a stand-in that reads `menu.TRIGGER_KEYS
.gamepad` and `menu.TRIGGER_KEY_PRIORITY` from the module rather than typing them — the
right instrument, and it is deliberately placed first.

**Mutation N2 (the chrome re-binds `ButtonY`), run:** **3 failed / 73.**

```
(4)  the toggle context binds exactly the three documented keys …
(16) a context bound exactly as menu.luau binds it still receives ButtonY
       expected: the menu verb fired 0 time(s); chrome open true
(16) …and the real `menu` scenario opens its card, with the chrome untouched
       expected: ButtonY opened 0 menu(s); chrome open true
```

**Both halves of §5's `ButtonY` sentence reproduce.** §5 claims one press "opened the menu
AND the chrome at 48b6e7b, then opened only the chrome once this context began to sink". I
reconstructed both states on the head tree:

```
N2 + sink = false : menu fired 1, chrome open true    ("opened both")
N2 + sink = true  : menu fired 0, chrome open true    ("only the chrome")
R20 (as shipped)  : menu fired 1, chrome open false
```

**`TOGGLE_GAMEPAD` is deleted from the export surface.** The constant appears nowhere in
`examples/` except its own tombstone comment; the only live reads are the spec's
`expect(showcase_chrome.TOGGLE_GAMEPAD).toBeNil()` and ADR-0040's row. The boot print in
`init.client.luau:856` no longer names it and no longer names `ButtonY`: it now prints
`{TOGGLE_KEYBOARD} on a keyboard, {SECTION_GAMEPAD.demos}/{SECTION_GAMEPAD.settings} on a
pad`. `SECTION_GAMEPAD` is a frozen table with both keys, `stylua --check` parses the file
clean, and no test executes that line (it did not before either — no regression).

**ADR-0040 B-14 exists and is R15-shaped in content**, with all four columns
(surface / what changed / why breaking / recorded) and the removal explicitly riding the
unreleased-`0.10.0` clause the constitution §14 names. It is honest that an example export
is not a `src/` surface and says why it is recorded anyway. Its *placement* is broken —
see MINOR-1.

**§5's audit table, per key, each claim checked.**

| §5 row | evidence offered | verified |
|---|---|---|
| `Backquote` — "grep of `src/`, `examples/` and `tests/`: bound nowhere else" | a grep | ✅ zero hits in `src/` or `examples/` outside `showcase_chrome` |
| `ButtonL1`/`ButtonR1` — `presenter.luau:2292-2293`, `:2394-2395` | line cites | ✅ 2292-2293 are the static `ButtonL1`/`ButtonR1` Adjust binds; 2393-2394 are the dynamic pair inside `bindAdjustKeys` (cited as 2394-2395 — off by one line, harmless) |
| `ButtonY` — `menu.luau:70-76`, `:884-899`, sinking, priority 1200 | line cites + measurement | ✅ `TRIGGER_KEYS` at 70-73, `TRIGGER_KEY_PRIORITY = 1200` at 76, `createContext{… sink = true}` at 884-887, gamepad binds at 895-898 |
| R19's real price — `presenter.luau:2398-2402` returns after Comma/Period/L1/R1 on a legacy `navigateH` screen | line cite | ✅ verbatim at 2398-2402 |

The table distinguishes what was *read* (Backquote) from what was *measured* (the two
contended entries) and does not overclaim either. That is the correction the review asked
for.

## 3. MINOR (a) — the Dock-padding overscan ✅

**N3b (`right` dropped to 0): 2 failed / 74**, both in (17) — the four-edge box case and
the ladder-offer case. ✅

**The "~90px wider than the visible width" claim is exact.** Full painted-geometry dump
(every `adapter.paths()` node carrying a rect), sorted, parent vs head, at four viewports —
**68 rows each, two lines differ, both on the console row**:

```
- console /ShowcaseChrome/Dock/Bar         x102 y72 w1806 h69
- console /ShowcaseChrome/Dock/Bar/Chips   x102 y72 w1806 h69
+ console /ShowcaseChrome/Dock/Bar         x102 y72 w1716 h69
+ console /ShowcaseChrome/Dock/Bar/Chips   x102 y72 w1716 h69
```

At 1920x1080 / Large the insets are 90/60 and the package gutter is 12. So the visible
content width is `1920 − 90 − 90 − 12 − 12 = 1716`, and the offer the `ViewThatFits`
ladder measured against was **1806 — exactly 90 wider**. The old right edge sat at 1908
against a safe limit of 1830, i.e. 78px into the bezel, which is the review's number.
Head's right edge is 1818. The corrected offer is what the case now shows.

**The three near rows keep their exact prior geometry.** Phone 390x844, tablet 844x390 and
desktop 1232x1067 are **identical line for line** in that dump, base vs head — every node,
not just the bar. The demo body at the console row is also unmoved (`/Demo x90 y149
w1740`), so the `barReservation` arithmetic in `init.client.luau:313` still lands where it
did.

*Note:* the shipped near-row control in (17) drives phone and desktop only. The tablet row
is mine, not the suite's — see NIT-2.

**The recorded null N3 is honest.** Dropping `bottom` to 0 reddens **nothing in the whole
suite** (6892 passed, exit 0), which is what the spec's comment says. It is not hiding
anything: the Dock's only child is a `topLeft`-anchored, hugging `Bar`, so no painted node
can reach the bottom inset, and the padding is inert rather than wrong. For completeness I
ran the other two edges, which the report did not claim: `left = 0` → **3 failed**,
`top = 0` → **2 failed**. Three of four edges observable, the fourth declared. The reshape
onto one `padding` is also what makes "half-applied" structurally impossible next time,
which was the review's actual complaint.

**The identity concern the reshape invites — measured and cleared.** The previous design
used two *scalar* memos specifically so the value compared BY VALUE; the new one returns a
fresh table. `effectiveOverscanInsets` is a `core:memo` gated on `overscanInsets` and
`displaySize` (`environment.luau:270`), neither of which a resize touches, so the table
identity does not churn. Confirmed rather than reasoned: 10 successive viewport changes
produce **70 adapter ops at both revisions** at ten-foot, **70 at both** on a near display,
and **0 at both** for a null re-set. No regression.

**`coreTop` is still pinned** after moving from the `barTop` memo to `offsetY = opts
.coreTop`: mutating it to `0` reddens **7 cases across the suite**.

## 4. MINORs (c)/(d) ✅

**N4 (the raise listener re-swallows): 1 failed / 75** — (18) "one throwing listener
produces one report line". ✅ The harness's `warnSink` replaced the swallowing `warn`, so
the seam is now observable, and `#lines == 1` would also catch extra noise.

**`isPanelPath`'s disclosed unpinned state is accurately described.** The new predicate is
correct (`path == "/ShowcasePanel"` or a `"/ShowcasePanel/"` prefix — `#PANEL_ROOT + 1`
matches the separator string's length). Reverting it to the loose prefix test and running
the **full suite** gives **6892 passed, exit 0** — nothing reddens, exactly as the report
says. The stated reason (there is no second `/ShowcasePanel*` surface in the place, and
fabricating one would be the fixture class this round just deleted) is consistent with
what MAJOR-1 was about, and the disclosure is in both the report and the source comment.

## 5. Suite, breakage scan, surfaces ✅

| claim | measured | result |
|---|---|---|
| 6892 at head, 6883 at the parent, +9 | `./run-tests.sh` in both exports | **6883 → 6892, exit 0 both** ✅ |
| the +9 are this round's own | full ✓-line diff of the two transcripts | **exactly 9 added**: (15)×1, (16)×4, (17)×3, (18)×1. 3 titles renamed, **0 removed** ✅ |
| `src/` untouched | `git diff -- src/` across the two commits | empty ✅ |
| public surface reflects the removal without collateral | `tools/lune/_probe_public_surface`, parent vs head | **241 lines, byte-identical** — `TOGGLE_GAMEPAD` was an example export and was never in the dump, so its removal is correctly invisible there and is recorded in ADR-0040 instead ✅ |
| `check_input_authority` stays clean | private multi-repo shape, real consumer symlinked | **exit 0** ✅ |
| every other repo check | 12 python checks run at head AND parent | **identical exit codes on all 12**; the only non-zero, `check_verdicts` (2), is environmental and identical at both ✅ |
| lune CLI checks | `check_docs`, `check_example_drift`, `check_registration`, `check_prop_parity`, `check_maintainer_map` | all OK ✅ |
| formatting and types | `stylua --check` on the three touched sources; `check_types.py` | clean; **0 diagnostics on both target files** ✅ |
| RascalRally lockstep | grep of the whole consumer tree for `showcase_chrome`, `TOGGLE_GAMEPAD`, `BAR_ID`, `demo_picker`, `watchRaise`, `overscanEdge` | **zero files** — nothing owed ✅ |
| `api.md` heading placement | headings around 2907-2933 | the standing-rule section now sits **after** the closed-option-key block and the responder table, before `### handle.focusOrder()` ✅ |

New-breakage scan of the two diffs found nothing beyond the MINORs below. The one
structural risk I chased — the guard's early return interacting with the "raise anyway"
contract on the failed-mount path — is answered above and is safe.

---

## New findings

### MINOR-1 — ADR-0040's B-14 is not a row of the ledger

`docs/adr/ADR-0040-unreleased-breaking-changes.md`: line 88 is B-13, **line 89 is blank**,
line 90 is B-14, line 91 is blank. A blank line terminates a GFM table, so B-14 renders as
a paragraph of pipe-delimited literal text below the ledger, not as its fourteenth row —
and nothing catches it, because `api_surface.spec` greps ADR-0040 for specific strings
rather than parsing rows, and `check_doc_style` passes. I scanned every `.md` under
`docs/` for the same pattern: **this is the only instance in the tree**, so it is not a
house idiom.

This is the one that matters. R20's removal is legal *because* R15 lets an unreleased
breaking change ride "provided it is recorded in ADR-0040" (constitution §14). The record
exists; as committed it is not in the ledger it is supposed to be in. **Fix: delete the
blank line at :89.**

### MINOR-2 — two stale key counts left in the file this round re-audited

* `showcase_chrome.luau:78` — the section heading still reads **"§ 4. THE BINDINGS, AND
  WHY THESE TWO KEYS"**. The chrome binds three (`Backquote`, `ButtonL1`, `ButtonR1`), and
  the round's own spec case is titled "binds exactly the **three** documented keys".
* `showcase_chrome.luau:330-332` — the sink justification still reads "Per-KEY, so **the
  two toggle keys** consume nothing that was ever bound elsewhere." There is exactly one
  toggle key now. §5's parallel sentence *was* updated to "so `Backquote` consumes
  nothing"; this copy of it was missed.

Both are the round's own subject — a comment describing a code shape that no longer
exists — surviving inside the module the round rewrote to remove exactly that. Grep for
`two toggle` finds one hit tree-wide, so this is the complete list.

### MINOR-3 — the fix-round mutation ledger mis-attributes two of its six rows

* **N2** is recorded as reddening "(7) contended keys". The contended-key case lives in
  `describe("showcase chrome (4): exactly one engaged surface, and no stolen keys")`;
  there is no describe (7) in the file. Measured: (4) and (16)×2.
* **N5** is recorded as reddening "(15) failed mount — the contract, not just the guard".
  Run as written (`demo_picker` stops passing the handle), it reddens **(15)'s SUCCESS
  control and three (10)-family swap cases — not the failed-mount case**, which cannot
  redden under that mutation because a nil handle is exactly what it expects. The
  failed-mount case reddens under the *opposite* mutation (passing a table on the failed
  path), which I ran separately: 1 failed.

The contract is genuinely pinned in both directions — this is a bookkeeping error, not a
hole. It is filed as a MINOR only because a mutation table whose rows do not match what the
mutations do is the same instrument failure the round was commissioned to fix, one level
up.

### NITs

1. **`showcase_chrome.luau:836`** — "Measured over 100 swaps: 30300 against 20400."
   Measured on the harness at head: panel-open demo **30300** / panel **30400**;
   panel-closed demo **20300**. The second number should be 20300. Pre-existing (the line
   is untouched by this diff), but it sits inside the hazard note this round re-audited and
   rewrote two paragraphs of.
2. **Case (17)'s near-row control drives phone and desktop only**, while the claim it
   supports is "the near rows". The tablet row (844x390) is unchanged — I measured it in
   the full-dump diff — but the shipped instrument does not say so. One more entry in the
   loop closes it.
3. **The report's "## The five MINORs" heads a seven-row table.** All seven review MINORs
   are in fact dispositioned; only the heading undercounts.
4. **`offsetY = opts.coreTop` drops the old `barTop` memo's `type(top) == "number"`
   coercion.** Unreachable in both consumers (`GuiService:GetGuiInset().Y` in
   `init.client.luau:291`, `o.coreTop or 0` in the harness), so there is no defect.
   Recorded so it is not re-litigated.

---

## Measured and cleared (recorded so it is not re-litigated)

* **The `overscanPadding` table identity is not a regression.** 70 ops / 0 ops / 70 ops on
  a 10-step viewport churn, null churn, and near-display churn — identical at both
  revisions. `effectiveOverscanInsets` is a memo gated on facts a resize does not move, so
  the previous round's "fresh table on every read" premise was itself wrong; the one-memo
  shape costs nothing.
* **The failed-mount focus path is unchanged** between revisions (same focused path before
  and after, both). The early return skips `pendingFocus`, and it does not matter because
  the panel is not re-presented.
* **`watchRaise` has exactly one subscriber** and `onRaise` re-presents nothing, so the
  guard's early return cannot leave the panel buried.
* **`Backquote` is bound nowhere else** in `src/` or `examples/` — §5's grep reproduces.
* **The `menu` scenario's `ctx` shape**: the harness passes a superset of what
  `scenarios/menu.luau` reads (`ctx.Facet`, `ctx.core`, `ctx.env`, `ctx.presenter`), so
  case (16)'s "real fixture" really is the shipped one, and N2 reddening it proves the
  binding is live in that harness rather than inferred.
* **The three `.rbxl.lock` files** in the head export are environmental, in neither commit,
  and are the only reason `check_brand_drift` looked red before they were removed.

## Recommended before merge

1. **MINOR-1** — delete the blank line at `ADR-0040:89` so B-14 is a row of the ledger.
   One character; it is the record R20 rides on.
2. **MINOR-2** — `showcase_chrome.luau:78` "THESE TWO KEYS" → three; `:330-332` "the two
   toggle keys" → `Backquote`.
3. **MINOR-3** — correct the two mutation-ledger rows to what the mutations actually
   redden, and note that the failed-mount contract is pinned by the inverse mutation.
4. **NITs 1-4** are optional; NIT-1 (20400 → 20300) is worth taking while the note is open.
