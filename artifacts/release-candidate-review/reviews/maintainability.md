[MAINT-AUDIT]: CONCERNS

# Release-candidate maintainability review (fresh-context verifier, 2026-08-17)

Reviewed at commit `b230b87`, read-only on tracked files. Viewpoint: the NEXT
maintainer — a future change should have one obvious owner, one established API
shape, one extension path, one proof path.

Verdict is CONCERNS, not REJECT: the framework's *mechanisms* are unusually
strong (the boundary checker, the prop-parity checker, the registration checker,
the deprecation ledger, the fast-tier honesty machinery are all better than
typical). The concerns are that (a) the headroom those mechanisms were built to
protect has been spent, (b) the enforcement layer itself is now the least
maintainable artifact in the repository, and (c) the documented extension path
does not reach a green suite.

Overlap with the sibling architecture review (`reviews/architecture.md`) is
noted where it exists; findings here are the maintenance-cost half and are not
restatements unless flagged.

## Findings

MAINT-1 | Blocker | High | src/render/renderer.luau (199,650 chars); tools/check_source_size.py:394,397,424 | Five modules sit within 10 KB of the hard 200,000-char `Source`-write cap and the renderer is 350 chars from it; `KNOWN_OVER` is empty and `main()`'s only size branch is `>= CAP`, so there is no warning band and the first signal is the edit that makes the file unsyncable.
MAINT-1b | High | High | src/render/renderer.luau vs src/render/presentation_channel.luau | Post-split growth landed almost entirely back in the blocks the design record calls "too entangled": renderer +23,749 chars (98.5% of the margin the split bought) against +460 for its clean extracted sibling — the campaign bought time, not a structural change.
MAINT-1c | Medium | High | src/render/renderer.luau:1-21; src/present/presenter.luau:1-21; src/controls/table.luau:1-36; src/controls/virtual_list.luau:278-279 | No module header records its own size or headroom, and the "why this stays whole" reasoning for the largest blocks (e.g. `makeHandle`, 85,157 chars = 45% of presenter.luau) lives only in tools/check_source_size.py — disconnected from the code it governs and stale for six of seven files.
MAINT-1d | Low | Medium | src/client/screen_chrome.luau (115,049 chars) | The largest split sibling in the framework — 3x the next — predates the documented campaign and appears in no size narrative, so it is on the same zero-early-warning trajectory with no checkpoint to diff against.
MAINT-2 | High | High | tools/lune/gate_manifest.luau (757 KB, 4,053 lines); tools/lune/gate.luau:48-56 | One file holds 31 phases / 501 checks / 469 shell commands with 2,270 `grep -q` text pins (max command 8,048 chars), and a failing check reports an EMPTY detail — there is no failure localization at all.
MAINT-2b | Medium | High | tools/lune/gate_manifest.luau (484 `note` strings, 357,921 chars — 47% of the file; longest 9,527) | The project's real design reasoning lives inside gate-manifest note strings and frozen `artifacts/`, neither of which a maintainer reading `src/` can discover; 78 of 469 checks invoke no tool at all (pure `grep`/`test -f`, 377 `test -f` sites), so they assert that text exists on disk rather than that behaviour holds.
MAINT-3 | High | High | tools/lune/scaffold.luau:62; docs/extending/new-control.md:179,205 | The documented scaffold emits `textSize = 14`, which the repo's own `check_theme_drift` rejects — so the playbook's stated pass condition (`./run-tests.sh` exit 0) is unreachable from the scaffold's own output.
MAINT-4 | High | High | tests/theme_drift.spec.luau:34,51,67,73 | The theme-drift lint's own negative controls assert ABSOLUTE global counts (`#result.violations == 1`, `result.ok == true`), so one real violation anywhere in `src/` reddens four unrelated mutation cases with messages that name the wrong file.
MAINT-5 | High | High | docs/extending/new-engine-feature.md:53-82; src/client/screen_target.luau:124-137 | There is NO playbook for adding a new blueprint primitive class: `new-control.md:7` defers to `new-engine-feature.md`, which only describes the property/modifier path, and `CLASS_TO_INSTANCE` plus the per-class `create()` branch have no checker at all.
MAINT-6 | High | High | src/blueprint.luau:1506 | `STYLE_GROUP_KEYS` is a hand-maintained closed list of the style-modifier family that no test or checker reads; its own comment records that this exact list already silently dropped `stroke` in production.
MAINT-7 | High | High | docs/guide/07-input.md:382,447,470,521; docs/reference/api.md:2509,2626,3244,3537 vs tools/lune/check_boundary.luau:102-116,138-139,253 | The public guide and API reference teach consumers to require `client.gamepad_contention` / `client.responder_effects`, which the boundary checker refuses for every consumer outside `examples/` ("not yet a blessed entry point").
MAINT-8 | High | Medium | src/controls/table.luau (196,778 chars, 3,222 headroom) | The second-largest module in the framework has no seam analysis anywhere — it is absent from `tools/check_source_size.py`'s header, from `docs/handoff/`, and from its own header comment.
MAINT-8b | High | High | docs/extending/new-render-target.md:42-51 vs src/render/target_contract.luau:39-228 | The playbook transcribes the OPTIONAL method list by hand — 23 names against the contract's current 28 — and nothing cross-checks the doc against the table it copies, so the drift is already three days old at freeze.
MAINT-8c | High | High | docs/extending/new-theme.md:367-381 | Six independently hand-maintained theme-name lists exist (tests/theme_reference_packages.spec.luau:24-39 and :40-50, tools/lune/check_docs.luau:353-364, tools/lune/_probe_matrix.luau:7-13, tests/renderer.spec.luau:721-729, tests/gallery_theme_picker.spec.luau:19-25,132-142); nothing enumerates `examples/themes/*.luau` and cross-validates, and the playbook names one of the six.
MAINT-8d | High | High | docs/extending/skinned-control.md:270-278 vs tools/lune/check_docs.luau:59-60,377 | The playbook says `check_docs_cli` enforces a skinned control's art/provenance/manifest; the checker hardcodes `RUNG3_ASSET_DIR = "assets/themes/ornate-gauge"`, so a SECOND skinned control gets zero mechanical protection and the playbook never says to edit the checker.
MAINT-8e | High | High | docs/extending/new-platform-mode.md:137; src/preview/device_profiles.luau:45-125; tests/preview.spec.luau:24 | Adding a device profile requires editing `PROFILES` AND a separate `ORDER` array; `get()` reads `PROFILES` and `list()` reads `ORDER`, so a profile missing from `ORDER` works but is invisible, and the only guard is a pinned `expect(#names).toBe(7)` that stays silent when `PROFILES` alone grows. `bench/perf_profiles.luau:88-112` repeats the pair.
MAINT-8f | Medium | High | docs/extending/new-theme.md:229-231; src/themes/package.luau:351,1906-2014 | The playbook declares the recipe-field vocabulary closed, but `chrome.focus` is a second shipping recipe grammar (`kind ∈ {ring, glow}`, `color`/`blurRadius`/`zIndex`/`transparency`) used live in `examples/themes/fantasy_parchment.luau:439-448` and never mentioned in the doc's 469 lines.
MAINT-8g | Medium | Medium | docs/extending/new-platform-mode.md:156-157; docs/extending/new-engine-feature.md:8-12 | Playbooks cite gates that do not cover the steps they are cited for: `check_registration_cli` touches neither `environment.luau` facts nor either profile registry, and no gate reads `style_lint.luau` rule content, `bench/perf_scenes.luau`, or `docs/guide/05-styling.md`; `new-platform-mode.md:156` also names a "conformance matrix" that exists nowhere in `docs/`.
MAINT-9 | Medium | High | src/ (415 mentions across 88 files) | 80 of 124 opaque cross-reference tags used in source comments (`O-20`, `C-06`, `F-28`, `ARCH-6`, `B-BTN3`, `NS-A12`, …) resolve in neither `requirements.json` nor `docs/` — only in the 326 MB frozen `artifacts/` tree or git history.
MAINT-10 | Medium | High | tests/ (43 of 232 spec files; 111 read sites, 113 assertions) | Nearly a fifth of the suite reads framework SOURCE as text and asserts on its wording or formatting, so any refactor — including the splits MAINT-1 forces — reddens tests indistinguishably from real regressions.
MAINT-11 | Medium | High | src/core/imperative.luau:1-9; src/core/fusion_adapter.luau:1-18 | Two Phase-0 bake-off baseline cores still ship inside `src/` (mounted wholesale into `ReplicatedStorage.Facet` by every project file), and `fusion_adapter` requires `../../vendor/Fusion/...`, a path no built place contains — it cannot load anywhere but Lune.
MAINT-12 | Medium | High | docs/INVENTORY.md:7,8,16; phases.json:3,80 | The document that says "read before building" and the machine-readable phase registry both cite `docs/superpowers/specs/2026-07-19-luauui-crossplatform-ui-design.md` and `prompt.md` as the product/architecture source of truth; neither path exists in this repository.
MAINT-13 | Medium | High | src/render/presentation.luau:2; src/render/presentation_channel.luau:2; src/client/screen_presentation.luau:2 | Three modules in three layers each open by declaring themselves "the presentation channel", so "fix the presentation bug" has no obvious owner.
MAINT-14 | Medium | High | src/controls/table.luau:1855; src/controls/virtual_list.luau:1894-1898 | The row-actions axis-lock resolution is implemented twice, in mirror-image form, in the two host dispatchers — sharing only the constant, so the predicate can diverge silently.
MAINT-15 | Medium | High | tools/lune/check_prop_parity.luau:331,436,449,492 | The parity checker's adapter and documentation views are plain substring searches over whole files (`string.find(docsSection, prop, 1, true)`), so a short prop name is "documented" if its letters appear anywhere in the section's prose and a `--[[TODO]]` adapter branch counts as wired.
MAINT-16 | Medium | High | tools/lune/gate_manifest.luau:3446; tests/lib/tiers.luau:57 | The gate checks that `tools/lune/check_tier_costs.luau` EXISTS (`test -f`) and never runs it, so the drift it was written to catch is already present (tier table recorded at "213 spec files"; 232 on disk).
MAINT-17 | Medium | Medium | tests/lib/testkit.luau:14-15,127-154; tests/profile_scopes.spec.luau:176-202 | The test framework has no `beforeEach`/`afterEach` of any kind, so isolation is pure author discipline; one case mutates process-global `src/core/profile.luau` state outside a `pcall`, and an early failure there leaks instrumentation into every later spec.
MAINT-18 | Medium | Medium | src/core/imperative.luau:16; src/render/renderer.luau:1010,1889; src/render/style_lint.luau:16; src/core/custom.luau:25; src/blueprint.luau:1080 | Six hard behavioural limits (`COMMIT_ROUND_CAP`, `RECYCLE_POOL_CAP`, `SOLVE_FEEDBACK_ROUND_CAP`, `SHADOW_BUDGET`, `FEEDBACK_ROUND_CAP`, `CIRCLE_MAX_CHARS`) appear in no documentation, and four of them in no test.
MAINT-19 | Medium | Medium | ui_todo.md:3-13 (79 citations across src/tools/tests/docs) | The four-input review bar that `check_registration` mechanically enforces is defined in a file whose own header calls it "the informal product-direction list".
MAINT-20 | Medium | Medium | tools/prior_gates.sh:44-52 | The prior-gates sweep's lock is `mkdir`-based, deliberately never auto-cleared, and refuses on stderr only — a killed sweep silently blocks every later one until a human runs `rmdir`.
MAINT-21 | Low | High | tests/instance_hosts.spec.luau:203-212 | A real wall-clock threshold (`os.clock()` around 20,000 iterations, `expect(elapsed).toBeLessThan(2.0)`) sits in the default correctness suite and the fast tier, not in a perf tier.
MAINT-22 | Low | High | tools/lune/check_boundary.luau:133-142 | `EXAMPLE_INTERNAL_REACH`'s six entries carry reasons but no removal trigger; two say "not yet a blessed entry point", which is a promise with no date and no owner.
MAINT-23 | Low | High | tools/check_brand_drift.py:51-112; tools/lune/theme_sync_cli.luau:85-90; src/init.luau:58-71 | Every rename-compat entry has a written removal rule, but no mechanism checks whether the stated condition has fired; two ADR-0011 deprecations are already past their `removeNoEarlierThan` floor at `VERSION = "0.9.0"`.
MAINT-24 | Low | High | src/init.luau:2,3 | The public entry point's header contains double-encoded UTF-8 (`Â§5`, `â client`) — the only such file in `src/`.
MAINT-25 | Low | High | tests/perf_lab.spec.luau:23 | The test suite requires `../examples/performance/lab/dataset`, so `tests/` cannot be run or distributed without the 41 MB `examples/` tree (proved: the suite aborts with a resolution error when `examples/` is absent).
MAINT-26 | Low | Medium | docs/plans/ (53 files); tools/lune/gate_manifest.luau (5 checks pin `docs/plans/`, 225 pin `artifacts/`) | Completed mission plans are never archived and gate checks pin their prose by content, so the doc tree cannot be pruned without reddening the gate.
MAINT-27 | Low | Medium | src/row_capability.luau; src/virtual_extents.luau; src/spec_guard.luau | Three control/authoring-domain helpers sit at the root of `src/` beside `init.luau`/`mount.luau`/`blueprint.luau`, outside the otherwise-total folder taxonomy, so their owning layer is not readable from the path.
MAINT-28 | Low | Medium | tools/ (54 verification entry points; 11 `check_*.py` with zero doc references) | There is no index of how to prove a change: 17 shell scripts, 19 Python checkers and 14 Lune checkers exist, and `docs/extending/new-control.md:204-208` names only four of them.
MAINT-29 | Low | Medium | tests/large_text_matrix.spec.luau:150-164 | A new control registered by the scaffold immediately fails `LT8-COVER` (no large-text fixture, no declared reason), and no extension playbook mentions large-text fixtures at all.
MAINT-30 | Low | Low | tests/fixtures/interact_fixtures.luau:1-11 | The interact-command fixture registry is permanently empty by design ("the interact command fails while empty"), with no date, owner, or tracking reference — `tools/interact.sh` has never worked.
MAINT-31 | Low | High | tools/lune/_probe_label.luau; _probe_new2.luau; _probe_text.luau; _probe_vlist_release.luau | Thirteen one-shot `_probe_*.luau` scratch files sit beside the real toolchain; four are referenced by nothing outside `artifacts/`, and two (`_probe_label`, `_probe_text`) open with executable code rather than a header saying what they were for.

## Details

### MAINT-1 — the source-cap ratchet has been fully consumed (Blocker)

`tools/check_source_size.py` is one of the best-documented artifacts in the
repository: its 300-line header records a 2026-08-14/15 campaign that split
seven modules down, names the seam taken in each case, names the blocks judged
too entangled, and states the doctrine explicitly —

> "AND STOP AT A REAL MARGIN, not at 199,9xx. Landing this file at 198,960 was
> enough to pass and not enough to survive… A ceiling reached by a hair is a
> file that crosses again on its next honest comment."

Measured at `b230b87`, against the sizes that header records as the campaign's
result:

| module | after the split | now | headroom |
|---|---|---|---|
| `src/render/renderer.luau` | 175,901 | **199,650** | **350** |
| `src/controls/table.luau` | (never analysed) | 196,778 | 3,222 |
| `src/controls/row_actions.luau` | 183,738 | 192,979 | 7,021 |
| `src/present/presenter.luau` | 179,055 | 190,326 | 9,674 |
| `src/client/screen_target.luau` | 167,749 | 186,471 | 13,529 |
| `src/layout/solver.luau` | 169,436 | 179,850 | 20,150 |
| `src/controls/virtual_list.luau` | 172,552 | 179,338 | 20,662 |

`presenter.luau` reached 199,481 on 2026-08-16 (`git rev-list --before`) — 519
chars — before coming back down. `renderer.luau` is at 350 chars today.

`KNOWN_OVER` is empty (`tools/check_source_size.py:397`), which the check
reports as the good news ("Nothing is waived"). The consequence is the finding:
with the ceilings gone there is no per-file budget left, and `main()`'s only
size branch is `elif size >= CAP` (`:424`). There is no warn band. The first
signal a maintainer gets is the commit that makes the file unsyncable — and the
remedy the header prescribes (find a seam by the mutable-upvalue test, prove it
with a live Studio A/B) is a multi-hour mission, not an edit.

This is the Blocker because it converts every ordinary maintenance act on the
five densest files in the framework into a hazard. The header itself says the
files were *deliberately* left with the comments that carry their device-round
reasoning; adding one such comment to `renderer.luau` now costs a split.

**Where the regrowth went (MAINT-1b).** The splits themselves are *architecturally
clean*: all 23 extracted siblings across the six split hosts were checked for
requires pointing back at their parent, and there are **zero** circular requires
— every extraction is genuinely one-way, as each commit claimed. What did not
hold is where new work landed. Measured against each file's own recorded
post-split checkpoint:

| module | delta since split | share of the margin consumed |
|---|---|---|
| `renderer.luau` | +23,749 | 98.5 % |
| `screen_target.luau` | +18,722 | 58 % |
| `presenter.luau` | +11,271 | 54 % |
| `solver.luau` | +10,414 | 34 % |
| `virtual_list.luau` | +6,786 | 25 % |

In the same window `presentation_channel.luau` — the clean seam the renderer
split created — grew **+460**. Essentially all post-split feature work went back
into the god-closures the design record calls "too entangled". So the campaign
bought time rather than changing the shape, which is the argument for a warn
band over another one-off split.

**The reasoning is not where the code is (MAINT-1c).** None of the seven
headers records the file's current size or headroom. `presenter.luau`'s
`makeHandle` (`:1528-3331`) is 85,157 chars — 45 % of the whole file — with no
comment at `:1500-1530` explaining why it resists splitting; that argument exists
only at `tools/check_source_size.py:90-96`. `virtual_list.luau:278-279` requires
`virtual_reorder` and `virtual_window` with no comment at all, where
`renderer.luau` and `screen_target.luau` both explain theirs. Two headers do
carry a stay-whole reason — `row_actions.luau:12-48` (the `buildEngine`
~60-shared-upvalue argument) and `screen_target.luau:371-429` (the five named
siblings) — but both are dated to the 2026-08-14 split and describe the crisis at
the *old* size, not the current 7,021 / 13,529 margin.

**One untracked sibling (MAINT-1d).** `src/client/screen_chrome.luau` is 115,049
chars — the largest of all 23 extracted siblings, about 3× the next
(`screen_paint.luau`, 53,055). It predates the documented campaign, appears in
no size narrative, and has no historical checkpoint to measure growth against.

Smallest fix direction: give `check_source_size.py` a WARN band (fail at
`>= CAP`, warn loudly at `>= 190,000`) and have it print current-size-vs-cap for
every `src/` file rather than only `KNOWN_OVER` rows, so the number is
discoverable without reading a 472-line docstring; then re-populate `KNOWN_OVER`
as a per-file *budget* — which is what its own closing paragraph asks for
("Re-snapshot them once the wave lands: a ceiling set mid-churn that nobody
revisits becomes a licence to grow"). Then take the seams the header already
named: the flow-wrap branch in `solver.luau` (~6 k), the keyboard/gamepad
plumbing in `virtual_list.luau` (~23 k), the focus-visual pair in
`screen_target.luau` (~19 k). `renderer.luau` needs one before its next comment;
the smallest candidates not already ruled "too entangled" are `structuralSync`
(`:2583-2789`, 10,135 chars) and the pointer/autoscroll/controller-API tail
(`:3618-4226`, ~24.9 k).

### MAINT-2 — the gate manifest is a single un-diagnosable 757 KB file (High)

`tools/lune/gate_manifest.luau` is 757,626 bytes / 4,053 lines and holds every
gate for all 31 phases in one Luau table: 501 checks, 469 `run` shell commands.
Measured over the parsed `run` strings:

- 2,270 `grep -q` text pins total
- 225 commands pin `artifacts/` (frozen mission evidence)
- 72 pin `src/` source text
- 23 use NEGATIVE pins (`! grep -q "preferredInput" src/controls/tab_view.luau`
  — the check fails when a string *appears*, so an unrelated comment breaks it)
- 52 `cd` into the Rascal Rally game repo
- longest single command: 8,048 chars (`gate_manifest.luau:3841`, check
  `d5-tabview`, ~70 chained pins spanning two repositories)

The diagnosability problem is in `tools/lune/gate.luau:48-56`:

```lua
local result = process.exec("bash", { "-c", `cd "$(pwd)" && {check.run}` })
state = if result.ok then "PASS" else "FAIL_RECOVERABLE"
detail = string.gsub((result.stdout or "") .. (result.stderr or ""), "%s+$", "")
```

`grep -q` prints nothing. Verified directly: a failing pin exits 1 with empty
stdout and stderr. So a broken `&&` chain of 70 pins produces
`FAIL_RECOVERABLE d5-tabview` with `detail = ""` in `gate.json`, and the
maintainer must bisect an 8 KB shell command by hand to learn which of 70
assertions moved. The header of the file is scrupulous about the *anchoring* of
these greps (FORM A vs FORM B, the `✓.*` rule) — the gap is that nothing makes a
failure legible.

Two further shape problems in the same file (**MAINT-2b**):

- **78 of the 469 `run` commands invoke no tool at all** — they are pure
  `grep`/`test -f` over files (377 `test -f` sites in total). Those checks assert
  that text exists on disk, not that behaviour holds. The clearest instance is
  `gate_manifest.luau:3446`, which does `test -f tools/lune/check_tier_costs.luau`
  — it verifies a *checker's file exists* and never runs it (see MAINT-16).
- **The project's real design reasoning lives in this file's `note` strings.**
  484 notes totalling 357,921 chars — 47 % of the file — the longest 9,527 chars
  (`gate_manifest.luau:3448`, an essay on the owed-ledger's history, two
  withdrawn closures, and a mutation that over-proved with 659 false reds). That
  is genuinely valuable institutional memory, and it is unreachable from the
  code it explains: a maintainer in `src/render/renderer.luau` has no path to it.
  It is the same problem as MAINT-9 with a different hiding place.

Smallest fix direction: change `run` from a string to a list of `{ label, cmd }`
pairs (or split on `&&` in `gate.luau`) and report the first failing label in
`detail`. That is a mechanical change to the runner plus a schema widening, and
it needs no manifest rewrite to start paying off. Separately, the `note` corpus
deserves extraction into `docs/` where it can be read by someone who is not
already inside the gate.

### MAINT-3 / MAINT-4 / MAINT-29 — the documented extension path does not reach green

Run in a scratch copy of the tree (`/tmp`, tracked files untouched):

```
lune run tools/lune/scaffold_cli control audit_probe
./run-tests.sh          ->  16 failed, 6182 passed
lune run tools/lune/check_registration_cli  ->  PASS
```

The scaffold works: it stamps the control, the spec, and all four registration
edits, and `check_registration` passes on the result. Ten of the sixteen
failures are the deliberately-red TODO cases the playbook describes.

The other six are collateral the playbook never mentions:

1. `LT8-COVER every controls_registry row is swept or carries a declared reason`
   (`tests/large_text_matrix.spec.luau:150`) — the scaffold adds a registry row
   but no large-text fixture and no declared reason. Neither
   `docs/extending/new-control.md` nor any sibling playbook contains the strings
   "large-text", "LT8", or "fixture" in this sense. **(MAINT-29)**

2. `the framework surface is clean` — `check_theme_drift` rejects the scaffold's
   own template line, `tools/lune/scaffold.luau:62`:
   `UI.Text({ id = "Todo", text = "%DISPLAY%: unimplemented", textSize = 14 })`.
   The framework's scaffold emits code the framework's lint forbids. **(MAINT-3)**

3-6. Four *unrelated* cases in `tests/theme_drift.spec.luau` then fail —
   `catches a hardcoded dimension in a control` (`:34`, "expected 2 to be 1"),
   `catches a hardcoded text size, gap, padding and named metric constant`
   (`:51`, "expected textSize to be gap"), `zero is not a metric` (`:67`), and
   `a comment describing a literal is not a violation` (`:73`). These are the
   lint's own mutation tests, and they assert ABSOLUTE totals over the whole
   scanned surface rather than a delta:

```lua
local result = drift.check({ injectFile = "src/controls/chip.luau", injectLine = ... })
expect(result.ok).toBe(false)
expect(#result.violations).toBe(1)          -- global count, not a delta
```

   So any real violation anywhere in `src/` makes four "does the lint bite?"
   cases fail with messages naming files the maintainer never touched. **(MAINT-4)**

`docs/extending/new-control.md:205` states the bar as
`./run-tests.sh # must exit 0: suite green, count grew`, and `:179` as "Loop
`./run-tests.sh` until green". Following the playbook literally, that loop
cannot terminate until the author also deletes the scaffold's own `textSize`
and discovers the undocumented large-text requirement.

Smallest fix direction: (a) change `scaffold.luau:62` to a theme role
(`textStyle = "body"` or equivalent) or add the scaffold path to
`check_theme_drift`'s ALLOWLIST; (b) make `theme_drift.spec`'s negative controls
filter `result.violations` to `injectFile`, or compare against a baseline run;
(c) add the large-text fixture step to `new-control.md` §5.

### MAINT-5 / MAINT-6 / MAINT-15 — registry surface for the three common changes

Enumerated against the code, not the playbooks:

| change | files that must change | mechanically cross-checked | text-matched only | unchecked |
|---|---|---|---|---|
| new prop on an existing primitive | 6 | 3 | 2 | 0 |
| new primitive class | 8 (+ spec registration, + conditional solver work) | 5 | 3 | 4 |
| new style modifier | 8-10 | 3 | 2 | 4 |

The prop path is in good shape: `blueprint_schema` → `render/authority` →
`renderer.BINDING_PROPS/STYLE_PROPS` agreement is verified by *calling* the real
modules (`tools/lune/check_prop_parity.luau:302,306,426,440,528`), and
`STYLE_PROP_ORDER` completeness is a hard `assert()` at module load
(`src/render/renderer.luau:164-173`) — the strongest guard in the repository and
the template the weaker ones should move toward.

The gaps:

- **No playbook exists for a new primitive class. (MAINT-5)**
  `docs/extending/new-control.md:7-8` explicitly routes "a control that needs a
  NEW engine instance class" to `new-engine-feature.md`. That document's six
  steps (`:53-82`) are written entirely in the vocabulary of adding a *property
  or modifier to an existing class* — its worked example is the UIShadow /
  per-corner UICorner adoption. Not one step mentions `class(...)` registration
  in `blueprint_schema.luau`, the `blueprint.<Name>(spec)` constructor,
  `CLASS_TO_INSTANCE` (`src/client/screen_target.luau:124-137`), the per-class
  `create()` branch, `src/controls/contract.luau`, or
  `tests/conformance/controls_registry.luau`. An author following it would pass
  `check_prop_parity_cli` and ship a primitive with no focus/accessibility
  contract, no conformance row, and — if it needs a non-`Frame` instance —
  silently wrong engine behaviour that renders as a generic Frame. Nothing
  checks `CLASS_TO_INSTANCE`, the `create()` branches, or
  `TAPPABLE`/`INPUT_SINKING`/`HOVERABLE`/`NO_DECORATION_CLASSES`
  (`renderer.luau:63,264,273,277`) for completeness.

- **`STYLE_GROUP_KEYS` is unguarded and has already drifted once. (MAINT-6)**
  `src/blueprint.luau:1506` is a hardcoded four-element list of the style-modifier
  family, read by nothing outside its own file (verified: no reference under
  `tools/lune/` or `tests/`). Its own comment at `:1498-1505` records the
  incident: "`stroke` — the fourth member of the style-modifier family — was
  silently dropped: an author reaching for the collection form of `UI.stroke`
  got no border on any element, with no error". The fix at the time was to
  validate against the list; the list itself is still hand-maintained.
  Smallest fix: derive it from `blueprint_schema`'s style-channel shared props.

- **Two parity views are substring searches. (MAINT-15)**
  `check_prop_parity.luau:436,449` do
  `string.find(adapterSource, 'prop == "<name>"', 1, true)` over the entire
  ~4,000-line adapter file including comments — proving the text exists, never
  that the branch does anything (`elseif prop == "blur" then --[[TODO]] end`
  satisfies it). `:331` and `:492` do `string.find(docsSection, prop, 1, true)`
  — a plain substring of the *prop name* against a multi-hundred-line prose
  section, so any prop whose name is a common word or a substring of another
  term reads as documented whether or not it is. Smallest fix: bound the adapter
  search to `adapter.setProp`'s byte range, and match the docs against a
  structured anchor (a table row or a `` `prop` `` backtick token) rather than a
  bare substring.

### MAINT-8b..8g — the five extension playbooks, verified against the code

All five playbooks in `docs/extending/` were read in full and every named path
and command checked. The good news first: **only one stale path exists in
1,449 lines of playbook** (`new-theme.md:68` says `render/authority.luau` where
every sibling reference correctly says `src/render/authority.luau`), every
named command exists and spells correctly, and the three safe checkers
(`check_docs_cli`, `check_registration_cli`, `check_prop_parity_cli`) all pass
clean. `new-engine-feature.md` matches its worked example step for step.

The failure mode is not stale paths. It is that **each playbook's steps produce
N parallel registries, and the gates each playbook cites verify only the subset
tied to the one worked example already in the repo.**

- **`new-render-target.md:42-51` (MAINT-8b).** The OPTIONAL contract is
  transcribed BY HAND into prose — 23 names. `target_contract.OPTIONAL`
  (`src/render/target_contract.luau:39-228`) has 28. Missing:
  `setSecondaryActivate` (`:116`), `setActivationFeedback` (`:160`),
  `setPreferredTransparency` (`:198`), `stageHost` (`:210`), `foreignHost`
  (`:223`). `git log -1` dates the doc to 2026-08-13 (`a42ef97`); the five
  methods landed 2026-08-14..08-16. The only automated cross-check,
  `tests/render_target_contract.spec.luau:123-158`, verifies `screen_target` against the
  contract — never the doc. The doc's own cautionary "SEAM-20" incident list
  (`:58-61`) then omits `setActivationFeedback`, reproducing in miniature the
  bug it warns about. Smallest fix: delete the hand-list and point at
  `target_contract.OPTIONAL`, which the doc already calls "the authority" one
  paragraph earlier.

- **Six unsynced theme lists (MAINT-8c).** `tests/theme_reference_packages.spec.luau`
  carries `MODULES` (`:24-39`, 9 entries) and a *separate parallel* `ORDER`
  (`:40-50`) with nothing asserting they match;
  `tools/lune/check_docs.luau:353-364` has `EXAMPLE_PACKAGES` (10);
  `tools/lune/_probe_matrix.luau:7-13` has 6; `tests/renderer.spec.luau:721-729`
  has 8; `tests/gallery_theme_picker.spec.luau` has two more (`:19-25`,
  `:132-142`). Nothing globs `examples/themes/*.luau` and validates against
  them. `new-theme.md:367-381`'s "Required tests" table names one of the six.

- **The skinned-control checker is hardcoded to the demo (MAINT-8d).**
  `skinned-control.md:270-278` says `check_docs_cli` "enforces that art,
  provenance and manifest exist and agree". `tools/lune/check_docs.luau:59-60`
  is `local RUNG3_ASSET_DIR = "assets/themes/ornate-gauge"`, and its asset list
  (`:377`) is literal paths under that one directory. A second skinned control
  is unprotected, and the playbook never says the checker must be edited. (The
  same file also mis-states at `:110-113` that `custom_control.luau`'s
  hand-rolled check has become a thin call into the contribution gate;
  `examples/themes/custom_control.luau:68-124` is still 57 hand-rolled lines and
  its own comment at `:26-27` still says the migration is future tense.)

- **`PROFILES` / `ORDER` (MAINT-8e).** `src/preview/device_profiles.luau` has
  `PROFILES` (`:45-119`) read by `get()` and a separate `ORDER` (`:121`) read by
  `list()`. A profile added to one and not the other is fully functional and
  invisible to every `list()` consumer. The only guard,
  `tests/preview.spec.luau:24`, is `expect(#names).toBe(7)` — a pinned count
  over `ORDER`, which stays silent exactly when `PROFILES` alone grows.
  `bench/perf_profiles.luau:88-112` repeats the pair; its `fromDevice()`
  (`:69-85`) asserts a referenced device class exists but nothing asserts the
  reverse. `new-platform-mode.md:137` names the file, not the pair.

- **A closed vocabulary that is not closed (MAINT-8f).** `new-theme.md:229-231`
  presents the recipe-field set as exhaustive. `chrome.focus` is a second,
  differently-shaped recipe grammar — `kind ∈ {ring, glow}` with `color`,
  `blurRadius`, `zIndex`, `transparency` — reserved at
  `src/themes/package.luau:351`, validated at `:1906-2014`, and used live in
  `examples/themes/fantasy_parchment.luau:439-448`. It appears nowhere in the
  doc's 469 lines.

- **Gates cited for steps they do not cover (MAINT-8g).**
  `new-platform-mode.md:157` cites the registration gate; `check_registration`
  touches neither `environment.luau`'s facts nor either profile registry.
  `new-engine-feature.md` covers `style_lint.luau`, `bench/perf_scenes.luau`
  and `docs/guide/05-styling.md` in its steps; grepping both checker scripts for
  those names returns zero hits, so an author can skip the lint, budget and
  guide steps and every named gate still exits 0. `new-platform-mode.md:156`
  ("add the platform/capability profile to the conformance matrix") is the one
  instruction in that doc naming no file, and the phrase appears nowhere else in
  `docs/`. Smallest fix for all three: state in each playbook which steps are
  gate-covered and which are eye-verified only — the honesty the rest of this
  repository shows everywhere else.

Positive controls worth recording: `new-theme.md:96`'s 17-slot vocabulary
matches `src/tokens/chrome_slots.luau:198-242` exactly; both real targets
implement 34/34 of the contract and `billboard_target.luau` nils exactly four
optional methods with inline justification per ADR-0009; the skinned-control
`fallback` requirement plus `checkCoverage` means only 2 of 8 example packages
declare `gauge:*` roles and the rest degrade silently — a real mitigation of the
"N themes must all be updated" trap.

### MAINT-7 — a documented seam the boundary checker refuses

`tools/lune/check_boundary.luau` rule (c) is a good mechanism: it resolves
`require(ReplicatedStorage.Facet.<...>)` — including through hoisted root
variables (`:183-215`) — and fails any consumer reaching past the blessed
client entry points. `BLESSED_CLIENT_MODULES` (`:102-116`) has nine entries.

`gamepad_contention` and `responder_effects` are not among them. They appear
instead in `EXAMPLE_INTERNAL_REACH` (`:138-139`) with the reasons
"the gallery demonstrates the legacy-control disable seam documented in
docs/guide/07-input.md; not yet a blessed entry point" and "the gallery binds
the responder-effects seam the guide teaches; not yet a blessed entry point".
The exemption is scoped to `examples/` only (`:253`:
`local exempt = string.sub(filePath, 1, 9) == "examples/" and ...`).

But the seam is taught to consumers in the shipped documentation, with the
literal require line:

- `docs/guide/07-input.md:382` — `require(ReplicatedStorage.Facet.client.responder_effects)`
- `docs/guide/07-input.md:447,470,521` — `require(ReplicatedStorage.Facet.client.gamepad_contention)`
- `docs/reference/api.md:2509,2626,3244,3537` — the three `gamepad_contention`
  probes and the `responder_effects` seam described as API

A game that follows the guide fails the boundary check with
`consumer-requires-facet-internal`. This is the "documented seam is incomplete"
class exactly: the doc and the enforcement disagree about what is public.
Smallest fix: bless both modules (they are already documented as API), or move
the guide sections behind an explicit "internal, not covered by the compat
promise" banner and give the guide a public alternative.

Concurs with, and extends, ARCH-8/ARCH-9 (`spec_guard` documented-but-unexported)
and ARCH-21 (`api.md` citing `src/input/contribution.luau` for the bundle's
field list). Three instances of the same class in one release candidate.

### MAINT-8 — the one large module with no seam story

`tools/check_source_size.py`'s header analyses `row_actions`, `screen_target`,
`presenter`, `solver`, `renderer` and `virtual_list` — naming, for each, the
seam taken and the blocks judged too entangled. `src/controls/table.luau` is
mentioned **zero** times (`grep -c 'table\.luau'` → 0), it appears nowhere under
`docs/handoff/`, and its own 36-line header discusses Phase A/B scope and native
scroll but never its size. It is the second-largest module in the framework, it
grew 6,538 chars in the two days before the freeze, and it has 3,222 chars of
headroom.

Its header does carry the right lesson about itself, which is worth quoting
because it is the pattern MAINT-9 generalises:

> "This header said 'Phase B' for both of them long after they landed, the
> implementation comment 1800 lines below said otherwise, and the stale half
> reached a mission brief as fact"

Smallest fix direction: run the same mechanised mutable-upvalue test the header
prescribes over `table_control.build` and record the result — even a "no seam is
worth taking yet, here is why" paragraph closes the finding, because the absence
of the analysis is what makes the next maintainer's decision unowned.

### MAINT-9 — 80 unresolvable cross-references in source comments

Scanned `src/**/*.luau` for the repository's cross-reference tag grammar
(`O-nn`, `C-nn`, `F-nn`, `M-n`, `ARCH-n`, `B-XXXn`, `NS-Xn`, `A-XXn`, `LT-n`,
`RR-n`, `DP-n`, `PKT-n`, `ENF-n`, `PG-n`, `SW-n`, `PLN-n`, `Dn.n`,
`UI-XXX-nnn`): **124 distinct tags, 415 mentions, 88 files.**

Resolvability:

- 15 resolve in `requirements.json` (the `UI-*` family — good)
- 29 resolve somewhere in `docs/`
- **80 resolve in neither**

Spot-checked: `O-20` (0 docs hits, 3 artifacts), `C-06` (0 docs, 2 artifacts),
`F-28` (0 docs, **104** artifacts), `ARCH-6` (0 docs, 5 artifacts), `B-BTN3`
(0 docs, 108 artifacts). So a maintainer reading `renderer.luau`'s
"owed row O-20" or `table.luau`'s "ledger C-06" must search a 326 MB frozen
evidence tree, and for the common tags the search returns a hundred files.

This is the "safe local change requires repository history to understand" class
in its purest form, and it is load-bearing: these tags appear inside the
comments that explain *why the code is shaped the way it is*, which is exactly
what a maintainer needs before touching it.

Smallest fix direction: one `docs/reference/tag-index.md` mapping each live tag
prefix to its defining artifact path — a generated file, not hand-written, since
the tags are already greppable.

### MAINT-10 — source pins are a systemic refactoring tax

Measured across `tests/`: **111** `fs.readFile`/`io.open` sites reading `src/` or
`tools/` as text in **43 of 232 spec files (18.5 %)**, carrying **113**
`string.find(source, …)` / `string.match(source, …)` assertion lines.

Representative:

- `tests/tier.spec.luau:106` pins the exact bash literal
  `out="$(./run-tests.sh 2>&1)"` from `tools/test.sh` — any requoting breaks it.
- `tests/scroll_indicators.spec.luau:310` pins
  `local SCROLL_BAR_THICKNESS = 8` including its formatting.
- `tests/container_relative_frame.spec.luau:465-472` asserts on the *wording of
  a comment* (``THE FIVE WRITERS OF `ctx.scopeKey` ``) as a proxy for an
  invariant the same file already checks structurally 13 lines above.
- `tests/stack_distribution.spec.luau:1161-1162` — the case
  `check_source_size.py`'s header already records as the hazard a split hits.

Many of these are legitimate: some invariants ("there is exactly one write site")
have no behavioural witness, and the comments say so. The maintenance cost is
the *scale*: any refactor across `src/` — including the splits MAINT-1 now
forces — reddens several of these, and each one needs manual triage to tell
"real regression" from "harmless text drift". There is no shared helper for the
idiom either: `tests/native_style_scenario.spec.luau:340-342`,
`tests/theme_icons_applied.spec.luau:48-50` and
`tests/paint_extensions.spec.luau:65` each reimplement the same
"extract the region between two needles" function locally.

Smallest fix direction: move the idiom into `tests/lib/` with a single helper
that reports "text pin drifted" distinctly from an assertion failure, so triage
is a message and not an investigation.

### MAINT-11 — two dead cores ship into every place

`src/core/imperative.luau:2` — "candidate C of the Phase 0 bake-off".
`src/core/fusion_adapter.luau:2` — "candidate B of the Phase 0 bake-off".
Production uses neither: `src/init.luau:145` binds `newCore = customCore.new`.
Their only live consumers are `tests/conformance/cli.luau:21-22` and three gate
rows (`gate_manifest.luau:1074,1890-1893`).

Every Rojo project mounts `src/` wholesale
(`games/RascalRally/code/default.project.json:14-15`,
`examples/showcase.project.json:67`), so both modules ship to every client.
`fusion_adapter.luau:14-18` requires `../../vendor/Fusion/State/Value` and
four siblings — a path outside `src/`, which no project file mounts. The module
therefore cannot load in any built place; it works only under Lune, where the
relative path resolves on disk.

The maintenance cost is not the 17 KB: it is that the core contract now has
three implementations that must agree forever, two of which exist only to keep a
Phase-0 rubric reproducible. `gate_manifest.luau:1076` already records that the
imperative scorecard's total is nondeterministic and the gate has to assert a
named check instead of a total.

Smallest fix direction: move both to `tests/lib/cores/` (they are test fixtures)
or add an explicit "why these ship" paragraph and a removal trigger. Either way
`fusion_adapter`'s vendor require should be noted as Lune-only, since today it
is a landmine for anyone who tries it in Studio.

### MAINT-12 — the declared source of truth is not in the repository

`docs/INVENTORY.md:1` — "Read before building". Its first row, `:7`, names
`docs/superpowers/specs/2026-07-19-luauui-crossplatform-ui-design.md` as
"Product/architecture source of truth". `phases.json:3` names the same path as
`"source"`. Neither `docs/superpowers/` nor `prompt.md` (`INVENTORY.md:8,16`;
`phases.json:80`) exists in this repository — the spec lives three levels up, at
the studio-repo root (`/docs/superpowers/specs/…`), outside the library folder
that is about to become a public distribution.

Eleven of the 55 paths `INVENTORY.md` cites do not resolve from the Facet root.

Smallest fix direction: either vendor the design spec under `docs/` (it is the
thing the phases index cites) or replace the citation with the in-repo authority
that superseded it — `docs/reference/constitution.md` and
`docs/plans/facet-consolidated-roadmap.md` are both plausible and both already
exist.

### MAINT-13 / MAINT-14 / MAINT-27 — ownership that the path does not reveal

**Three "presentation channels" (MAINT-13).** `src/render/presentation.luau:2`
("the PRESENTATION CHANNEL'S ARITHMETIC"), `src/render/presentation_channel.luau:2`
("THE PER-NODE PRESENTATION CHANNEL"), `src/client/screen_presentation.luau:2`
("THE PRESENTATION CHANNEL … of the ScreenTarget adapter"). Three real layers —
pure arithmetic, the renderer's per-surface factory, the engine adapter's writes
— but a maintainer handed "the fade is wrong" reads three headers that each
claim the name. A fourth namespace, `src/present/`, sits beside them.
Smallest fix: rename to say the layer (`presentation_math`,
`presentation_channel`, `screen_presentation_writes`) and make each header open
with what it is NOT.

**Two axis-lock resolvers (MAINT-14).** `src/controls/table.luau:1855` and
`src/controls/virtual_list.luau:1894-1898` both decide whether a row gesture
became a horizontal swipe, from the same origin and the same constant
(`row_actions_state.AXIS_LOCK_PX`), written in mirror-image form (`>= r^2 and
abs(dx) > abs(dy)` vs `< r^2 → return; abs(dx) <= abs(dy) → declined`). The
`table.luau` comment at `:1804-1813` argues this is not a second copy of the
*decision* — true of the `row_actions_state` instance, not of the predicate.
Two written forms of one rule, in two 190 KB files, is where a tie-breaking
change silently applies to one list type. Smallest fix: one exported
`row_actions_state.resolveAxis(dx, dy)` both call.

**Root-level `src/` modules (MAINT-27).** `src/row_capability.luau`,
`src/virtual_extents.luau` and `src/spec_guard.luau` sit at the root beside
`init.luau`/`mount.luau`/`blueprint.luau`, while every other module is
foldered by layer. All three are shared helpers (table + virtual_list; all
controls), which is a real reason — but the path does not say so, and
`src/controls/shared/` would. Related: ARCH-11 already flags
`src/controls/contract.luau` being a registry of *primitives*.

### MAINT-16 / MAINT-17 / MAINT-21 — proof-path hygiene

**The tier-cost detector is unwired (MAINT-16).** The fast-tier machinery is
otherwise exemplary: `tests/lib/tiers.luau:63-129` records `spec`/`ms`/`why` per
exclusion, `tests/tier.spec.luau:64-70` mechanically refuses a lazy `why`
(`#entry.why > 30`) or an unmeasured `ms`, membership is derived from
`run.luau` rather than hand-listed twice, and `tools/test.sh` refuses a fast-tier
transcript outright. The gap is that `tools/lune/check_tier_costs.luau` —
written specifically to catch recorded costs drifting from reality, citing a
real incident (`overflow_sweep.spec` recorded at 1,036 ms, measured at
16,342 ms) — is never executed. Its only appearance in the gate is inside the
2.4 KB `&&` chain of the `owed-ledger-honest` check
(`gate_manifest.luau:3446`), as `test -f tools/lune/check_tier_costs.luau`: the
gate checks that the checker's *file exists*, in a check about something else
entirely. The manifest's own note at `:3448` says so out loud ("wired into
no gate row yet, which its own artifact says out loud"). The drift the checker
exists to catch is already present: `tests/lib/tiers.luau:57` records the
measurement as taken "at 5561 cases / 213 spec files"; `find tests -name
'*.spec.luau'` returns 232.

**No test-isolation primitive (MAINT-17).** `tests/lib/testkit.luau:14-15,127-154`
provides `describe`/`it`/`expect` and a bare `pcall` runner — no `beforeEach`,
no `afterEach`, no teardown hook. All 232 specs run in one Lune process, so
`require`-cached module state is shared for the suite's lifetime. Isolation is
entirely author discipline, and it is nearly universal: every case that touches
`src/core/profile.luau`'s process-global counters wraps the body in a
pcall-based recorder — except `tests/profile_scopes.spec.luau:176-202`, which
calls `setEnabled(true)`/`setHooks(...)` and restores them only after several
unwrapped `expect()`s. An early failure there leaves the profiler enabled for
every later spec. A 13-file order-shuffle probe and 11 standalone-run probes
found no *current* divergence, so this is a latent hazard rather than an active
bug. Concurs with ARCH-23 (`text_metrics` process globals): the same test agent
found that only 7 of the 17 spec files requiring `text_metrics` call its
documented `resetMeasured()` seam.

**Wall-clock in the correctness suite (MAINT-21).** `tests/instance_hosts.spec.luau:203-212`
runs 20,000 iterations between `os.clock()` reads and asserts
`elapsed < 2.0`. It is registered at `tests/run.luau:138` and is *not* in the
fast-tier exclusion list, so it runs on every save and every gate. The author's
own comment concedes the coupling ("a machine slow enough to fail this is slow
enough to fail the suite"). It is the only real-time threshold on non-perf logic
in the suite.

### MAINT-18 / MAINT-19 / MAINT-20 — implicit limits and informal authority

**Six undocumented hard limits (MAINT-18).**

| constant | file:line | in docs/ | in tests/ |
|---|---|---|---|
| `COMMIT_ROUND_CAP = 20` | src/core/imperative.luau:16 | no | no |
| `SOLVE_FEEDBACK_ROUND_CAP = 8` | src/render/renderer.luau:1889 | no | no |
| `RECYCLE_POOL_CAP = 64` | src/render/renderer.luau:1010 | no | 1 file |
| `SHADOW_BUDGET = 100` | src/render/style_lint.luau:16 | no | no |
| `FEEDBACK_ROUND_CAP = 100` | src/core/custom.luau:25 | no | 1 file |
| `CIRCLE_MAX_CHARS = 3` | src/blueprint.luau:1080 | no | no |

Each of these decides an observable behaviour at a boundary (a commit loop that
gives up, a solve-feedback loop that stops, a pool that stops recycling, a lint
that starts complaining, a label that gets refused). None is stated in
`docs/reference/api.md`, and four have no test that pins the boundary — so a
maintainer changing one has no way to learn who depended on it. Smallest fix:
one "declared limits" table in `api.md`, plus a boundary case for the four
untested ones.

**Normative rules in an informal file (MAINT-19).** `ui_todo.md:1` calls itself
"director TODO / decision notes" and `:15-17` says "this file is the informal
product-direction list". Its §0 is nonetheless the four-input review bar that
`tools/lune/check_registration.luau` mechanically enforces, and it is cited 79
times across `src/`, `tools/`, `tests/` and `docs/` — including from
`docs/extending/new-control.md` as the standard a new control is held to.
Smallest fix: move §0 into `docs/reference/constitution.md` (which already owns
this kind of rule) and leave a pointer.

**A lock that must be cleared by hand (MAINT-20).** `tools/prior_gates.sh:44-52`
takes `/tmp/facet_prior_gates.lock` with `mkdir` and, by design, never clears a
stale one ("a stale lock from a killed sweep is cleared by hand (rmdir) —
deliberate, so a crash is investigated rather than papered over"). The refusal
goes to stderr and exits 2; the header itself records that this bit on
2026-08-15, when every run orphaned its own lock. The reasoning is defensible;
the maintenance cost is that a killed sweep silently blocks the next maintainer
on a machine-local file with no message in the artifact they read.

### MAINT-22 / MAINT-23 — compat windows with no machine trigger

The rename machinery is in good shape and is the model the rest should follow:
`tools/check_brand_drift.py` is a real guard (path + content + rebuilt-XML
`Name` properties, since a binary `.rbxl` LZ4s in chunks), it currently passes,
and its 22-entry `ALLOWLIST` (`:51-112`) requires a reason *and* a removal rule
per entry. `examples/` is completely clean of the old brand. ADR-0011's
deprecation ledger (`src/init.luau:44-142`) requires
`{surface, since, removeNoEarlierThan, replacement}` and
`check_prop_parity.luau:392` fails a malformed entry.

The residual gap in both systems is the same and is process, not mechanism:
**nothing checks whether a stated removal condition has fired.**

- `tools/lune/theme_sync_cli.luau:85-90` — `LEGACY_SCHEMA = "luauui-theme-sync/1"`
  accepted alongside the current one, removable "once no stored dump names it";
  nothing scans stored dumps.
- Five `tools/check_*.py` schema pins (`check_xp_matrix.py:37`,
  `check_device_captures.py:38`, `check_sf_rows.py:26`,
  `check_perf_captures.py:61-62`, `check_perf_gate_evidence.py:39-43,93`) are
  allowlisted "when those capture schemas are re-recorded under Facet" — while
  the same files describe those captures as immutable evidence, so the trigger
  may be unsatisfiable by construction.
- Several allowlist entries are gated on "Step 14", which has not run.
- `src/init.luau:58-64` and `:65-71` are already at their
  `removeNoEarlierThan = "0.9.0"` floor with `VERSION = "0.9.0"` (`:135`).
  Policy-compliant (a floor, not a mandate), but nothing tracks them as due.
- `tools/lune/check_boundary.luau:138-139` — two `EXAMPLE_INTERNAL_REACH`
  entries say "not yet a blessed entry point" with no date (**MAINT-22**; see
  also MAINT-7, which is the sharper half of the same gap).
- `EXCLUDED_TREES` (`check_brand_drift.py:40-44`) exempts `artifacts/`,
  `docs/superpowers/` and `.superpowers/` wholesale, so any new file dropped
  there is silently exempt forever.
- Leftover: `examples/places/LuauUI-Showcase.rbxl.lock` still carries the old
  name in a tracked path.

Smallest fix direction: a `--audit-triggers` mode on `check_brand_drift.py` that
reads each entry's `removal` string against a machine-readable milestone state
(`phases.json`, the version in `init.luau`) and reports the ones now due.

### MAINT-24 / 25 / 26 / 28 / 30 / 31 — smaller items, and the dead-code sweep

- **MAINT-24.** `src/init.luau:2-3` contains `c3 82 c2 a7` (double-encoded `§`)
  and `c3 a2 c2 80` sequences — "design Â§5", "â client entry points". Verified
  by hexdump; it is the only file in `src/` with this, and the public entry
  point is the file a new reader opens first.
- **MAINT-25.** `tests/perf_lab.spec.luau:23` requires
  `../examples/performance/lab/dataset`. Proved by running the suite against a
  tree with `examples/` removed: it aborts with
  `could not resolve child component "examples"` before any spec runs. The test
  tree is therefore not separable from the 41 MB examples tree, which matters
  for a distribution that will not ship `examples/places/` (39 MB of `.rbxl`).
- **MAINT-26.** `docs/plans/` holds 53 files, essentially all completed missions,
  with no archive convention. Five gate checks pin their prose by content (e.g.
  `grep -q "CLOSED 2026-08-16 (navigation-and-menus D5)" docs/plans/parity-completeness-audit-2026-08-13.md`
  inside `gate_manifest.luau:3841`), and 225 pin `artifacts/`, so neither tree
  can be pruned or reorganised without reddening the gate. The manifest's own
  allowlist entries call this the "Step 14 gate simplification", which has not
  run.
- **MAINT-28.** 54 verification entry points exist (17 `tools/*.sh`, 19
  `tools/check_*.py`, 14 `tools/lune/check_*.luau`, plus `run-tests.sh`), of
  which 11 Python checkers are referenced by no document at all
  (`check_device_captures`, `check_eq6_evidence`, `check_no_screen_key_bindings`,
  `check_perf_budgets`, `check_perf_metrics`, `check_perf_scenes`,
  `check_sf_rows`, `check_spike`, `check_verdicts`, `check_xp_matrix`, and
  `build_reference_places.sh`). `docs/extending/new-control.md:204-208` names
  four commands as "the" proof path. There is no index that says which of the 54
  a given kind of change owes.
- **MAINT-30.** `tests/fixtures/interact_fixtures.luau:1-11` is an intentionally
  empty registry whose header states "the interact command fails while empty" —
  so `tools/interact.sh` / `tools/lune/interact.luau` have never succeeded, with
  no date, owner, or tracking reference on the stub.
- **MAINT-31.** `tools/lune/` holds 13 `_probe_*.luau` files (plus
  `_theme_baseline.luau`) beside the 14 real checkers. Counting references
  outside `artifacts/`: `_probe_label`, `_probe_new2`, `_probe_text` and
  `_probe_vlist_release` have **zero**; `_probe_label` and `_probe_text` also
  open with executable code rather than a header, so nothing in the file says
  what it was for or when. The other nine are cited by frozen mission ids
  (`L-31`, `O-20`, `L-29`) — MAINT-9's class again. Smallest fix: move the
  orphans out of the toolchain directory, or give each a one-line header naming
  the mission and stating it is a one-shot.

**Not dead, checked and cleared.** A require-graph scan over `src/`, `tests/`,
`tools/`, `examples/` and `bench/` found no unreachable module in `src/`: the
seven that show no Lune-shaped require (`billboard_target`, `edit_preview`,
`motion_driver`, `responder_effects`, `roblox_env`, `roblox_input`,
`roblox_resources`) are all reached by consumers through Roblox instance paths
and are blessed entry points in `check_boundary.luau:102-116` (except the two in
MAINT-7). `billboard_target` in particular is documented
(`docs/reference/api.md:6883-6890`), blessed, and exercised by
`tests/stage.spec.luau` and `tests/foreign.spec.luau` — the ADR-0003 world-target
deferral did not leave an orphan behind.

## Notes on what is NOT a finding

Recorded so the next reviewer does not re-derive them:

- **The scaffold is registration-complete.** Run end to end, it stamps five
  files/edits and `check_registration_cli` passes on the result (33 controls, 98
  exports documented, 232 specs registered). The red-first spec is deliberate
  and documented. The defect is MAINT-3's collateral, not the mechanism.
- **`tests/fixtures/` and `tests/reference/` are clean.** Every fixture is
  `.luau` source with an explanatory header; there are no binary or JSON golden
  blobs, and the render/soak fixtures self-verify by running twice and diffing.
  No un-regenerable frozen fixture exists.
- **`themes/snapshot.luau`'s memo tables are correctly scoped** (weak-keyed per
  snapshot object, `:226,952,984-990`), and `sheet_model.luau`,
  `themes/package.luau` and `env/environment.luau` hold no module-level mutable
  state. The `core/*.luau` `counts`/`memos` tables that grep as globals are all
  per-instance factory closures.
- **The fast tier cannot be mistaken for the suite**: `tools/test.sh` greps for
  the `FACET-FAST-TIER` marker and refuses, and `tests/tier.spec.luau:100-107`
  pins that wiring.
- **PRNG determinism is sound**: `tests/lib/prng.luau` is a seeded xorshift32
  and `tests/lib/fuzz.luau` reports a replayable failing seed; no `math.random`
  or wall-clock seeding in the suite.
- **The `luau-*` selector-tag family is not rename debt.** `luau-slot-`,
  `luau-chrome-`, `luau-skinned-`, `luau-state-` (`src/tokens/chrome_slots.luau:59,75,84`)
  predate the rename by three weeks (ADR-0020) and name the *language*, not the
  old brand. ARCH-15/ARCH-16 cover the naming question; from a maintainability
  angle the only cost is that a future contributor may attempt a destructive
  mechanical cleanup, which one sentence in ADR-0036 would prevent.
- **Every module split is genuinely one-way.** All 23 siblings extracted from
  the six split hosts were checked for requires pointing back at their parent:
  **zero circular requires**, and `catchers.luau` / `text_reveal.luau` even
  carry an explicit "this never requires the presenter back" comment. The one
  pair with real coupling beyond a call API —
  `renderer.luau ↔ presentation_channel.luau` (22 references plus `handles` /
  `lastRects` shared by reference) — is documented as the split's stated price
  at `check_source_size.py:156-162`. This is the part of the architecture that
  is in the best shape, and it is why MAINT-1 is a headroom finding rather than
  an architecture one.
- **Both shipped render targets are complete against the contract** (34/34), and
  `billboard_target.luau` nils exactly four optional methods with inline
  justification per ADR-0009 — structurally drift-proof.
- **`STYLE_PROP_ORDER`'s load-time `assert()`** (`src/render/renderer.luau:164-173`)
  is the strongest completeness guard in the repository — it fires on every run
  that loads the renderer, not only under a CLI — and is the shape the
  substring-based checks in MAINT-15 should be moved toward.

## What I ran

Read-only on tracked files throughout. The only writes were to `/tmp`, to a
scratch copy of the tree, and to this file.

- `python3 tools/check_source_size.py` → PASS ("KNOWN_OVER is empty").
- `find src -name '*.luau' -exec wc -c` + `git show <rev>:<path> | wc -c` over
  `--before` revisions for 2026-08-15 and 2026-08-16, to measure regrowth
  against the sizes `check_source_size.py`'s header records (MAINT-1).
- Copied the tree to a scratch directory (`rsync -a --exclude .git --exclude
  artifacts --exclude build`, plus `examples/` minus `places/`) and ran there:
  - `lune run tools/lune/scaffold_cli control audit_probe` → 2 files written,
    4 registration edits applied.
  - `lune run tools/lune/check_registration_cli` → PASS.
  - `./run-tests.sh` → **16 failed, 6182 passed** (exit 1); 10 of the 16 are the
    scaffold's intended red cases, 6 are the collateral in MAINT-3/4/29.
  - `lune run tools/lune/scaffold_cli adapter audit_target` → stamps the 6
    `target_contract.REQUIRED` methods (of 6 REQUIRED + 28 OPTIONAL + a THEME
    list).
- `diff` of the scaffold's edits against `git show HEAD:` for `src/init.luau`
  and `tests/conformance/controls_registry.luau`.
- `./run-tests.sh` on the unmodified tree (via a parallel verifier) → **6188
  passed**, exit 0 — the baseline the scaffolded run's 6182/16 is measured
  against.
- Python scans over the tree: gate-manifest structure (31 phases, 501 `name=`,
  469 parsed `run` commands, 2,270 `grep -q`, 377 `test -f`, 78 tool-free
  checks, 484 notes totalling 357,921 chars, pin-target classification, command
  lengths); the opaque-tag census and its resolvability against
  `requirements.json` and `docs/`; a double-encoded-UTF-8 scan of every `.luau`
  and `.md`; `docs/INVENTORY.md` path existence (11 of 55 cited paths missing).
- Playbook verification: all five `docs/extending/*.md` read in full; every named
  path checked for existence; `lune run tools/lune/check_docs_cli`,
  `check_registration_cli` and `check_prop_parity_cli` run (all PASS); the
  OPTIONAL-method count diffed doc-vs-contract (23 vs 28) with
  `git log -1 -- docs/extending/new-render-target.md` (2026-08-13, `a42ef97`)
  dating the lag.
- Structural checks: block-size decomposition of the seven largest modules by
  `sed`+`wc`; a circular-require scan across all 23 extracted siblings (0 found);
  `git show <rev>:<path> | wc -c` deltas against each split's recorded
  checkpoint.
- Direct reads: `tools/check_source_size.py`, `tools/lune/gate.luau`,
  `tools/lune/gate_manifest.luau` (header + sampled checks),
  `tools/lune/check_boundary.luau`, `tools/lune/check_prop_parity.luau`,
  `tools/lune/scaffold.luau`, `tools/lune/check_example_drift.luau`,
  `tools/prior_gates.sh`, `tests/theme_drift.spec.luau`, `src/init.luau`,
  `src/controls/contract.luau`, `src/controls/table.luau` (header + `:1800-1815`),
  `src/controls/virtual_list.luau:1885-1900`, `src/core/imperative.luau`,
  `src/core/fusion_adapter.luau`, `src/render/target_contract.luau`,
  `docs/extending/new-control.md`, `docs/INVENTORY.md`, `phases.json`,
  `ui_todo.md`, `docs/reference/constitution.md` §16,
  `docs/plans/release-candidate-review.md`.
- Verified the empty-detail claim in MAINT-2 directly:
  `out=$(grep -q "definitely-not-here" src/init.luau 2>&1)` → `exit=1`,
  `stdout+stderr=[]`.
- Verified project mounts: `games/RascalRally/code/default.project.json:14-15`
  and `examples/showcase.project.json:67` both mount `src` wholesale; no project
  file mounts `vendor/`.
- A require-graph scan over `src/`, `tests/`, `tools/`, `examples/`, `bench/`
  and `docs/` for unreachable `src/` modules (7 candidates, all cleared as
  instance-path consumers), plus a reference census of the 13
  `tools/lune/_probe_*.luau` files excluding `artifacts/`.
- Did NOT run `tools/gate.sh` or `tools/perf.sh` (out of scope by instruction).
  `tools/suite_transcript.sh` was not needed — the scratch-copy suite run served
  the same purpose without touching the tracked cache.
