# Playbook-only dry run — Chip control (2026-07-21)

A fresh-context agent (zero prior repo knowledge, instructed to read ONLY
docs/extending/new-control.md and whatever it links) landed a new composite
control end to end: `src/controls/chip.luau` + `tests/chip.spec.luau` (12 real
cases: build/render, four device-true input classes, four per-class affordance
idioms, no-factory-rerun, dump determinism, registry neutrality), registry row
with `inputProofs` + `affordanceProofs` (`hotSwitch = false`), `newChip`
export, real api.md entry.

Result: suite 591 passed / 0 failed (stable across 6+ runs);
`check_registration_cli` PASS exit 0 (Chip is the 8th interactive control
proving four-input AND the paradigm axis); `lune run tools/lune/gate
phase-4-hardening` PASS exit 0 with no regressed check.

Verdict (the agent's own): the scaffold/checker/gate loop makes it nearly
impossible to forget an axis or a proof; the playbook succeeds because it
points at the house exemplars. Three load-bearing facts lived only in the
exemplar sources — single activation site (no inner `onActivate` beside
`handleActivate`), the 44 px floor being declared-not-solver-enforced, and
refresh-before-reading-rendered-props — all three folded into
docs/extending/new-control.md the same day (this artifact is the record).
