# swiftui-parity-round4 — mutation evidence, row by row

**Every row in the `swiftui-parity-round4` gate was proved able to FAIL.** For each
mutation below: the guarded thing was broken in the working tree, the **named row's
own `run` command** was executed exactly as `tools/lune/gate.luau` executes it
(`bash -c`, from the library root), the row was watched to redden, and the break was
restored immediately. Nothing here is an argument; every line is a run.

Date: 2026-08-16. LuauUI baseline **5618 passed / 0 failed** (committed tree and
working tree agreeing). Rascal Rally baseline **3280 passed / 0 failed**.
`tools/check_source_size.py` PASS with `KNOWN_OVER` empty.
`stylua --check src tests tools bench examples` clean.

## Baseline first

A mutation result means nothing without it: **all 18 runnable rows were confirmed
PASS on the unmutated tree** before any mutation was applied, and the tree was
confirmed byte-identical to its pre-mutation state afterwards (`git status` shows
only the four files this stage deliberately changed).

The nineteenth row (`studio-and-device-evidence`) is a `state` row and has no
command. The twentieth (`prior-gates-unregressed`) is discussed at the bottom.

## The battery

| # | row | what was broken | result |
|---|---|---|---|
| **M1** | `library-suite-green` | `require("./sorted_entries.spec")` removed from `tests/run.luau` — an unregistered spec is a silent zero | **BITES** |
| **M2a** | `time-based-easing` | `curves.evaluate` returns `alpha` — every curve becomes linear | **BITES** |
| **M2b** | `time-based-easing` | the `WITHDRAWN 2026-08-15, by the consumer rider this ADR commissioned.` marker deleted from ADR-0033 | **BITES** |
| **M2c** | `time-based-easing` | `The engine is not cheaper here.` rewritten into a speed claim | **BITES** |
| **M3a** | `foreign-instance-seam` | `Foreign = { Parent = "host" }` changed to `"layout"` — the reserved authority spent elsewhere | **BITES** |
| **M3b** | `foreign-instance-seam` | the inverted-seam sentence (`nothing LuauUI owns travels **out**`) deleted from ADR-0034 | **BITES** |
| **M4a** | `preferred-transparency` | `sheet_model.backdropTransparency` returns `base` — the preference stops composing | **BITES** |
| **M4b** | `preferred-transparency` | the shadow / focus-glow refusal reversed in ADR-0035 | **BITES** |
| **M5a** | `when-branch-scope` | both `thenView(branchScope)` call sites hand the ENCLOSING scope instead | **BITES** |
| **M5b** | `when-branch-scope` | `There is deliberately **no elseView**` downgraded to `An elseView is planned` | **BITES** |
| **M6** | `sorted-entries-determinism` | the key comparator removed (`return false`) — the sort is gone | **BITES** |
| **M7a** | `two-dimensional-focus` | the perpendicular `lineStep` dispatch disabled | **BITES** |
| **M7b** | `two-dimensional-focus` | the deleted `bindFocusGraph` seam reintroduced into `virtual_grid.luau` | **BITES** |
| **M8** | `hit-expander-z-order` | the qualifier loses its `hud` / `R1` measurement citation | **BITES** |
| **M9** | `tint-fill-tag` | `buildPackage` stops emitting the `Tint fill` rule (one-emitter drift) | **BITES** |
| **M10** | `zstack-hugging-margin` | the zstack arrange aligns in `innerW`/`innerH` again — the box it DENIED the child | **BITES** |
| **M11** | `native-scroll-autobind` | the shared installer in `native_scroll_binding.new` neutered | **BITES** |
| **M12** | `app-chrome-and-screen-gutter` | `appChromeRects` renamed in `environment.luau` — nothing declares or merges it | **BITES** |
| **M13** | `demo-picker-mounted` | `mountedId` collapsed back into `currentId` — `mounted()` becomes `current()` | **BITES** |
| **M14a** | `comparison-docs-honest` | the stale `Nothing here is implemented; this is the list.` preamble restored | **BITES** |
| **M14b** | `comparison-docs-honest` | an honesty-appendix bullet (`No Fusion project was built for this comparison.`) deleted | **BITES** |
| **M15a** | `source-size-cap` | a waiver added to `KNOWN_OVER` | **BITES** |
| **M15b** | `source-size-cap` | `src/render/renderer.luau` padded past the 200,000-char Source cap | **BITES** |
| **M16** | `checker-battery` | a `src/` file left unformatted | **BITES** |
| **M17** | `theme-sync-red-carried` | `circularSize = 30,` deleted from `fantasy_parchment.luau` — the tempting green-making fix | **BITES** |
| **M18** | `rascalrally-consumer` | `tests/luauui_motion_and_scroll_contract.spec.luau` removed from the game | **BITES** |

**24 of 24 bite.**

## Second pass — twelve more rows, twelve more mutations

The first pass enumerated what it had left uncovered; the second pass took twelve of
those items. Same protocol: baseline PASS confirmed for all twelve first, then one
mutation each, then restore.

| # | row | what was broken | result |
|---|---|---|---|
| **M19** | `authored-presentation-composition` | authored rotation MULTIPLIES instead of adding (`presentation.luau`) | **BITES** |
| **M20** | `cross-surface-overlap` | the `FULLY_FADED` alpha clause deleted in `renderer.paintsNothing` — a faded surface covers again | **BITES** |
| **M21** | `leaf-opacity-refusal` | the structural-class exclusion deleted, so the five structural classes get the fade refusal | **BITES** |
| **M22** | `nested-instance-tree-deferred` | `src/` starts constructing a `UIListLayout` — ADR-0032 Decision 6 reversed | **BITES** |
| **M23** | `core-settle-phase` | the settle pass never restarts after a write (`wrote = true` -> `false`) | **BITES** |
| **M24** | `virtual-grid-family` | the column-flow transpose collapses to row flow (`gridIsColumn` -> `false`) | **BITES** |
| **M25** | `variable-item-extents` | the running-offset prefix sum forgets the gap | **BITES** |
| **M26** | `text-line-box` | DEFECT 1 restored: the line box floors instead of ceiling | **BITES** |
| **M27** | `measure-memo-key` | the offered height goes back into the memo key — L-37 restored | **BITES** |
| **M28** | `table-virtualized` | the `virtualized` + `scrolls = false` refusal deleted | **BITES** |
| **M29** | `hud-composition-collisions` | `holdsLane` stops reaching the composition | **BITES** |
| **M30** | `table-gutter-and-divider-press` | the scrollbar-inset axis pair transposed (`right`/`bottom` swapped) | **BITES** |

**36 of 36 bite across both passes.**

### M20's first attempt — another bad mutation, not a weak row

First aimed at `surface_overlap.luau`'s `if #covering < 2` precondition, which did NOT
redden the row: that is the *scan* precondition, not the *cover* rule, and none of the
row's greps depend on it. Re-aimed at the clause ADR-0028 itself names — the
`FULLY_FADED` alpha test in `renderer.paintsNothing` — it bites, and it bites on
exactly the two cases the ADR predicts (`a surface at opacity = 0 covers nothing` and
`a framework fade to nothing covers nothing`). Third time this battery has caught the
mutation rather than the row.


## The two mutations that did NOT bite on the first attempt, and what each was

Both are recorded because a mutation battery with no failures in it is usually a
battery that was not run.

### M5a, first attempt — a bad mutation, not a weak row

The anchor was `scope:child(path .. "/then")`. That string occurs exactly once in
`src/mount.luau` — **inside the block comment** that explains why two `UI.When`s
cannot share a scope. Editing it changed a sentence and no behaviour, so the row
correctly stayed green. Re-aimed at `bp.props.thenView(branchScope)` (two real call
sites) it bites. The lesson is the ordinary one: a mutation must be confirmed to
have changed what executes, not merely what a file says.

### M17, first attempt — a REAL hole in the row, found and fixed

The row asserted that three progress metrics still exist in a shipped theme package
by grepping their bare names. Deleting `circularSize = 30,` did **not** redden it,
because `examples/themes/fantasy_parchment.luau` names all three metrics in a
**comment sixty lines above the table**:

```
-- ...and `controls.progress.circularSize` / `circularThickness` / `spinnerDotSize`
```

So the grep was satisfied by prose *describing the feature it had just lost* — a
check that cannot fail, of exactly the class this manifest's header exists to refuse.
The row now anchors on the assignment (`^[[:space:]]*<name> = `), the baseline still
passes, and the mutation bites. **This is the reason the battery was run at all**:
the row read as sound, was reviewed as sound, and was not.

## The two rows this battery could not prove, said plainly

**`studio-and-device-evidence`** is a `state = "FAIL_ENVIRONMENT"` row with
`releaseBlocking = false`. It has no command, so there is nothing to mutate: it is a
declaration that a Play session and physical hardware were unavailable, and it reads
as a non-PASS in the roll-up by construction. It cannot pass, which is the point;
it also cannot fail, which is why it is a *disclosure* rather than a check, and this
paragraph is the honest statement of that. If it should exist at all: yes — the
alternative is a gate whose reader cannot tell that four device questions are open.

**`prior-gates-unregressed`** re-runs all 28 preceding gates through
`tools/prior_gates.sh`. Mutation-proving it means deliberately reddening a prior gate
and sitting through a second full sweep, and a sweep already takes long enough that
running two of them serialises everything else in the tree. It is unproved here, the
same statement round 3's block makes about its own copy, for the same reason. What
IS demonstrated, and is the stronger evidence: **this row's mechanism already caught
a real regression during this stage** — `large-text-accessibility` / `overflow-policy`
had been FAIL_RECOVERABLE for two days because `4a948d0` renamed the LT6-ACTION case
out from under its grep. The check is not hypothetical; it found something, and the
grep was repaired rather than allow-listed.

## Reproducing any row

```bash
# from the library root
python3 - <<'EOF'
# the row's own `run` string, executed exactly as gate.luau executes it
EOF
tools/gate.sh swiftui-parity-round4
```

The per-row harness used here (`rowrun.py` / `mutate.py`) extracts each row's `run`
value from `tools/lune/gate_manifest.luau` and shells it from the library root, which
is what `gate.luau` does; running the whole gate is the same assertion, more slowly.
