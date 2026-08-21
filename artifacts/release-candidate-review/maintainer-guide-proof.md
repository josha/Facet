# The maintainer guide, and the check that keeps it true (RC-11)

Stage `release-candidate-review`, row `maintainer-map-current`. Evidence for
acceptance row RC-11 in `artifacts/release-candidate-review/acceptance.md`.

Date: 2026-08-21. Baseline commit `1f9510a`, framework suite **6821 passed** in a
private `git archive` export before any edit in this wave.

---

## 1. What was built

**`docs/MAINTAINERS.md`** — one page that answers "where does a change go, and
what proves it?" for every production area, in three tables and a maintenance
contract.

### Table 1 — the areas

Nineteen areas, each carrying a one-sentence responsibility, the public seam, and
the internal owner modules. Between them they claim **all 28 top-level entries
under `src/`** — twelve directories and sixteen root modules — and the drift check
reads that tree from disk to prove it, so an unmapped area is a failure and not an
oversight.

The areas are: core, blueprint, mount, layout, render, controls, present, input,
focus, motion, tokens, themes, env, async, replication, client, preview, shared
helpers, library root.

Three of them exist because the `src/` tree is wider than the architecture chapter
describes it: **motion** and **preview** are whole directories the chapter's module
map never lists, and **shared helpers** is the four extracted single-purpose modules
(`num`, `paths`, `rect`, `text_distance`) that the reuse consolidation left at the
root. All three were unmapped before this page.

### Table 2 — how each area is held true

Same nineteen areas, same order, enforced. Per area:

- **may depend on** — the allowed direction, naming the rule that enforces it where
  one exists. All four of `check_boundary`'s rules are cited by name:
  `src-module-requires-library-root`, `non-client-requires-client`,
  `engine-free-zone-requires-engine-vendor`, `consumer-requires-facet-internal`.
- **tests** — entry-point specs, 71 of them, each proved by the checker to require
  a module of the area it is filed under.
- **Studio scenario** — a registered scenario in `examples/gallery/scenarios/`, 18
  cited. One area (shared helpers) declares `none —` with its reason, which the
  checker accepts only in that exact form; an empty cell is a failure.
- **gate** — 51 `stage/row` citations, each resolved against
  `tools/lune/gate_manifest.luau`.
- **extend via** — the playbook, the scaffold command, or the constitution for an
  internal area. All seven shipped `docs/extending/` playbooks are linked.

### Table 3 — where does it belong?

Thirteen one-line answers, each ending in a link: a control, a primitive, a layout,
a modifier, an engine property, a render target, an input behavior, a device or
platform fact, a theme feature, an example, a Studio scenario, a test helper, and a
checker. Every one names the file it lands in and the playbook that walks it.

### Section 4 — how this file stays true

Three rules and one command. Derive, do not duplicate.

There is **no second API catalog** here.
Public names, properties, defaults and return values stay in
`docs/reference/api.md`, and the shipped capability list stays in the guide index;
the map links both and repeats neither. No number you would have to maintain: the
page carries no spec count, no control count, and not the size of the blessed
client list.

---

## 2. What was corrected on the way in

**`docs/guide/02-architecture.md` said ELEVEN blessed client modules and listed
eleven, omitting `client/host.luau`.** `check_boundary.luau`'s
`BLESSED_CLIENT_MODULES` holds twelve, and `docs/reference/api.md §Client entry
points` says twelve and documents `client.host` at length as *the* bootstrap to
start with. The guide had been stale since `host` was blessed.

That is precisely the failure the map's no-number rule exists to prevent: a
restated count is a second list, and the second list is the one that rots. The
chapter now names `client/host.luau` in its file list and stops restating the size,
pointing at the code that is already declared to be the authority.

---

## 3. The drift check

`tools/lune/check_maintainer_map.luau` (module) and
`tools/lune/check_maintainer_map_cli.luau` (command). Eleven obligations, printed
by `--list`:

1. every top-level entry under `src/` (read from disk) is claimed by exactly one
   area row;
2. every `src` path the map claims exists, and no two areas claim the same one;
3. the area table and the proof table name the same areas in the same order;
4. every backticked `src` module path anywhere in the map is a real file;
5. every spec a proof row names exists and requires a module of that row's area;
6. every Studio scenario named exists and is registered, or the cell says
   `none — <reason>`;
7. every gate stage and `stage/row` cited exists in the gate manifest;
8. every dependency rule cited by name is one `check_boundary` really reports;
9. every quick answer links the page carrying the rest of the answer;
10. every local link resolves, and an anchor lands on a heading that document has;
11. every page under `docs/extending/` is linked by the map.

**Coverage is derived, never listed.** A spec covers an area when one of its own
`require` calls names a module of that area — the require graph, one hop out of the
spec file. A spec that reaches the library only through `require("../src")` counts
under the library-root row, which is why the reactive-recovery and quarantine specs
are filed there rather than under core. The numbers are printed on demand and
written down nowhere:

```
covering specs per area (the require graph, one hop out of each spec file):
  core: 94 spec files          themes: 46 spec files
  blueprint: 84 spec files     env: 74 spec files
  mount: 64 spec files         async: 4 spec files
  layout: 42 spec files        replication: 2 spec files
  render: 59 spec files        client: 20 spec files
  controls: 55 spec files      preview: 2 spec files
  present: 33 spec files       shared helpers: 2 spec files
  input: 45 spec files         library root: 158 spec files
  focus: 7 spec files          motion: 12 spec files
  tokens: 46 spec files
```

### The live run

```
check_maintainer_map: PASS (19 areas covering 28 src entries, 71 named specs,
18 scenarios, 51 gate rows, 7 boundary rules, 47 local links, 7 playbooks linked)
```

---

## 4. Red first: the proof each rule bites

A check nobody has watched fail proves nothing about the tree it passes.

### 4.1 The command-line selftest — a scratch copy, one planted fault each

`--selftest` copies `docs/MAINTAINERS.md` into a scratch directory named with a
per-run stamp, plants one fault into each copy, and points the checker at that
copy. The scan is the same scan over the same live tree; only the map is a copy, so
a concurrent reader never sees a planted file and the working tree is never
written. This is the discipline `tools/check_input_authority.py` established.

```
check_maintainer_map: selftest (a copy of the map, one planted fault each)
  control: an unmutated copy passes
  a dropped area row: reported
  a broken link: reported
  a spec named under an area it does not cover: reported
  a gate row that does not exist: reported
  a boundary rule nothing enforces: reported
  a scenario that is not registered: reported
check_maintainer_map: SELFTEST PASS — every planted fault was reported
```

The headline case is the one the plan asks for. Deleting the `env` row from the
copy — the single line that claims `src/env/` — produces:

```
docs/MAINTAINERS.md: src/env is not claimed by any area row
      fix: add a row for it to the area table, or fold it into the row that owns it
```

The control matters as much as the plants: an unmutated copy passes, so the six
reds are the faults and not the copying.

### 4.2 The suite half — nineteen cases, nineteen faults

`tests/maintainer_map.spec.luau`, registered in `tests/run.luau`, runs the same
checker so drift fails the suite and not only a command someone remembered to type.
The suite plants **in memory** (`mapSource`) rather than on disk, because a test run
must write nothing.

```
maintainer map: every row still points at the tree it describes
  ✓ the live repository passes every obligation
  ✓ checks a real amount, so a gutted map cannot pass by describing nothing
  ✓ names every obligation it enforces (the command's --list output)
  ✓ reports a src area no row claims
  ✓ reports a claimed path that does not exist
  ✓ reports two src paths claimed by the same two areas
  ✓ reports the two tables falling out of step
  ✓ reports a spec filed under an area it does not require
  ✓ reports a spec file that has been renamed away
  ✓ reports a Studio scenario that is not a registered scenario
  ✓ reports an empty scenario cell that gives no reason
  ✓ reports a gate row the manifest does not have
  ✓ reports a gate stage the manifest does not have
  ✓ reports a boundary rule check_boundary does not enforce
  ✓ reports a link that resolves nowhere
  ✓ reports a link whose anchor is not a heading in the target
  ✓ reports a shipped extension playbook the map stops linking
  ✓ reports a missing marker rather than silently checking nothing
  ✓ derives a per-area covering count from the require graph

19 passed
```

Every plant asserts it changed the text first (`the mutation changed nothing, so it
proves nothing`), because a mutation that no longer matches its own pattern is a
case that passes while testing an unmodified file.

The count floors are the second half of the same argument: a gutted map cannot pass
by describing nothing, so the spec pins floors on areas, claimed `src` entries,
named specs, scenarios, gate rows, boundary rules, links and playbooks.

---

## 5. Writing style

`docs/MAINTAINERS.md` is inside `tools/check_doc_style.py`'s scope. That checker
scans two directories plus a named file list, and its own comment records why the
file list exists: the directory loop silently skips anything that is not a
directory, so a page outside `docs/guide` is scanned by nothing while looking
covered. The map is added to `SCANNED_FILES` beside `README.md`.

```
check_doc_style: SELFTEST PASS — an over-long numbered step, an unexpanded acronym
and a bare artifact row id were each reported; the restored tree is clean
check_doc_style: PASS — 23 documents; no over-long instruction step, no unexpanded
acronym, no internal shorthand
```

The document count moved from 22 to 23, which is the map.

---

## 6. What this row does not claim

It does not claim the prose is good. A checker cannot read a sentence. The
mechanical half of clarity is `check_doc_style`, and the fresh-reader judgement
stays owed as `RC-17`.

It does not claim every area has a Studio scenario that exercises it deeply. The
scenario column names the fixture a maintainer should open first; several areas are
reached through a scenario that exercises them alongside other work, and shared
helpers honestly declares that it has no live surface at all.

It does not re-derive the extension playbooks or the scaffold: those were rebuilt
and proved by `new-control-path-proven` and `seeded-defect-exercise`. This row
proves the map points at them, and that a new playbook cannot ship unlinked.

---

## 7. Files

| Path | What |
|---|---|
| `docs/MAINTAINERS.md` | The maintainer map |
| `tools/lune/check_maintainer_map.luau` | The drift check, `check(opts)` |
| `tools/lune/check_maintainer_map_cli.luau` | The command: default, `--list`, `--counts`, `--selftest` |
| `tests/maintainer_map.spec.luau` | The suite half, nineteen cases |
| `tests/run.luau` | Registration |
| `README.md` | Links the map from the front door |
| `docs/guide/02-architecture.md` | Links the map; the blessed-client-module correction |
| `tools/check_doc_style.py` | The map joins `SCANNED_FILES` |
| `tools/lune/gate_manifest.luau` | Row `maintainer-map-current`; `clear-writing-checked` note updated for the widened scope |
