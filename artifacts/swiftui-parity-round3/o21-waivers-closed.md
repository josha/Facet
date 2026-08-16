# O-21 — "fix the ones that hide text; waive the rest", carried to the end

**2026-08-15.** The director's ruling was executed in two rounds. Round one
(recorded in the O-21 ledger row) fixed ten waivers, measured fifteen cosmetic
and left **sixteen that still hid copy or a labelled control**. This is round
two, which closes all sixteen.

| | round 1 left | round 2 |
|---|---|---|
| `WAIVERS` (neutral) | 31 | **13** |
| `LOCALE_WAIVERS` (`xa`) | 12 | **4** |
| `theme_sweep_ledger.ROWS` | 127 | **116** |
| `DEFAULT_WAIVERS` (`since = 0`) | 4 | **3** |
| still hides copy or a labelled control | 16 | **0** |

Every waiver left standing is measured **cosmetic in both passes**: no character
and no labelled control outside the band a player can reach, nothing cut without
a `disclose` to open it, nothing opaque painted over copy. The one-line measured
reason for each of the thirteen is in the `WAIVERS` header of
`tests/overflow_sweep.spec.luau`.

## The re-verification, before anything was changed

The ledger's count was re-derived rather than inherited. `tools/lune/triage_overflow_waivers`
was re-run against the corpus at `b377fe9` and its output joined to the two waiver
lists by `(pass, surface, variant, node, sig)`: **31 neutral waivers, 16 carrying a
verdict that costs a player copy or a labelled control, 15 carrying none.** That
reproduces round one's split exactly, so the count was the ledger's, not a fresh
guess. (`LEAF-UNREACHABLE(Box)` and `(Image)` are *not* counted as owed — a plate
or an icon past an edge is a bleed. That is round one's own rule, kept.)

## The sixteen, resolved

**Thirteen FIXED in the fixture.** Each is a real product defect on a real
viewport, not a demo quirk.

| surface | what a player had lost | the repair |
|---|---|---|
| `p5_wardrobe` ×2 | the item card's column hugged its widest **label**, so it measured 153px inside a 133px Button content box: `Dusk Plaza` truncated against the wrong width, the 20px VERIFIED icon sat past the plate, and the whole card ran off the catalog scroller's window **on x**, where nothing scrolls it back | one `shrinkWeight` on the creator line |
| `p4_foyer` TopBar | the bell and its unread count 2px off a 320px screen at +14, and **19px off a 390px one under `xa` at the DEFAULT preference** | `shrinkWeight` on the brand — see "the note that had gone stale" below |
| `sponsor_toast` ×2 | `Press me`, the control the fixture exists to prove stays pressable under a toast, 5px below the fold | the lab chrome is a bounded sibling `ScrollView`; the stage keeps its own lane |
| `sponsor_billboard` | all four labelled controls (`Mount`/`Deplete`/`Move`/`Teardown`) below the fold | a `fill` ScrollView does the `Spacer`'s job and gives the readouts a window |
| `perf_capture` | `Boost` — the control this fixture's own injected input fault is *about* — 11px under the fold with no fault injected | the boost count joins the readout band (one wrapping row) instead of taking a second pinned line; the roster **name** shrinks like its detail |
| `row_actions` ×3 | the `From` header 33px under the fold, the Edit/Done toggle 9px under it, the swipe hint 9px under it | `VirtualList` → `VList` (the mode bar's `minColumnWidth = "intrinsic"` reads the *widest* label, and 243px of it re-columned the bar to two lines = 134px of a 184px canvas); and the hosted list's window is the pane, with no row-sized floor pushing it off the bottom edge |
| `card_rail` ×2 | `Rally` 61px inside a clip host, on an axis that does not scroll back; `Livery 001` cut with no `disclose` | the rail's cross extent is the plate's own derived height and the **page scrolls** — see "the redesign" below |
| `variable_extents` | the status line 36px below the fold **and** cut | a sibling chrome scroller, conditional on `isShort`, plus a `disclose` on the capped status |
| `scroll_host` ×2 | the `BELOW-LIST MARKER`, the node this fixture asserts must never move, 10px under the fold | the title and the two region labels go where the room does |
| `table_virtualized` | the `Last` line 10px under the fold under `xa` | the same sibling-scroller shape |
| `sponsor_list` | the row detail cut at two lines with nothing to open it | `disclose` — the other half of a declared truncation |

**Two RECLASSIFIED, because the instrument was wrong.** Both were measurement
defects in the probe, and both were fixed in the probe rather than argued:

1. **Paint order was a path sort.** `adapter.paths()` is *sorted* — alphabetically,
   by path — and the probe read its index as "painted later".
   `BellZ/BadgeWhen/.../Count` sorts before its sibling `BellZ/Bell` while the
   renderer paints the badge **on top of** the bell, so a notification count was
   reported covered by the button it decorates. The renderer's own
   `syncZOrder` hands every node an integer through `adapter.setZOrder`, and
   `node.z` is the only thing entitled to the word "later".
2. **`surface = "plain"` was counted as opaque.** `chrome_slots.classify` returns
   nil for it before any class rule (*"AN EXPLICIT `plain` PAINTS NOTHING"*,
   `src/tokens/chrome_slots.luau:844`), so a `plain` Box is a stroke and a shape
   with no fill. `sponsor_avatars`' sixteen "covered" initials were covered by
   the hairline **rim drawn around them**.

A third instrument fix came with them: a victim rect is now intersected with its
`ScrollView` ancestors' windows before the probe asks whether anything covers it,
because a row its own list has already clipped away is not on glass to be covered.

**Zero NEEDS-A-DESIGN-CHANGE.** Round one's lead — *"one page that cannot fit a
640×320 landscape phone and cannot delegate its scrolling — a design change to
demos whose chrome IS their subject"* — was half right and the wrong half was
load-bearing. The pages genuinely could not fit. But **the objection to a page
scroller was to NESTING one**, and two shapes get around it without touching the
subject:

* **a perpendicular page scroller.** `card_rail`'s rail scrolls x; a page that
  scrolls y is a different gesture with a different owner. Nothing is shared.
* **a sibling scroller.** `Chrome` and `ListPane` are two boxes in one stack,
  each owning its own window — which is the arrangement `scroll_host` exists to
  prove is legal. Used on `sponsor_toast`, `variable_extents` and
  `table_virtualized`, and made conditional on `adaptive.conditions.isShort` so
  every viewport that already fitted is byte-identical.

## The redesign: `card_rail`'s rail sizes to its plate

`RailPane` took `height = fill` — *"whatever the three labels around it did not
take, and it can never demand more"*. On a 640×320 landscape at +14 the labels
took all but 23px, the plate needed 84, and the rail's clip host cut the badge.
`fill` is a promise the box will be big enough, and this box was not.

The plate's height is not a mystery, so it is now derived from the same live
facts the plate paints with: its padding, one 14pt line box, its 2px gap, one
12pt line box, **the theme's `chromeInsets.panel`**, **the theme's
`chromeOutsets.panel`**, and the rail's own scroll gutter. The last two are the
theme axis, and they are the reason this took two attempts:

| package | `chromeInsets.panel` | `chromeOutsets.panel` |
|---|---|---|
| classic-desktop, glossy-mobile, scifi-hud | 0 | — |
| compact-pointer | 8 | — |
| glossy-touch | 14 | — |
| fantasy-parchment | 18 | — |
| pixel-quest | 24 | — |
| fantasy-ornate | **30** | **top 20** |

The first version summed padding and line boxes only. It was clean under the
default theme at every viewport and every preference, and **590 findings red
under Compact Pointer at the DEFAULT preference** — the corpus the probe sweeps
is uniform along the theme axis (it mounts one theme), so it cannot test that
axis. The always-on sweep can, and did. Fantasy Ornate then needed the outset
term as well: it is the one shipped package that declares one.

## The note that had gone stale

`p4_foyer`'s TopBar carried a measured 2026-08-13 note refusing the shrink pair:
a text node's shrink floor is **its longest word**, the brand is the single word
`Foyer`, *"so there is nothing for a weight to give… a hand-chosen `minMax` cap
is still the only lever."*

That was true when it was written and is not true now. **Director ruling 1 of
2026-08-14 put an ELLIPSIS rung under the longest-word floor**
(`src/layout/shrink.luau`, COMPACT → TRUNCATE → CLIP), so a one-word wordmark has
somewhere to go and a bare `shrinkWeight` reaches it. Measured as the minimal
set: a `minMax` floor was written under it first and then **deleted**, because
removing it moves neither the sweep nor the readability probe. Removing the
weight itself reddens `proof 'p4_foyer'`.

Two other props were written and then deleted the same way, on the same evidence
— a `shrinkWeight` on the wardrobe card's column (the creator line is what the
column was hugging, so shrinking it shrinks the column) and a `UI.When` hiding
`row_actions`' swipe hint (with the list's window floor gone the pane no longer
demands more than it has). **Three null results, three deletions.**

## Mutation evidence

Every check was broken deliberately and watched. The battery ran in a git
worktree carrying exactly these hunks, each mutation applied to a tree restored
from source afterwards.

### The sweep (`tests/overflow_sweep.spec.luau`), 13 of 17 red, each ONE named case

| mutation | named case that reddened |
|---|---|
| M2 wardrobe: drop the creator line's `shrinkWeight` | `proof 'p5_wardrobe': the solver reports NOTHING…` |
| M4 foyer: put the tab row back on `wrap` | `proof 'p4_foyer': …` |
| M5 toast: chrome scroller back to a bare stack | `scenario 'sponsor_toast': …` |
| M6 billboard: readouts scroller back to a `Spacer` | `scenario 'sponsor_billboard': …` |
| M7 perf_capture: boost count back on its own line | `scenario 'perf_capture': …` |
| M8 perf_capture: roster name stops shrinking | `scenario 'perf_capture': …` |
| M9 row_actions: the mode bar's widest label goes back | `scenario 'row_actions': …` |
| M11 row_actions: the row-height floor comes back | `scenario 'row_actions': …` |
| M12 card_rail: the plate stops paying the theme's chrome **inset** | `scenario 'card_rail': …` |
| M13 card_rail: …stops paying the **outset** | `scenario 'card_rail': …` |
| M14 variable_extents: the chrome scroller is always hug | `scenario 'variable_extents': …` |
| M15 scroll_host: the title and region labels stop hiding | `scenario 'scroll_host': …` |
| M16 table_virtualized: the chrome scroller is always hug | `scenario 'table_virtualized': …` |
| brand: remove the shrink pair entirely | `proof 'p4_foyer': …` |

### The probe (`tools/lune/triage_overflow_waivers`), 3 of 4 red

| mutation | what came back |
|---|---|
| M19 `plain` counted as opaque again | the `sponsor_avatars` false positive returns — `Initial "" — covered by …/Avatar/Rim [Box]` |
| M20 occlusion stops clipping the victim to its scroll window | a false covering returns — `…/Row/Card/Row/Name "Row 07" — covered by /DropLab/Main/Hand [HStack]` |
| M18 paint order back to the alphabetical path sort | **NULL RESULT on the current corpus** — and it BITES on the pre-fix one |
| M17 sponsor_list's capped detail loses its `disclose` | `TEXT-TRUNCATED … /ListLab/…/Labels/Detail "Secondary line, long enough to wrap…"` |

**M18, published as both.** On today's corpus the verdicts do not move, because
the only surface that produced the false positive is fixed. Run against the
corpus at `b377fe9` with the same probe, reverting `node.z` to the path sort
resurrects **4 TEXT-COVERED verdicts**, every one of them
`/Foyer/Root/TopBar/BellZ/BadgeWhen/then/BadgeBubble/Count "5" — covered by
/Foyer/Root/TopBar/BellZ/Bell [Button]`, at `narrow-portrait@+14` and
`compact-phone-portrait@+0`. The z fix is load-bearing; today's corpus is simply
no longer a place it can be seen.

### Four mutations that reddened nothing, and what each one bought

M1, M3, M3b and M10 are the null results above. Three became deletions; M3b
(`lineLimit`/`disclose` on the brand) stayed, and the reason is itself a finding:
**the probe only reads nodes under a waived finding**, so a truncation on a
surface that files none is invisible to it. Those two props are there on the
standing rule that player copy is never cut without an opener, and no always-on
check bites for them. That is recorded in the code rather than claimed as proof.

## Live, on the real engine

Studio, Play, driven through the demo picker (`workspace.LuauUIShowcaseAPI`), no
direct mounts and therefore no probes to clean up. `mounted` asked, not `current`.

* **`card-rail`** — `ok: true`. `/CardRail/Page` is a real `ScrollingFrame`
  (377×633), and `/CardRail/Page/RailPane/Rail` is a nested `ScrollingFrame`
  365×62 with `ClipsDescendants = true`. The derived plate height is **62px**,
  which is the headless number to the pixel under Studio Neutral. The `[c1]`
  card is 132×54 at y 123; its `Rally` badge ends at **y 165** against a rail
  that clips at **y 185** — 20px of headroom inside the clip host, and both
  labels (`Livery 001`, `Rally`) render whole.
* **`variable-extents`** — `ok: true`, `/VariableExtents/Chrome` is a
  `ScrollingFrame` at its **hug** height (385×95) on a tall window, i.e. the
  conditional is off exactly where there is room.
* **`table-virtualized`** — `ok: true`, `/TableVirtualized/Chrome` 377×92, same.
* **`row-actions`** — `ok: true`, 69 GuiObjects.

**Tier**: headless Lune is the regression signal, Studio is the engine claim
above. The defects themselves live at 640×320 with `preferredTextOffset = +14`,
which a desktop Studio window cannot reproduce (`GuiService.PreferredTextSize` is
not script-writable), so **no device claim is made here** — what Studio proves is
that the redesigns mount, clip and derive correctly on a real adapter.

## Suites

| | before | after |
|---|---|---|
| LuauUI (`tests/run`) | 5618 / 0 at HEAD `602987a` | **5618 / 0** |
| Rascal Rally | 3280 / 0 | **3280 / 0** |

No case count moved: this round deleted waiver rows and edited fixtures, and
added no spec. `stylua --check` clean on every file touched;
`tools/check_source_size.py` PASS with `KNOWN_OVER` empty.

**No `src/` file was touched**, so the LuauUI-and-Rascal-Rally rider is satisfied
by evidence rather than by edits: no public contract, default, behaviour or
distribution output moved, and the game's suite is re-run above to prove the live
consumer is current.

## One finding this round did NOT fix, recorded rather than left silent

`p4_foyer`'s `SearchSlot` is a `UI.ViewThatFits` with `width = fill`. On a 320px
phone at +14 the leftover is 0, the ladder falls through to its last candidate
(*"the fallback when none fits"*, api.md), and the 44px icon button then paints
at its natural size **inside a 0px slot** — half on top of `Refresh`. Measured at
`b377fe9` and unchanged by this round: `IconForm` 44×44 at x 142, `Refresh` 44×44
at x 148.

It is not one of the sixteen and no diagnostic files it: the solver sees no stack
overflow, and the probe's occlusion pass only counts **Text** as a victim. It is
a framework-behaviour question — whether a losing-by-fallback candidate may paint
outside the slot it was offered — not a fixture edit, so it is booked here rather
than patched around.
