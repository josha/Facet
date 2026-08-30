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
  - now red, triage present, kind != real-regression, OR real-regression
    with an explicit waiver                     -> PENDING (listed, not fatal)
  - now red, triage.kind == "real-regression"    -> REAL-REGRESSION (always
    reported by name, never folded silently into PENDING — S2). Additionally
    a HARD FAIL when the baseline for this cell was green and no `triage.waiver`
    is recorded: a real regression against a green baseline is exactly the
    case the docstring's own promise names, and "the operator forgot to
    write a triage" must not be the only way to fail it (S2).
  - a config cell with no row file at all        -> MISSING (hard fail)
  - now green, evidence supports it              -> PASS
  - now green, but `solverDiagnostics` is unreadable because this row is
    `live`-sourced (no `FacetScenarioAPI.report()` diagnostics channel exists
    in showcase boot mode) -> DIAGNOSTICS-BLIND (listed, not fatal by itself,
    but never silently counted as a clean PASS — S3)
  - now green, but the row's OWN recorded evidence contradicts it (a non-empty
    `containment`/`zeroBoxes` array, a non-zero `solverDiagnostics`, or an
    `offscreenNodes`/`unfitText` entry with no derivable or explicit waiver)
    -> UNSOUND-PASS (HARD FAIL — `ok: true` is derived from the row's own
    evidence, never trusted verbatim; S1)

Exit 0 = every cell is PASS, DIAGNOSTICS-BLIND, or a triaged PENDING (incl. a
waived real-regression); 1 = at least one REGRESSION, REAL-REGRESSION (against
a green baseline, unwaived), UNSOUND-PASS, or MISSING cell.
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

# `tests/lib/device_views.luau:72`, `CORE_TOP = 58` — the showcase's own
# reserved demo/theme-chip strip height (`coreSafeInsets.top`). Hand-copied
# across the Luau/Python boundary the same way `LIVE_STYLED_PROPS` in
# `tools/studio/device_matrix.luau` hand-copies the runner's dump shape (S8 in
# `review-forksweep-theme2-findings.md` names that drift risk with no guard;
# this constant carries the same risk and the same disclosure). If the
# showcase's reserved strip height ever changes, this must change with it or
# the waiver below silently stops firing (never silently over-fires: a wrong
# value here can only make MORE offscreen entries require an explicit waiver,
# not fewer).
RESERVED_TOP_PX = 58


def _offscreen_waived(entry):
    """An `offscreenNodes` entry is waived when either:
      (a) it is EXACTLY the reserved negative-Y chrome band
          (docs/guide/11-device-verification.md 'Known gate limitations' #3;
          review finding S1/S4) — never a range, which would risk waiving a
          genuinely off-screen node that merely happens to sit near the band.
          `pos.x` must also be on-screen: the band exemption is about Y only; or
      (b) it carries its own explicit `"waived": "<reason>"` string — the
          per-entry escape hatch S1 asks for, for a case this function cannot
          derive purely from geometry (e.g. a node nested INSIDE the band's own
          box at a shallower Y, confirmed by a direct engine read rather than
          by the exact-Y shortcut — see `ps5-showcase-hud.json`'s three
          Strip-descendant entries).
    """
    if not isinstance(entry, dict):
        return False
    if isinstance(entry.get("waived"), str) and entry["waived"] != "":
        return True
    pos = entry.get("pos")
    if not isinstance(pos, dict):
        return False
    return pos.get("y") == -RESERVED_TOP_PX and isinstance(pos.get("x"), (int, float)) and pos.get("x") >= -1


def _unfit_waived(entry):
    """An `unfitText` entry is waived when either the row's own judge already
    recorded a DECLARED truncation policy (`declared ~= nil` —
    `device_matrix.luau`'s `judgeInstanceTrees`: disclose/reveal is the
    framework's legal overflow affordance, not a failure), or it carries its
    own explicit `"waived": "<reason>"` string. An entry with neither is an
    UNDECLARED truncation and fails an `ok: true` row (S1)."""
    if not isinstance(entry, dict):
        return False
    if isinstance(entry.get("waived"), str) and entry["waived"] != "":
        return True
    return entry.get("declared") is not None


def _explicit_waivers(row):
    """Per-entry OR whole-row explicit waivers a human/agent operator can
    still record for a class this checker cannot derive on its own — the
    schema field S1 proposes (`row["waivers"]`, a list of free-text reasons)
    or `triage.waiver` for the real-regression case (S2). Presence alone is
    what is checked; the reviewer reading `notes`/`triage.detail` is what
    judges whether the reason is honest, exactly like `triage.ref`/`.detail`
    already work for a red cell."""
    waivers = row.get("waivers")
    return bool(waivers)


def derive_pass_verdict(row):
    """For a row claiming `ok: true`, decide whether its OWN recorded
    evidence actually supports that (review finding S1) — an `ok` value is a
    claim, not a fact, until this function agrees with it.

    Returns (verdict, reasons) where verdict is one of:
      "PASS"              - evidence is clean (or every non-empty array entry
                             carries a derivable or explicit waiver).
      "DIAGNOSTICS-BLIND"  - clean otherwise, but `solverDiagnostics` cannot be
                             known because this row is `live`-sourced (S3) —
                             not a failure, but never conflated with a real
                             PASS either.
      "UNSOUND-PASS"       - the row's own evidence contradicts `ok: true` and
                             carries no waiver (S1) — a hard failure.
    """
    reasons = []
    live_sourced = "live" in (row.get("evidenceSource") or "")
    has_explicit_waiver = _explicit_waivers(row)

    if row.get("containment"):
        reasons.append(f"{len(row['containment'])} containment escape(s)")
    if row.get("zeroBoxes"):
        reasons.append(f"{len(row['zeroBoxes'])} zeroBoxes entr(y/ies)")

    sd = row.get("solverDiagnostics")
    diagnostics_blind = False
    if sd is None:
        if live_sourced:
            diagnostics_blind = True
        else:
            reasons.append("solverDiagnostics is absent (required 0 for ok:true)")
    elif sd != 0:
        reasons.append(f"solverDiagnostics={sd} (required 0 for ok:true)")

    unwaived_offscreen = [e for e in (row.get("offscreenNodes") or []) if not _offscreen_waived(e)]
    if unwaived_offscreen:
        reasons.append(f"{len(unwaived_offscreen)} unwaived offscreenNodes entr(y/ies)")
    # A `live`-sourced row has no `textPolicies` channel at all (device_matrix's
    # `observeLive` passes `nil` where `observe` passes `report.textPolicies`),
    # so `declared` can never be populated here — the SAME structural blindness
    # class `solverDiagnostics` has, just on a different array. Waiving the
    # whole array for a live row is honest, not lenient: the row's own
    # `judgeInstanceTrees` comment says exactly this ("informational only, not
    # gating") for every live-sourced cell, not a hand-picked few.
    if live_sourced:
        unwaived_unfit = []
    else:
        unwaived_unfit = [e for e in (row.get("unfitText") or []) if not _unfit_waived(e)]
    if unwaived_unfit:
        reasons.append(f"{len(unwaived_unfit)} unwaived unfitText entr(y/ies)")

    if reasons and has_explicit_waiver:
        # an explicit, named waiver on the row covers whatever this pass could
        # not derive on its own — still surfaced in --verbose via `reasons`,
        # never silently dropped.
        return ("PASS", reasons)
    if reasons:
        return ("UNSOUND-PASS", reasons)
    if diagnostics_blind:
        return ("DIAGNOSTICS-BLIND", ["solverDiagnostics unavailable: live-sourced row, no FacetScenarioAPI channel (S3)"])
    return ("PASS", reasons)


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
        # S9: `theme` is never checked here even though base-cell naming
        # depends on it (`f"{row}__{theme}__{scenario}"`). Presence, not
        # truthiness: the row schema documents `theme` as legitimately null
        # for "a scenario with no package concept, e.g. a pure device-only
        # notable cell", so an explicit `"theme": null` must not fail this —
        # only an ENTIRELY MISSING key (a plain typo/omission) should.
        if "theme" not in cell:
            errors.append(f"cell '{cell.get('id')}' has no 'theme' key at all (S9) — write `\"theme\": null` if this cell genuinely has no package concept")
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
            errors.append(f"{cell}: triage has no 'ref' (cross-reference to the device-owed register)")
        if row.get("ok") is True:
            # S5: `triage` exists to explain a RED cell (the schema comment:
            # "required on every `ok: false` row"). An `ok: true` row carrying
            # one is a live contradiction — either the defect it describes is
            # still open (the row should be `ok: false`) or it is stale (it
            # should be removed) — never both fields telling different
            # stories with no reader able to tell which is current.
            errors.append(
                f"{cell}: ok:true but carries a triage ({triage.get('kind')!r}) describing an open "
                f"defect — contradictory (S5); fix `ok` to match the triage or drop the stale triage"
            )
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
    grid = {
        "PASS": [],
        "DIAGNOSTICS-BLIND": [],
        "PENDING": [],
        "REAL-REGRESSION": [],
        "UNSOUND-PASS": [],
        "MISSING": [],
        "REGRESSION": [],
    }
    verdict_notes = {}  # cell -> reasons list, for --verbose

    for cell in sorted(required):
        row = rows.get(cell)
        if row is None:
            grid["MISSING"].append(cell)
            errors.append(f"{cell}: no evidence file in {os.path.relpath(ROWS_DIR, REPO)}")
            continue
        errors.extend(validate_row_shape(cell, row))
        ok = row.get("ok") is True
        was_ok = baseline.get(cell, {}).get("ok")
        triage = row.get("triage")
        kind = triage.get("kind") if triage else None

        if ok:
            # S1: an `ok: true` claim is verified against the row's OWN
            # recorded evidence before it is trusted, never taken verbatim.
            verdict, reasons = derive_pass_verdict(row)
            if reasons:
                verdict_notes[cell] = reasons
            if verdict == "PASS":
                grid["PASS"].append(cell)
            elif verdict == "DIAGNOSTICS-BLIND":
                grid["DIAGNOSTICS-BLIND"].append(cell)
            else:
                grid["UNSOUND-PASS"].append(cell)
                errors.append(f"{cell}: UNSOUND-PASS — claims ok:true but {'; '.join(reasons)}, no `waivers` recorded (S1)")
            continue

        # S2: a `real-regression` triage is ALWAYS reported by name — never
        # silently absorbed into the generic PENDING bucket the summary line
        # then reports as "0 REGRESSION" while real regressions sit inside it.
        if kind == "real-regression":
            grid["REAL-REGRESSION"].append(cell)
            if was_ok is True and not (triage or {}).get("waiver"):
                # the exact case the docstring's promise is about: baseline
                # was green, this is a real regression, and "downgrade by
                # writing any triage at all" is not an escape hatch.
                errors.append(
                    f"{cell}: REAL-REGRESSION against a GREEN baseline with no `triage.waiver` "
                    f"(S2) — a real-regression triage on a previously-passing cell is fatal "
                    f"unless the waiver is explicit and named"
                )
            else:
                grid["PENDING"].append(cell)
            continue

        if triage:
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
        for kind in ("PASS", "DIAGNOSTICS-BLIND", "PENDING", "REAL-REGRESSION", "UNSOUND-PASS", "MISSING", "REGRESSION"):
            if grid[kind]:
                print(f"{kind} ({len(grid[kind])}): {', '.join(grid[kind])}")
        if verbose and verdict_notes:
            for cell in sorted(verdict_notes):
                print(f"  note {cell}: {'; '.join(verdict_notes[cell])}")
        if extra:
            print(f"EXTRA evidence beyond the required matrix ({len(extra)}): {', '.join(extra)}")

    if errors:
        for e in errors:
            print(f"FAIL {e}")
        return 1

    print(
        f"device sweep ok: {len(required)} cells required, "
        f"{len(grid['PASS'])} PASS, {len(grid['DIAGNOSTICS-BLIND'])} DIAGNOSTICS-BLIND, "
        f"{len(grid['PENDING'])} PENDING (triaged), {len(grid['REAL-REGRESSION'])} REAL-REGRESSION, "
        f"0 UNSOUND-PASS, 0 MISSING, 0 REGRESSION"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
