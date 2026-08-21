# Task RC-11 — the maintainer map, and the check that keeps it true

Status: **DONE**. Acceptance row RC-11 moves PENDING to PASS_AUTOMATED.

Date 2026-08-21. Baseline `1f9510a` (framework **6821 passed** in a private export
before any edit). Commits `b5bad0868`, `d20bca81c`, `661a4451b`.

---

## Per-item outcomes

### 1. The area table, derived from the real tree — DONE

`docs/MAINTAINERS.md`. **Nineteen areas covering all 28 top-level entries under
`src/`** (twelve directories, sixteen root modules). Two tables share the area key:

- **Table 1** — area, the `src/` it owns, one-sentence responsibility, public seam,
  internal owner modules.
- **Table 2** — area, allowed dependency direction, covering specs, Studio
  scenario, gate row, extension path.

Splitting into two five-and-six-column tables rather than one nine-column table was
a readability call; the checker enforces that both name the same areas in the same
order, so they cannot drift apart.

Three areas existed in the tree and in no document: **motion** and **preview** are
whole directories the architecture chapter's module map never lists, and **shared
helpers** is the four extracted leaf modules (`num`, `paths`, `rect`,
`text_distance`) the reuse consolidation left at the root.

Sources walked, as instructed, rather than invented: `src/` itself,
`docs/INVENTORY.md`, `docs/guide/02-architecture.md`, `src/init.luau`,
`tools/lune/check_boundary.luau`, `tools/lune/gate_manifest.luau`,
`examples/gallery/scenarios/init.luau`, `docs/extending/`, `tools/lune/scaffold.luau`.

### 2. The dependency column cites the rule that enforces it — DONE

All four of `check_boundary`'s rule names appear and are checked to exist:
`src-module-requires-library-root`, `non-client-requires-client`,
`engine-free-zone-requires-engine-vendor`, `consumer-requires-facet-internal`.
A rule the map names but the checker does not report is a failure.

### 3. Tests derived by require-graph, and the method stated — DONE

The map states the rule in its own words: **a spec covers an area when one of its
own `require` calls names a module of that area** — the require graph, one hop out
of the spec file. A spec that reaches the library only through `require("../src")`
counts under the library-root row, which is why `reactive_recovery` and
`runtime_quarantine` are filed there and not under core.

71 entry-point specs are named, and each is verified to really require the area it
is filed under. The per-area totals are **not written down**: `--counts` prints them
from the same graph, so a new spec never makes the page stale.

### 4. Studio scenario, gate, extension path — DONE

18 registered scenarios cited, each checked to exist in
`examples/gallery/scenarios/` and to appear in the scenario order. 51 `stage/row`
gate citations, each resolved against the manifest. All seven `docs/extending/`
playbooks linked, plus the two scaffold commands (`scaffold_cli control`,
`scaffold_cli adapter`) and the constitution route for internal areas.

One area (shared helpers) honestly declares `none —` with a reason. The checker
accepts that exact form and rejects an empty cell, which is what stops "no scenario"
from being expressible as silence.

### 5. The "where does X belong" quick answers — DONE

Thirteen, each one line and each ending in a link: control, primitive, layout,
modifier, engine property, render target, input behavior, device or platform fact,
theme feature, example, Studio scenario, test helper, checker. That is the plan's
nine plus four the exercise of writing the map showed were missing.

### 6. "How this file stays true" — DONE

Three rules — derive don't duplicate, no second catalog, no number you would have to
maintain — plus the command. The map links `docs/reference/api.md` and the guide's
capability catalog and repeats neither, which is the "never create a second
hand-maintained API catalog" constraint honoured literally: the page contains no
property, default or return value.

### 7. The drift check, red first — DONE

`tools/lune/check_maintainer_map.luau` plus `check_maintainer_map_cli.luau`.
**Twelve obligations**, printed by `--list`. Every fact is read back from the place
it came from: the area list from the `src/` tree on disk, coverage from the require
graph, gate rows from the manifest, dependency rules from `check_boundary`'s own
reported strings, scenario names from the scenario index, seams from the exported
library table, links (anchors included) from the filesystem. It also refuses a
shipped playbook the map never links.

Red first, two ways:

- **`--selftest`** plants seven faults into a **copy of the map in a per-run scratch
  directory** and requires each to be reported, with an unmutated control beside
  them. Dropping the one line that claims `src/env/` yields `src/env is not claimed
  by any area row`. The scratch directory is keyed per run, because an unkeyed one
  is raced by a concurrent sweep.
- **`tests/maintainer_map.spec.luau`** (registered in `tests/run.luau`) plants twenty
  in memory, because a suite run must write nothing. Every plant asserts it changed
  the text first, so a mutation that stops matching its own pattern fails loudly
  instead of testing an unmodified file.

### 8. Gate row and acceptance row — DONE

New row `maintainer-map-current` in stage `release-candidate-review`: selftest, live
check, three pins on the evidence file, seven suite greps anchored to the pass
marker. Evidence
`artifacts/release-candidate-review/maintainer-guide-proof.md`.

The row was **extracted from the manifest and executed**, never retyped, inside a
private export: `ROW EXIT=0`.

`clear-writing-checked`'s note was amended because its scope really did widen —
`docs/MAINTAINERS.md` joined `check_doc_style.py`'s `SCANNED_FILES`.

RC-11 in `acceptance.md`: PENDING to **PASS_AUTOMATED**, with the driver cell naming
what closed it and pointing the playbook-and-scaffold half at RC-19 and RC-20.

---

## One real defect found and fixed

`docs/guide/02-architecture.md` said **ELEVEN** blessed client modules and listed
eleven, **omitting `client/host.luau`**. `check_boundary.luau`'s
`BLESSED_CLIENT_MODULES` holds twelve and `docs/reference/api.md §Client entry
points` says twelve and documents `client.host` at length as *the* bootstrap to
reach for first. The guide had been stale since `host` was blessed, and it is the
chapter a new maintainer reads before anything else.

That is exactly the failure the map's no-number rule exists to prevent. The chapter
now names the module and stops restating the size, pointing at the code that is
already declared to be the authority. The map, in turn, states no count at all.

---

## Suites

| Suite | Where | Result |
|---|---|---|
| Facet, argument-free | private `git archive 1f9510a` export, before any edit | **6821 passed**, exit 0 |
| Facet, argument-free | private `git archive 661a4451b` export | **6841 passed**, exit 0 |
| Rascal Rally, argument-free | private two-repo export, `fccf29d` beside Facet `d20bca8` | **3449 passed**, exit 0 |

**+20**, which is exactly the twenty cases the new spec registers. Nothing else
moved, and nothing else should have: this wave added one document, one checker, one
command, one spec and one gate row, and changed no library source.

Everything was measured in private `git archive` exports. The working tree carries a
second agent's uncommitted work (`src/init.luau`, `rokit.toml`, `tests/types/`,
`tools/check_types.py`, two probes), so an in-tree run would have measured theirs
and mine together — and the instruction was to never measure in-tree while that
review runs.

**Rascal Rally needed no edit and got none.** Nothing under `src/` moved; no public
contract, default, behavior, asset or distribution output changed. The consumer run
above is the compatibility evidence: the live game builds and passes, unchanged,
against this Facet commit.

---

## Checks

PASS: `check_maintainer_map_cli` + `--selftest`, `check_doc_style` + `--selftest`
(23 documents; the map is the 23rd), `check_gate_pins` + `--selftest` (242 pins),
`check_manifest_integrity` (1518 suite greps, all anchored), `check_boundary`,
`check_registration_cli` (256 specs registered), `check_docs_cli`,
`check_source_size`, `check_library_purity`, `check_input_authority`,
`stylua --check` on every touched file.

---

## CONTESTED, with evidence

**Three checks are red in this tree and none of them is this wave's.** Each was
reproduced red at the baseline commit before any edit here:

1. `check_comment_codes.py` — 6 orphan codes in `src/controls/virtual_grid.luau`,
   `src/controls/virtual_window.luau`, `src/core/custom.luau` (`RR-5`, `RR-12`).
   Reproduced on a clean `git archive 1f9510a` export with a fresh index. This wave
   touched no file under `src/`.
2. `check_brand_drift.py` — 11 matches, all in `tools/microprofiler_aggregate.py`,
   unmodified at the baseline commit.
3. `check_call_shape_drift.py` — 1 match in `tools/lune/_probe_t15_controls.luau`,
   unmodified at the baseline commit.

All three belong to the concurrently running performance wave. They are reported
rather than repaired: repairing another agent's in-flight file is how two agents
produce one broken commit.

---

## Two traps worth carrying forward

**A run string verified under `pipefail` measures your shell, not the row.** The
first attempt to execute `maintainer-map-current` wrapped it in
`set -euo pipefail` and got **exit 141** — `SIGPIPE`. `grep -q` exits the instant it
matches, the `echo` feeding it dies of a broken pipe, and `pipefail` promotes that
141 to the pipeline's status. `tools/lune/gate.luau` runs a check as
`bash -c 'cd "$(pwd)" || exit 1; <run>'` with no `pipefail`, which is why the same
idiom is green in dozens of rows. Run a row the way the runner runs it.

**`grep -qF` is line-based, and prose wraps.** The gate pin
`grep -qF "no second API catalog"` failed against an evidence file that contained
those exact words — split across two lines by the paragraph wrap.
`check_gate_pins.py` caught it immediately, which is the second time this session a
pin earned its keep.

---

## What is not claimed

The map's prose quality is not proved by any of this; a checker cannot read a
sentence. The mechanical half is `check_doc_style` and the fresh-reader judgement
stays with RC-17.

The playbook-and-scaffold half of the RC-11 row's wording was closed by RC-19 and
RC-20, not here. This wave proves the map points at them and that a new playbook
cannot ship unlinked.

No Studio session was run and none was needed: nothing in this wave changes a pixel.
