# M2 fix round — A-H1, A-H2, B-H1, A-M1

**Status: DONE.** All four findings closed, every claimed mutation measured to
bite, plus one red gate row found while verifying and repaired. Nothing in `src/`
changed except comments. No extraction-locked file was touched and nothing is
CONTESTED.

| finding | outcome |
|---|---|
| **A-H1** the two laziness pins do not bite | **FIXED** — three pins over one require-recording instrument; P1/P2 both redden, plus a third mutation (a require reached from a frame) |
| **A-H2** falsified idiom + retracted 831 KB asserted as fact | **FIXED** — all six review sites plus two more the review did not list; `check_types --selftest` still PASS |
| **B-H1** the fence measures the smaller rect; the expander is unexamined | **FIXED** — EXPAND 15 reads `hitRectOf` under R18, plus a three-half paint-inert guard; both named mutations redden |
| **A-M1** the false "kept and marked SUPERSEDED" | **FIXED (made true)** — the table, inventory and ranking restored under a SUPERSEDED heading; the unmarked survivor banner-marked |
| *(new, not in the review)* `surface-ledger-complete` red at HEAD | **FIXED** — `Facet.preload` had no ledger row |

## Commits

| commit | subject |
|---|---|
| `1f0b99d` | the laziness pins watched the cache, which cannot say whether anything was deferred |
| `08eb931` | the instrument built to stop an unfalsifiable claim carried one its own first run had falsified |
| `9a5ea84` | the fence measured the smaller of the mark's two rects, and the bigger one is the one that reaches |
| `509d747` | "kept and marked SUPERSEDED" was true of nothing; the table is kept and marked now |
| `1f9e32c` | `preload` shipped as a public export with no ledger row, and the gate has been red since |

All five through `tools/commit_isolated.py`; the DROP list was empty on every run
and the republish step reported the expected path count each time. Another
implementer's commit (`6628ebd`, the showcase-chrome work) landed underneath the
first two and the compare-and-swap handled it without incident; none of their six
files appears in any of my commits.

---

## A-H1 — the laziness pins now watch the CALL, not the cache

**The diagnosis the review made is exact, and the root cause is one sentence.**
A second `require` is a table lookup, so *every* identity test written from
outside the file is a fact about the module cache and never about
`src/init.luau`. That is why `rawequal(require(m), require(m))` passed with the
entire mechanism removed, and it is why the fix could not be another identity
test.

**The instrument.** `src/init.luau` is loaded a second time through `luau.load`
with an environment whose `require` records the path and delegates to the real
one (which answers from the cache, so nothing loads twice and nothing is timed).
Every `require` the file performs is then visible — at load, at construction, or
inside a frame. The sandboxed copy shares every dependency with the real one, so
`probe.module.newCore()`, `probe.module.UI` and the real `mountLib` are the same
modules the rest of the suite uses.

Three pins in `tests/virtualization.spec.luau`:

1. **the SET** — the load requires the fifteen typed controls (asserted
   *positively first*, so a recorder wired to nothing cannot satisfy the
   "was not required" lines) and not the four with no spec type. The deferred set
   is **derived** (every `@self/` path the source names, minus every one the load
   asked for), so a fifth deferral joins the pin instead of escaping a hand list.
2. **the SEAM** — building a VirtualList fires exactly
   `@self/controls/virtual_list`; mounting fires nothing; thirty scroll steps, a
   window slide and an off-window edit fire nothing.
3. **PRELOAD as a set, not a count** — it must ask for every deferred path and no
   other, the number it reports must equal the number it required, and the module
   it hands back must be the same table the closure gets.

### Mutations — red output

**P1, four requires restored to eager top-level** (isolated copy):

```
  ✗ requiring Facet loads the fifteen typed controls and defers exactly four (T15)
      expected  to be @self/controls/async_image @self/controls/chip
                      @self/controls/virtual_grid @self/controls/virtual_list
  ✗ the deferred require fires at the construction seam and never in a frame (T15)
      expected  to be @self/controls/virtual_list
  ✗ Facet.preload() force-loads exactly the deferred set, and twice is a cache hit (T15)
      [never] expected  to be
3 failed, 9 passed
```

**P2, `preload`'s body gutted to `return 4`:**

```
  ✗ Facet.preload() force-loads exactly the deferred set, and twice is a cache hit (T15)
      expected  to be @self/controls/async_image @self/controls/chip
                      @self/controls/virtual_grid @self/controls/virtual_list
1 failed, 11 passed
```

**P3 (mine, not the review's), a require reached from a per-frame path** — the
cell factory calls `preload()`, i.e. a module compile in the middle of a frame:

```
  ✗ the deferred require fires at the construction seam and never in a frame (T15)
      expected @self/controls/async_image ×12 @self/controls/chip ×12
               @self/controls/virtual_grid ×12 @self/controls/virtual_list ×12 to be
```

**What the instrument does not see**, stated in the file so nobody reads it
wider: only requires made *by* `src/init.luau`. A control module's own internal
requires run under the real global. This pins the framework's own deferral seam,
which is what the four entries and `preload` are a claim about.

## A-H2 — the falsified idiom and the retracted number

All six sites from the review's table, plus two the review did not list
(`check_types.py:218` and `:295`, the same idiom inside the selftest's own prose,
the second of which prints on every selftest run).

| file | before | after |
|---|---|---|
| `tools/check_types.py:5-8` | "defers each control's `require` … keeps the parameter types through `typeof(require(...))` … worth 831 KB" | fifteen eager bindings are the ONLY spelling that carries an exported type; the idiom was falsified by this check's own first run; four deferred = 228 KB [131..313]; 632 KB remains |
| `tools/check_types.py:182` | "this is what a lazy require without `typeof(require(...))` looks like" | "this is what deferring that control's `require` looks like: a module's exported types do not survive any deferral spelling" |
| `tools/check_types.py:218, :295` | two more idiom mentions in the selftest | "the shape a DEFERRED require leaves behind" |
| `tests/types/controls_witness.luau:4-9` | same sentence, same idiom | same correction, citing §7 |
| `src/init.luau:31` | "the nineteen composite controls are 831 KB of it" | ~2.76 MB retained; all nineteen would be 860 KB [762..860]; the 831 KB named as retracted subset arithmetic |
| `src/init.luau:50` | "2,537 KB eager against 2,305 KB … i.e. 232 KB" | "2,763 KB eager against 2,535 KB … i.e. 228 KB [131..313]" |
| `src/init.luau:55` | "the remaining 599 KB" | "the remaining 632 KB" |
| `src/init.luau:449` | "232 KB of Lua heap" | "228 KB [131..313] of Lua heap" |
| `capture-plan.md:61` | records the device number against 831 KB | the current pair, with an explicit "do not record against 831" |
| `examples/performance/client/init.client.luau:30` | "the nineteen composite controls are 831 KB" | the current pair, naming the retraction |

Every figure was verified against the round's own artifact before writing:
`requalification.md` §7 rows read `shipped 228 KB [131..313]`, `ceiling 860 KB
[762..860]`, arms `2 763` / `2 535` / `1 903`, and "The other **632 KB** (860 minus
228)". Retracted numbers are named as retracted where they were quoted rather
than silently deleted, so a reader who remembers 831 KB learns why it is gone.

`python3 tools/check_types.py --selftest` → **PASS** (unmutated / M1 / M2 / M3),
both target files restored. `python3 tools/check_types.py` → **PASS — 19 Controls
entries (15 typed, 4 declared `any`)**.

## B-H1 — the fence learns to see hit rects (R18)

**Measured first, before writing anything** (probe against `worldLib`, viewport
390×150):

| fixture | `/S/C/Clock/Compact` | mark rect | mark hitRect | overlap |
|---|---|---|---|---|
| `ringScreen(false)` | `Text` 40×20 @0,46 | 20×22 @370,46 | 44×44 @358,35 | none |
| `ringScreen(true)` | `VStack` (fill) 370×46 @0,46 — **passive** | 20×22 @370,58 | 44×44 @358,47 | **12×44 over the VStack** |
| `ringScreen(true)` | `…/Compact/Live` Button 69×46 — **interactive** | | | none |

So **as shipped, the floor overlaps only passive content**, which is exactly the
R18-exempt case. The fence passes green and is not vacuous.

**What EXPAND 15 does now**, over both fixtures and the whole screen (excluding
the mark's own subtree and its ancestors, which contain it by construction):

* the **painted** rect must touch nothing at all, passive or interactive;
* the **hit** rect must touch no interactive node — against that node's own rect
  *or* its own hit floor. Interactive is read from the fake target's own seams
  (`onActivate`, `secondaryActivate`, `pointer`, `dragDetector`, `touchGestures`,
  `scrollHandler`, `discloseZone`);
* passive overlaps are **counted and asserted non-zero**, so the exemption stays
  a measured fact. The R18 reason — F1 accessibility floor and platform
  convention over passive content, tap-ambiguity defect class over interactive
  content — is written into the case.

**The paint-inert guard**, three halves that never rely on a transparency value
being obeyed:

1. the expander is born writing `Text = ""`, `BackgroundTransparency = 1`,
   `AutoButtonColor = false`, `BorderSizePixel = 0`;
2. **no paint channel reaches it.** Every fill, corner, stroke and state in a
   Facet sheet hangs off a `facet-*` CLASS selector applied through
   `CollectionService:AddTag` in `syncTags`, and an explicit hand-off is recorded
   in the `Facet_PaintClaims` attribute. The expander is `Instance.new`'d in
   `setHitRect` and enters neither. Every line of the live adapter mentioning an
   expander is scanned for those channels (zero), and the **thirteen** properties
   written to an expander anywhere are enumerated from source and pinned against
   a declared inert set;
3. **the sheet's remaining reach is enumerated by name.** The rules that can match
   a tagless `TextButton` are exactly `Button default/BackgroundTransparency`
   (declared `= 1`), `Button text default/FontFace`, `Button text
   default/TextColor3` and `Disabled button/TextTransparency` — none of which
   deposits anything on an empty-text transparent button. A new `TextButton` rule
   that paints reddens this line rather than a screen.

### Mutations — red output

```
(a) the compact form's Button given `width = fill`, so the expander overlaps it
  ✗ no framework instance covers any node of the screen, painted OR reachable (R18)
      expected /S/C/Clock/Compact/Live under the mark's 44px floor by 12x44: FORBIDDEN (R18)
            to be /S/C/Clock/Compact/Live under the mark's 44px floor by 12x44: allowed (R18)

(b) CollectionService:AddTag(expander, "facet-surface-base") in setHitRect
  ✗ the hit expander is paint-INERT by construction, not by transparency (R18)
      expected paint channels reaching the hit expander:
        AddTag: CollectionService:AddTag(expander, "facet-surface-base") | … to be
      paint channels reaching the hit expander:

(c) the hit sweep reverted to `mark.rect` (i.e. the old fence, with (a) in place)
  ✗ no framework instance covers any node of the screen, painted OR reachable (R18)
      expected false to be true      <- the non-vacuity assertion
```

(c) is worth noting on its own: reverting to the smaller rect does not merely
stop catching the overlap, it makes the sweep see *nothing*, and the non-vacuity
line says so.

## A-M1 — the claim made true

The claim lives in a commit message (`84b38bb`), which cannot be edited, so the
honest move was to make it true. `requalification.md` §7 now carries a
**SUPERSEDED** block containing the subset table with a per-row retraction reason,
the method that produced it with both defects named, the 19-row inventory kept
explicitly as an ORDER rather than as costs, and the candidate ranking with its KB
column marked superseded and its **verdict column marked as standing** — which is
the half the commit message called load-bearing, because it is what said the
nineteen controls were the only candidate worth a change and closed the other six.
The block states in its own first line that nothing in it may be quoted as a
saving, and states that it is a restoration rather than a re-measurement: no
sample was re-taken. `grep -c supersed` on that file: **0 → 5**.

The unmarked survivor at `task-15-report.md:83-88` now carries a retraction banner
naming both defects and pointing at the current pair; the table itself is left
unedited because it is what that report said on the day.

## The extra: a gate row that has been red since Round A

Not a review finding — found while verifying. `lune run
tools/lune/check_surface_ledger` fails at HEAD *before* my changes with
`top-level export 'preload' is not classified in the surface ledger`. Round A
added `Facet.preload` and never added its row, so the `surface-ledger-complete`
gate row has been red since `8202a9d`: the check the whole ENF-5 stage exists to
keep green, failing on the one export the wave was written to add. Confirmed
pre-existing by running it against a HEAD-only copy. Repaired with a row that says
what the seam *is*, citing ADR-0037, the three new pins and `check_types.py`.
`check_surface_ledger: PASS`.

## Verification

All suite measurement in private `rsync`/`git archive` copies; no concurrent
`lune` run shared a tree.

```
HEAD + this round (git archive export)        6883 passed
HEAD alone, other implementer's files reverted 6881 passed   (delta = +2, exactly the two new cases)
check_types                                   PASS — 19 entries (15 typed, 4 `any`)
check_types --selftest                        PASS — unmutated / M1 / M2 / M3
check_surface_ledger                          PASS
check_source_size                             PASS
check_comment_codes                           PASS — 0 orphans (ceiling 0), 25 codes (ceiling 25)
check_brand_drift                             PASS
stylua --check                                clean on every edited .luau
```

**The stated baseline of 6865 is stale.** HEAD at the start of this round
(`3ad40b0`) measures **6881**, not 6865, in a clean export. The +16 is not mine —
it predates this round. Rascal Rally is untouched (3449 not re-measured; nothing
in this round changes a public contract, a default, a behaviour or a distribution
output, and `Facet.preload`'s ledger row is documentation).

**A false start worth recording, because it nearly produced a wrong number.** My
first delta measurement compared two `rsync` snapshots taken minutes apart and
both read 6881, which looked like "my two new tests added nothing". They did not:
the other implementer committed two tests *between* the two snapshots and the
offsets cancelled. In a shared tree, a baseline must be pinned by content (revert
the other agent's paths to HEAD in the same snapshot), never by timing.

## Concerns

1. **R18's "banned over interactive" is currently enforced by the fixtures, not by
   the framework.** Mutation (a) is not synthetic — it is a legal author screen: a
   compact form whose interactive child is `width = fill`. The solver reserves the
   mark's 20px column and gives the form `innerW - markW`, so a fill-width Button
   ends exactly where the mark begins and the 44px floor reaches 12px back over
   it. The shipped fixtures happen not to do this, so EXPAND 15 is green; an
   author who does it gets two overlapping actionable targets. `src/render/hit_lift.luau`
   already resolves *which* one wins (it lifts the expander's host above the
   siblings its floor reaches into, deterministically), so the band is delivered
   rather than dead — but it is delivered to the chevron while the player believes
   they pressed the button, which is the defect class R18 names. **A real fix is
   solver-side** (reserve `markW` + the floor's overhang rather than `markW`), and
   `src/layout/solver.luau` is extraction-locked and 2,190 characters from the
   write cap. I did not attempt it and it is not CONTESTED for this round — the
   brief scoped B-H1 to the fence and the ruling — but it should be a booked item,
   because the fence will catch it the first time a fixture grows a fill-width
   interactive compact form.
2. **The steady-state half of the seam pin has no reachable production mutation
   today.** `src/init.luau` runs no per-frame code, so nothing in it can move a
   require into a frame; P3 had to reach the recorder through the cell factory. The
   assertion is a fence for the day the file gains such a path, and it is honest
   about that in its own comment — but it is the one of the three that cannot be
   reddened by editing `src/init.luau` alone.
3. **`comments-plain` is still at exactly its ceiling** (25 of 25) and this round
   added comments to `src/init.luau`. It stays green because none of them carries a
   private code, but the margin the review flagged is unchanged: the next private
   code added to any maintained `src/` module reddens the row.
4. **A-M5's second half is untouched and worth re-reading**: the same
   `check_comment_codes` run reports 185 sites / 150 orphans in the five
   extraction-locked modules, counted and never gated.
5. **The A-H2 edits are prose, and prose has no gate.** Nothing mechanically
   prevents the retracted 831 KB from being re-typed. The one structural
   improvement available cheaply would be a checker that refuses the literal
   `831 KB` outside the SUPERSEDED blocks; I did not add one because it is a new
   gate row and outside this round's scope.
