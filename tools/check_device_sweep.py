#!/usr/bin/env python3
"""check_device_sweep — the device-emulator visual sweep gate (task SWEEP,
framework-gaps-phase2-followups, director mandate part a).

WHAT THIS IS A GATE FOR. The director keeps finding overlap/cutoff/
stray-stroke/pop bugs in the Studio device emulator that headless tests miss.
`tools/studio/device_matrix.luau` (the reusable driver) + the `theme_authoring`
scenario (`examples/gallery/scenarios/theme_authoring.luau`) already carry the
live instrumentation: on-glass containment (declared box vs live engine rect),
`GetStyled` paint-claim resolution, and a settled-frame check. What did NOT
exist before this task is a machine-readable, regression-diffable VERDICT over
a whole matrix of device presets x theme packages x scenarios, captured once
and checked forever after — that is this file.

THIS GATE CANNOT RUN IN CI. It requires an open Roblox Studio session with the
place injected (studio_sync + inject) and a human or agent operator driving
`StudioDeviceSimulatorService` + the scenario runner through the Studio MCP
`execute_luau` tool — there is no headless engine that can stand in for Studio's
device emulator. This script is the CHECK half: it reads the JSON evidence the
operator persisted to `artifacts/device-emulator-sweep/rows/*.json` (one file
per cell, written after each live observation — see the row schema below) and
verdicts it against the matrix config (`tools/studio/device_sweep_matrix.json`)
and the stored baseline (`artifacts/device-emulator-sweep/baseline.json`).

TRIGGER DISCIPLINE (when a sweep run is required, not merely nice-to-have):
  - before any director device-pass/review of the showcase or a reference app;
  - any change touching `src/client/screen_scroll_indicators.luau`,
    `screen_presentation.luau`, `screen_target.luau`'s paint/containment path,
    `render/transitions.luau` (backdrop/pop), or any `examples/themes/*.luau`
    package;
  - before closing a campaign/phase that claims cross-platform or themed
    correctness;
  - whenever a device-owed register item is claimed "covered by sweep" — the
    row proving it must exist and pass here first.

ROW SCHEMA (`artifacts/device-emulator-sweep/rows/<cell>.json`):
  cell            "<deviceRow>__<theme>__<scenario>" (or a notable cell's own
                  id from the matrix config's `notableCells`)
  deviceRow, theme, scenario   the three matrix axes (theme may be null for a
                  scenario with no package concept, e.g. a pure device-only
                  notable cell)
  notable         null, or the matrix config's notableCells[].id this row
                  answers
  ok              bool — the cell's own verdict (containment clean, zero
                  zero-boxes, styled paint resolved, settled-frame agrees)
  evidenceClass   must be "studio-emulated"
  sourceStamp, studioVersion   identity (device_matrix's `identity` block)
  containment, zeroBoxes, offscreenNodes, unfitText   arrays, from
                  device_matrix's `observe`/`row` mode (empty = clean)
  solverDiagnostics   int, must be 0 for `ok: true`
  settledTwice    bool — two `observe()` calls back-to-back agreed (the
                  "first-paint watch" substitute: proves the settled frame
                  matches what a fresh re-solve produces, per the brief's
                  fallback clause)
  capture         "captures/<cell>.png" (capture_viewport.sh convention:
                  `<deviceRow>__<theme>__<scenario>.png`, or the notable
                  cell's own id)
  captureSha256_16   first 16 hex chars of the capture's sha256
  triage          null, or {"kind": "known-owed"|"sweep-defect"|
                  "real-regression"|"physical-owed", "ref": "...",
                  "detail": "..."} — required on every `ok: false` row
  notes           free text

Usage:
  python3 tools/check_device_sweep.py [--selftest] [--verbose]

--selftest runs WITHOUT any live evidence: it validates the matrix config's
own shape (device rows are real `matrix_rows` ids, themes/scenarios/notable
cells are well-formed) and the artifacts directory layout, which is the part
provable without Studio open — exactly the "the gate is wired" half a CI
context or a fresh reviewer can check. It intentionally does NOT touch
`rows/*.json` and cannot pass or fail on sweep evidence.

Default mode reads `rows/*.json`, requires full coverage of the base matrix
(every deviceRow x theme combination on `baseScenario`) plus every
`notableCells[].id`, and diffs each cell against `baseline.json`:
  - baseline ok, now red, no triage             -> REGRESSION (hard fail)
  - now red, triage present                     -> PENDING (listed, not fatal)
  - a config cell with no row file at all        -> MISSING (hard fail)
  - now green                                    -> PASS

Exit 0 = every cell is PASS or a triaged PENDING; 1 = at least one REGRESSION
or MISSING cell.
"""

import glob
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
CONFIG_PATH = os.path.join(HERE, "studio", "device_sweep_matrix.json")
MATRIX_ROWS_SRC = os.path.join(REPO, "src", "preview", "matrix_rows.luau")
ARTIFACT_DIR = os.path.join(REPO, "artifacts", "device-emulator-sweep")
ROWS_DIR = os.path.join(ARTIFACT_DIR, "rows")
CAPTURES_DIR = os.path.join(ARTIFACT_DIR, "captures")
BASELINE_PATH = os.path.join(ARTIFACT_DIR, "baseline.json")

TRIAGE_KINDS = {"known-owed", "sweep-defect", "real-regression", "physical-owed"}


def load_config():
    with open(CONFIG_PATH) as f:
        return json.load(f)


def live_matrix_row_ids():
    """The real device-row ids `src/preview/matrix_rows.luau` declares, parsed
    from its own `id = "..."` fields inside `matrix_rows.ROWS` — so this config
    cannot silently drift onto a row id the pure policy does not know."""
    src = open(MATRIX_ROWS_SRC).read()
    rows_block = src.split("matrix_rows.ROWS = {", 1)[1].split("matrix_rows.OPTIONAL", 1)[0]
    return set(re.findall(r'id\s*=\s*"([a-z0-9\-]+)"', rows_block))


def base_cells(cfg):
    out = []
    for row in cfg["deviceRows"]:
        for theme in cfg["themes"]:
            out.append(f"{row}__{theme}__{cfg['baseScenario']}")
    return out


def selftest(cfg, verbose):
    errors = []
    known_rows = live_matrix_row_ids()
    for row in cfg.get("deviceRows", []):
        if row not in known_rows:
            errors.append(f"deviceRows names '{row}', not a row in {MATRIX_ROWS_SRC}")
    if not cfg.get("themes"):
        errors.append("themes list is empty")
    if not cfg.get("baseScenario"):
        errors.append("baseScenario is not set")
    notable = cfg.get("notableCells", [])
    planned = cfg.get("plannedCells", [])
    if not notable and not planned:
        errors.append("notableCells/plannedCells are both empty — the brief names specific director cells beyond the matrix floor")
    seen_ids = set()
    for cell in notable + planned:
        for field in ("id", "deviceRow", "scenario", "director"):
            if not cell.get(field):
                errors.append(f"cell missing '{field}': {cell}")
        cid = cell.get("id")
        if cid in seen_ids:
            errors.append(f"duplicate cell id '{cid}' (across notableCells/plannedCells)")
        seen_ids.add(cid)
        if cell.get("deviceRow") not in known_rows:
            errors.append(f"cell '{cid}' names deviceRow '{cell.get('deviceRow')}', not a real matrix row")
    for cell in planned:
        if not cell.get("status"):
            errors.append(f"plannedCells entry '{cell.get('id')}' has no 'status' explaining why it is not required yet")
    for d in (ARTIFACT_DIR, ROWS_DIR, CAPTURES_DIR):
        if not os.path.isdir(d):
            errors.append(f"missing artifact directory {os.path.relpath(d, REPO)}")

    if errors:
        for e in errors:
            print(f"FAIL {e}")
        return 1
    print(
        f"selftest ok: {len(cfg['deviceRows'])} device rows x {len(cfg['themes'])} themes "
        f"({len(base_cells(cfg))} base cells) + {len(notable)} notable cells (required) + "
        f"{len(planned)} planned cells (not yet required), config wired to real matrix_rows ids, "
        f"artifact directories present"
    )
    return 0


def sha256_16(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()[:16]


def load_rows():
    out = {}
    for path in sorted(glob.glob(os.path.join(ROWS_DIR, "*.json"))):
        with open(path) as f:
            row = json.load(f)
        out[row.get("cell", os.path.basename(path)[:-5])] = row
    return out


def validate_row_shape(cell, row):
    errors = []
    if row.get("evidenceClass") != "studio-emulated":
        errors.append(f"{cell}: evidenceClass must be 'studio-emulated', got {row.get('evidenceClass')!r}")
    for field in ("containment", "zeroBoxes", "offscreenNodes", "unfitText"):
        if not isinstance(row.get(field), list):
            errors.append(f"{cell}: '{field}' must be a list (empty = clean), missing or wrong type")
    if row.get("ok") is False and not row.get("triage"):
        errors.append(f"{cell}: red cell with no triage — every red needs a kind/ref/detail")
    triage = row.get("triage")
    if triage is not None:
        if triage.get("kind") not in TRIAGE_KINDS:
            errors.append(f"{cell}: triage.kind {triage.get('kind')!r} not one of {sorted(TRIAGE_KINDS)}")
        if not triage.get("ref"):
            errors.append(f"{cell}: triage has no 'ref' (cross-reference to the device-owed register or ADR)")
    capture = row.get("capture")
    if capture:
        full = os.path.join(ARTIFACT_DIR, capture)
        if not os.path.isfile(full):
            errors.append(f"{cell}: capture '{capture}' does not exist on disk")
        elif row.get("captureSha256_16") and sha256_16(full) != row["captureSha256_16"]:
            errors.append(f"{cell}: capture sha256 does not match the recorded hash — the picture and its trace drifted")
    else:
        errors.append(f"{cell}: no capture recorded")
    return errors


def main():
    verbose = "--verbose" in sys.argv
    cfg = load_config()
    if "--selftest" in sys.argv:
        return selftest(cfg, verbose)

    required = set(base_cells(cfg)) | {c["id"] for c in cfg.get("notableCells", [])}
    rows = load_rows()
    baseline = {}
    if os.path.isfile(BASELINE_PATH):
        with open(BASELINE_PATH) as f:
            baseline = json.load(f).get("cells", {})

    errors = []
    grid = {"PASS": [], "PENDING": [], "MISSING": [], "REGRESSION": []}

    for cell in sorted(required):
        row = rows.get(cell)
        if row is None:
            grid["MISSING"].append(cell)
            errors.append(f"{cell}: no evidence file in {os.path.relpath(ROWS_DIR, REPO)}")
            continue
        errors.extend(validate_row_shape(cell, row))
        ok = row.get("ok") is True
        was_ok = baseline.get(cell, {}).get("ok")
        if ok:
            grid["PASS"].append(cell)
        elif row.get("triage"):
            grid["PENDING"].append(cell)
        elif was_ok is True:
            grid["REGRESSION"].append(cell)
            errors.append(f"{cell}: REGRESSION — baseline was green, now red with no triage")
        else:
            grid["REGRESSION"].append(cell)
            errors.append(f"{cell}: red with no triage and no baseline to compare against")

    # rows present but not in the required set are extra evidence, not an error
    extra = sorted(set(rows) - required)

    if verbose or errors:
        for kind in ("PASS", "PENDING", "MISSING", "REGRESSION"):
            if grid[kind]:
                print(f"{kind} ({len(grid[kind])}): {', '.join(grid[kind])}")
        if extra:
            print(f"EXTRA evidence beyond the required matrix ({len(extra)}): {', '.join(extra)}")

    if errors:
        for e in errors:
            print(f"FAIL {e}")
        return 1

    print(
        f"device sweep ok: {len(required)} cells required, "
        f"{len(grid['PASS'])} PASS, {len(grid['PENDING'])} PENDING (triaged), 0 MISSING, 0 REGRESSION"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
