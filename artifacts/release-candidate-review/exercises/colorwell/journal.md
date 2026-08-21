# Journal — contributing a ColorWell control to Facet

Format: chronological. Every friction point marked **[F]**.

## 0. Finding the contributor guidance

Repo root: `GameStudio/ui/Facet`.

**[F1] There is no README at the repo root.** `ls` shows `ui_todo.md`, `phases.json`,
`requirements.json`, `rokit.toml`, `run-tests.sh`, `sweep.luau` and directories. A first-time
contributor's first instinct — `cat README.md` — fails. The only root-level Markdown is
`ui_todo.md`, which is a TODO list, not an entry point. I found the real entry point by
listing `docs/`, which contains `adr extending guide handoff INVENTORY.md lessons plans
reference research`. `docs/guide/README.md` exists; the root does not link to it.

Guessed that `docs/extending/new-control.md` is the doc for my task. Reading it next.

## 1. The playbook itself

`docs/extending/new-control.md` is genuinely good — ordered steps, a command and a
pass condition per step. It tells me to read `docs/reference/constitution.md` first
(338 lines) and `docs/plans/agent-execution-contract.md` (380 lines). Both read.

Baseline suite before touching anything: **6799 passed**, exit 0. (~85 s.)

## 2. `scaffold_cli control color_well`

Ran exactly as documented. Worked first try. Output named 7 registration points.

**[F2] The playbook's scaffold table is missing a row.** It lists 6 files; the
scaffold writes/edits **7** — it also stamps a fixture into
`tests/lib/large_text_fixtures.luau`. Harmless but it means the table is not the
authority it claims to be ("stamps and REGISTERS everything so nothing can be
forgotten").

**[F3] The scaffold's own output breaks 5 PRE-EXISTING tests that the playbook never
mentions, and it is not obvious they are mine to fix.** Red state after scaffold:
`15 failed, 6795 passed` — but only **10** of those 15 are the deliberate stubs
(+1 TODO = 11 new tests). Four tests that were GREEN before the scaffold ran are now
RED:

- `documentation gate: the shipped theme surface and its docs agree > the live
  repository passes every documentation obligation`
- `documentation gate: every claim about the compared framework is cited > the live
  comparison document passes…`
- `… > passes on a minimal well-formed document (the fixture is not accidentally red)`
- `the guide index catalogs the live public surface > counts a catalog entry for
  every namespace member, export and playbook`

all four with the same cause: `docs/guide/README.md: the capability catalog does not
name 'Controls.ColorWell'`. **The playbook's §4 Documentation says to fix
`docs/reference/api.md` and to "add a paragraph to the relevant `docs/guide/` page"
if the control introduces a new concept. It never says that a catalog ROW in
`docs/guide/README.md` is MANDATORY for every control, concept or no concept.** The
scaffold knows how to edit api.md; it does not edit the catalog it is required to
edit. I only learned this from a test failure message (which, to the repo's credit,
names the exact fix).

- `ADR-0037: the Controls namespace > exports exactly the nineteen composite controls
  the ADR names, and nothing else`

**[F4] A hard-pinned allowlist that every new control must be added to, documented
nowhere in the playbook.** `tests/controls_namespace.spec.luau` pins the Controls
namespace to a literal nineteen-name list. Adding the twentieth control reddens it.
The playbook explicitly enumerates what I may not edit (`gate_manifest.luau`,
`phases.json`) which reads as an exhaustive statement about test-infrastructure
edits — so hitting a pinned list I *must* edit was a genuine "am I allowed to do
this?" moment. Worse, the playbook's own prose reinforces the number: "The nineteen
`Facet.new<Name>` builders that still exist are the pre-ADR set" — that nineteen is
about the DEPRECATED old-form builders, a different set that happens to share the
count, so the failing message reads as if I had added a deprecated builder.

## 3. Designing the control against the docs

The reference material is genuinely excellent — `docs/reference/api.md` is 8000+
lines and answered nearly everything (tint forms, Button-as-container, Grid laning,
the contribution bundle field list, `presentAnchored`'s placement rules). Where I had
to read framework internals, it was for these reasons:

**[F5] The playbook's own 44px example is a lint violation.** `new-control.md` §3
says, in bold: *give your control's hit surface an explicit
`height = { type = "minMax", min = 44 }`*. `tools/lune/check_theme_drift` has the
pattern `[^%w_]min%s*=%s*%-?[1-9]%d*` and rejects exactly that literal inside
`src/controls/`. The right spelling is `min = "targetSizes.minimum"` — which I only
learned by reading `check_theme_drift.luau` and grepping the shipped controls. The
scaffold warns about `textSize` in a comment; nothing warns about this, and the
playbook actively recommends the wrong thing.

**[F6] `Facet.paths` is not public, so a control cannot safely route its own paths.**
Every shipped composite routes Activate with `string.match(path, "/{idPattern}/…")`
and gets `idPattern` from `require("../paths").escape` — an INTERNAL module. A
control's `id` is author data and may legally contain a Lua pattern magic character
(`"Kart 1 (paint)"`), so an out-of-repo control following the exemplar verbatim has
a latent routing bug it cannot fix with public API. I sidestepped it with plain-text
suffix comparison, which needs no escaper — but the exemplars teach the pattern form.

**[F7] The `specGuard` example in api.md does not compile as written.** It shows
`function gauge.build(core, spec)` — two arguments — while calling `Facet.specGuard`
inside, with no `Facet` in scope. The real seam is `build(Facet, core, spec)`
(constitution §3). A first-time reader copying that block gets a nil index.

**[F8] `docs/extending/new-control.md` never mentions `tests/run_one`.** The playbook
says to "Loop `./run-tests.sh`" — 85 seconds a run. `tests/run_one.luau` exists,
runs one spec in ~2 s, and its own header says it exists precisely for this loop. It
is not referenced from the playbook, the guide index, or the scaffold's closing
message. I found it by `ls tests/run*`. This is the single biggest inner-loop cost.

## 4. Two real framework findings, both invisible to the docs

**[F9] `transientScope` silently downgrades navigation to a FLAT ring, so a
composite with a transient surface cannot have 2-D navigation inside it.**
I built the palette as a `UI.Grid` because `src/present/focus_map.luau` derives
per-lane navigation groups from a `UI.Grid` holding ≥2 focusables — the pad idiom for
a tiled surface, for free. It never fired. Two separate causes, neither documented:

1. `presenter.present` picks `navigationGroupsFn` ONCE, at present time, from
   `hasHorizontalStructure(root.node)`. My Grid lives behind a `UI.When`, so at
   present time the screen has no horizontal structure and the flat ring is locked in
   for the surface's life. The presenter DOES have a late-upgrade path
   (`syncContributions`), but it only upgrades for a late `focusGroups` CONTRIBUTION,
   never for late layout structure. A `UI.When` that opens a Grid can therefore never
   get grid navigation.
2. Even if it did: `handle.syncTransientScopes` pushes
   `graph.pushScope({ name, trap = true, order })` — a **flat** scope — over the
   control's whole subtree while `transientScope.active`. A flat scope navigates on
   one axis. So the trap-and-restore I want and the 2-D navigation I want are mutually
   exclusive, and nothing says so. `api.md`'s `transientScope` line ("focus is trapped
   within rootPath and restored") does not mention that it flattens.

I kept the trap (focus restore is worth more than lane movement), kept the Grid as the
right LAYOUT, and wrote the limitation into the control header, the spec, and api.md
rather than quietly claiming a lane idiom the control does not have.

**[F10] A content `Button`'s `label` is documented as "the semantic label" but
reaches nothing.** `renderer.applyProp` writes `label = ""` to the adapter for any
Button with children ("a content button's label is SEMANTICS, not paint"), and
`grep -rn "Accessib|semanticLabel" src/client src/render` returns nothing: there is no
accessibility channel behind it. So for an icon-only or content-only button the label
is consumed by the solver and the focus story and is invisible to the player and to
any assistive tech. This changed my design: every palette tile DRAWS its colour name
instead of relying on `label`, and the closed well draws the name beside the chip.

**[F11] A construction error inside a `UI.When` `thenView` is quarantined, so the
surface just never appears.** I typed `role = "caption"` on a `UI.Text` (legal set:
`secondary | content`). No throw, no test failure — the palette silently did not
mount while every `dump()`-based case still passed, because the dump reads the
control's own state, not the tree. `core:lastError()` was the only witness. The
playbook's step 2.1 says to assert `core:lastError()` stays nil on MOUNT; it does not
say to re-assert it after opening a structural branch, which is the only place it
could ever go wrong. I added that assertion and left the story in the test.

**[F11b]** The refusal message itself is malformed:
`UI.Text.role expects string, got string — one of secondary | content`.

## 5. The registrations the playbook does not list

Beyond the scaffold's seven files and api.md, a twentieth control needs **six more
edits**, every one of them discovered by a red test rather than by reading:

| Edit | Discovered by |
|---|---|
| `docs/guide/README.md` capability-catalog row | 4 red doc-gate tests **[F3]** |
| `tests/controls_namespace.spec.luau` `NAMES` allowlist | 1 red test **[F4]** |
| `examples/gallery/scenarios/init.luau` `ORDER` | overflow_sweep RULE 4 |
| `tests/overflow_sweep.spec.luau` `SCENARIOS` | overflow_sweep RULE 4 |
| `examples/gallery/client/demo_picker.luau` `DEMOS` + `DEMO_ROOT` pin | 3 red tests |
| `tests/gallery_demo_picker.spec.luau` two pinned counts (36→37, 29→30) | 2 red tests |

**[F12] `new-control.md` §6.1 says "Add it to an instrumented gallery fixture" in
nine words.** That one instruction is six files, two hard-pinned integers and one
pinned root-name map, enforced by four different specs in three different files. The
repo's own standing rule (quoted inside `overflow_sweep.spec`) is *"registered in
`scenarios/init.luau` ORDER and `demo_picker.DEMOS`, swept by
`tests/overflow_sweep.spec.luau` at all viewports, and verified across every shipped
theme"* — that sentence is exactly what §6.1 should say and does not.

**[F13] THE HEADLINE: the playbook forbids the one edit a twentieth control
requires.** `new-control.md` §0: *"**Never** edit `tools/lune/gate_manifest.luau` or
`phases.json` for a control; the existing gate checks pick your work up through the
suite and the registration checker."* But `gate_manifest.luau:4039`, the
`naming-adr-implemented` check of the `release-candidate-review` gate, contains:

```
test "$(grep -c "^  Controls[.]" artifacts/release-candidate-review/public-surface.txt)" = "19"
```

Measured, both ways: `lune run tools/lune/_probe_public_surface | grep -c "^  Controls[.]"`
returns **19** with my work stashed and **20** with it restored, and the committed
evidence file `artifacts/release-candidate-review/public-surface.txt` also has 19. So
adding any control turns that check from PASS to FAIL, and the playbook says I may not
touch the file that fixes it. The premise the prohibition rests on — "the existing gate
checks pick your work up" — is false for a hard-pinned count.

I followed the instruction literally and did NOT edit `gate_manifest.luau`. The fix is
one character (`= "19"` → `= "20"`); the *durable* fix is to derive the count from the
registry instead of pinning it, exactly as the sibling `since=0.10.0` count legitimately
stays 19 (a new control is born with no deprecation row).

Wryly: the same gate file carries a PENDING row named `new-control-path-proven` whose
evidence path is `artifacts/release-candidate-review/exercises/colorwell/README.md` —
this exercise is a planned repo activity, and the control's name was chosen in advance.

**[F14] `tools/doctor.sh` FAILS on a clean checkout, for a missing directory.**
It runs `rojo build examples/gallery.project.json -o build/Facet-Gallery.rbxl`, and
`build/` is gitignored and never created (`doctor.sh` does `mkdir -p artifacts` and
nothing else). `mkdir -p build` and the same command succeeds and doctor reports PASS.
Pre-existing and unrelated to my control, and not in the playbook's command list — so
reported, not fixed.

## 6. What the repository caught that I would have shipped

Two real defects in my own control, both found by always-on sweeps rather than by any
test I wrote. This is the strongest thing about this codebase.

1. **`overflow_sweep`**: the well's chip-plus-name row ran 30–35 px past a 320 px
   portrait at the Largest text preference under four theme packages. The name was
   measured on one line; giving it `width = fill` lets it take the remainder and wrap
   inside the `minMax`-floored row. I would never have found this by hand.
2. **`large_text_matrix`** (the fixture the scaffold stamped for me and told me to
   grow): a palette tile's caption truncated a German compound with no full-value
   path, at +0. Fixed with `disclose = true`.

**[F15] `tests/world_substrate.spec` red-lit my spec for hand-rolling a presenter,
and the playbook sent me to the exemplars that hand-roll one.** §2 says to follow
"the house style" in `tests/table.spec.luau` and `tests/virtualization.spec.luau`;
both build core/env/adapter/system/presenter by hand, so I copied that. The R12
ratchet then failed with *"79 spec files build a presenter by hand, up from 78 … the
next spec file that ADDS a builder migrates its file onto tests/lib/world.luau
instead."* The message is a perfect fix instruction — and `tests/lib/world.luau` is
mentioned nowhere in `new-control.md`. Migrating took five minutes and the spec is
better for it. The playbook should name the substrate instead of the two files that
predate it.

## 7. Live Studio: honestly PENDING

`docs/extending/new-control.md` §6 requires a live Roblox gate, and
`agent-execution-contract.md` §4 requires a preflight proving the running place holds
the source just built.

- The gallery place BUILDS with the new fixture in it:
  `rojo build examples/gallery.project.json` succeeds, and `tools/doctor.sh` reports
  PASS once `build/` exists.
- One Studio instance is connected (`Facet-Showcase.rbxl`), but
  `script_grep "color_well"` returns **no matches** — that session is a different
  checkout and does not contain this work. Preflight step 2 fails by definition, and
  the contract is explicit: *"If … the source is stale, mark `FAIL_ENVIRONMENT` … Do
  not infer a framework defect from a blind instrument."*
- I did not sync my scratch tree into somebody else's open Studio session.

So every §6 row is **PENDING_HUMAN / FAIL_ENVIRONMENT**, with the review packet ready:
select the demo `color-well` in the showcase picker, or set the workspace attribute
`Facet_Scenario = "color_well"` before Play. The fixture ships six named steps
(`reset`, `openKartPalette`, `closeKartPalette`, `stepKartNext`, `stepKartPrevious`,
`pickTeamOrchid`) and a `report` that returns both wells' dumps.

## 8. Final state

Committed on branch `colorwell-control` as `c7789dc`. 14 files: 3 new
(`src/controls/color_well.luau`, `tests/color_well.spec.luau`,
`examples/gallery/scenarios/color_well.luau`) and 11 edited.

Gate results, all run from the library root:

| Command | Result |
|---|---|
| `./run-tests.sh` | exit 0, **6837 passed** (6799 before → +38) |
| `tools/test.sh 6800` | `test: PASS passed=6837` |
| `lune run tools/lune/check_registration_cli` | PASS — 39 controls, 20 interactive prove four-input and the paradigm axis |
| `lune run tools/lune/check_prop_parity_cli` | PASS — 27 classes, 673 properties |
| `lune run tools/lune/gate phase-4-hardening` | byte-identical to the stashed baseline; **no check regressed** |
| `lune run tools/lune/check_docs_cli` | PASS |
| `python3 tools/check_doc_style.py` | PASS |
| `lune run tools/lune/check_theme_drift.luau` | exit 0 |
| `lune run tools/lune/check_boundary` | PASS |
| `python3 tools/check_source_size.py` | PASS |
| `stylua --check` (all 14 files) | clean |
| `tools/doctor.sh` | PASS once `build/` exists — see **[F14]** |
| `rojo build examples/gallery.project.json` | builds, 3.5 MB place |

Two things deliberately left red or undone, both named above:
`gate_manifest.luau`'s `= "19"` pin (**[F13]**, the playbook forbids the edit) and
every live Studio row (**§7**, the instrument holds a different checkout).

`check_call_shape_drift.py` and `check_brand_drift.py` report FAIL_ENVIRONMENT
because `games/RascalRally` does not exist in this isolated checkout. The root
`CLAUDE.md` requires consumer lockstep for any Facet contract change; this change is
purely ADDITIVE (one new namespace entry, no existing contract touched), so no
consumer edit would have been correct even with the game present.

## 9. What the docs got RIGHT, since a journal of friction is unbalanced without it

- `docs/extending/new-control.md` is ordered, has a pass condition per step, and its
  step 3 "three load-bearing facts" (one activation site, declare the touch floor,
  `pres.refresh()` before reading props) each saved a real defect.
- The scaffold works first try and registers seven files.
- `docs/reference/api.md` answered nearly every design question without reading
  source: tint forms, Button-as-container, Grid laning, the whole contribution
  bundle, `adjustAxis`'s "choose the axis your screen does not navigate on".
- Every failing check told me the exact fix in its own message. The doc gate named
  the catalog row to add; the R12 ratchet named the substrate to migrate onto; the
  overflow sweep gave pixel counts, theme names, and viewports.
- The always-on sweeps (`overflow_sweep`, `large_text_matrix`) caught two real
  defects in my control that no test I wrote would have.
