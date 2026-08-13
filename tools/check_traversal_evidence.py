#!/usr/bin/env python3
"""The `traversal-document-order` stage's Studio evidence, checked AGAINST THE
SCENARIO IT WAS RECORDED FROM.

WHY THIS FILE EXISTS (Milestone-1 architecture review, finding C1).

The `studio-evidence` check used to be a python one-liner inside
`tools/lune/gate_manifest.luau` asserting, among other things:

    f['focusLog'][2] == '/KbdNav/Volume/TrackHost/Track'   # the grip, THIRD

The device-bug round of 2026-08-12 wrapped the `keyboard_navigation` scenario's
body in a `UI.ScrollView` called `Body` (a real landscape defect: the column ran
239px past its own box at 705x338), so every surface in that fixture moved one
path segment deeper. The two assertions were rewritten to
`/KbdNav/Body/Volume/TrackHost/Track` — and the artifact they read was not
re-recorded. It is still the 2026-08-03 capture, still holding the old paths, so
the gate has been RED ever since, failing with:

    AssertionError: the grip must be reached THIRD, in document position

which is a sentence about traversal ORDER. It is not an order defect. It is
stale evidence, and the check said the wrong thing about it — the exact inverse
of the can't-ever-fail checks `docs/lessons/` already records: a check edited to
agree with the code while the recorded evidence stayed behind.

WHAT THIS DOES ABOUT IT. The staleness question is asked FIRST, and it is asked
structurally rather than by trusting a date: the expected path prefix is derived
from the scenario source that is on disk right now, and compared with the paths
the artifact actually recorded. A restructure of that fixture therefore reddens
this check with an explicit "re-record" instruction on the day it lands, and no
later edit to the ORDER assertions can make the gate look passable while the
evidence predates the scenario.

Re-recording needs Studio and a human. It is booked as owed work in
`docs/plans/device-bug-round-2026-08-12.md` ("Owed: the TD-13/TD-14 re-record"),
with the drive procedure and everything that must be captured.

Exit 0 = the evidence is current AND says what the stage claims. Any other exit
prints why, on stderr.
"""

import json
import os
import re
import sys

ARTIFACT = "artifacts/traversal-document-order/studio/traversal.json"
SCENARIO = "examples/gallery/scenarios/keyboard_navigation.luau"
CAPTURE = "artifacts/traversal-document-order/studio/td13-fixture.png"
PLAN = "docs/plans/device-bug-round-2026-08-12.md"


def fail(message: str) -> "NoReturn":  # noqa: F821
    sys.stderr.write(message.rstrip() + "\n")
    raise SystemExit(1)


def scenario_prefix(source: str) -> str:
    """The path the scenario ITSELF resolves its own surfaces under, read out of
    the fixture rather than restated here.

    `keyboard_navigation.luau` asks the runtime for its list host by absolute
    path (`ctx.instanceAt("/KbdNav/Body/List")`). That literal is the fixture's
    own statement of where its observed surfaces live, it is load-bearing in the
    fixture (the scroll trace reads nil without it), and it therefore cannot
    drift from the tree the scenario builds without the scenario itself
    breaking. Its parent is the prefix every focusable in that fixture shares.
    """
    found = re.search(r'ctx\.instanceAt\(\s*"(/[^"]+)"\s*\)', source)
    if found is None:
        fail(
            f"{SCENARIO} no longer resolves any absolute instance path, so this check cannot\n"
            "derive where its surfaces live. Re-point `scenario_prefix` at whatever the fixture\n"
            "now states, and re-record the evidence — do not delete the staleness guard."
        )
    return found.group(1).rsplit("/", 1)[0]


def focus_paths(row: dict) -> list:
    """A focus log entry is a bare path string in the 2026-08-03 capture; the
    live scenario appends `{ n, path, at }` tables. Accept either, so a
    re-record cannot fail this guard for a shape difference."""
    out = []
    for entry in row.get("focusLog") or []:
        out.append(entry if isinstance(entry, str) else entry.get("path"))
    return [p for p in out if p]


def main() -> None:
    for path in (ARTIFACT, SCENARIO):
        if not os.path.isfile(path):
            fail(f"missing {path}")
    doc = json.load(open(ARTIFACT))
    source = open(SCENARIO).read()
    prefix = scenario_prefix(source)
    rows = {r["id"]: r for r in doc["rows"]}

    # ---- 1. IS THE EVIDENCE STILL EVIDENCE OF THIS SCENARIO? ---------------
    recorded = []
    for row_id in ("TD13-forward-traversal", "TD13-reverse-traversal", "TD2-arrows-unregressed"):
        recorded += focus_paths(rows.get(row_id, {}))
    dump = (rows.get("TD14-dump-matches-behavior", {}).get("dump") or {}).get("traversal") or []
    recorded += [e["path"] for e in dump if e.get("path")]
    if not recorded:
        fail(f"{ARTIFACT} records no focus paths at all — it cannot support TD-13/TD-14.")
    strays = sorted({p for p in recorded if not p.startswith(prefix + "/")})
    if strays:
        fail(
            "STALE EVIDENCE — the artifact predates the scenario it claims to describe.\n"
            f"  artifact : {ARTIFACT}\n"
            f"  captured : {doc.get('date', '<undated>')} against {doc.get('scenario', '?')} "
            f"in {doc.get('place', '?')}\n"
            f"  scenario : {SCENARIO} now resolves its surfaces under `{prefix}/`\n"
            f"  recorded : {len(strays)} distinct path(s) outside it, e.g. {strays[0]}\n"
            "\n"
            "The device-bug round of 2026-08-12 wrapped this fixture's body in a `UI.ScrollView`\n"
            "(`Body`) to close a real landscape overflow, which moved every focusable one segment\n"
            "deeper. The assertions below were updated to the new paths; the RECORDING was not.\n"
            "This is not a traversal-order failure and must not be reported as one.\n"
            "\n"
            "THE FIX IS A RE-RECORD, NOT AN EDIT. Do not hand-edit the artifact, and do not\n"
            "revert the scenario — the ScrollView is a shipped fix. The drive procedure and the\n"
            f"full capture list are booked in {PLAN}, section\n"
            '"Owed: the TD-13/TD-14 re-record".'
        )

    # ---- 2. ...AND DOES IT SAY WHAT THE STAGE CLAIMS? ----------------------
    # (the original `studio-evidence` assertions, unchanged in substance; the
    # grip's expected path is now BUILT from the prefix the scenario states
    # rather than spelled out, so the next restructure cannot leave one of the
    # two spellings behind again)
    grip = f"{prefix}/Volume/TrackHost/Track"
    pre = doc["preflight"]
    assert pre["scenarioState"] == "ready", "preflight"
    assert pre["stalenessMarkerChecked"] is True, "staleness"
    assert pre["playerListEnabled"] is False, "DKN-1: Tab is only deliverable with the players list off"
    for key in (
        "TD13-forward-traversal",
        "TD13-reverse-traversal",
        "TD2-arrows-unregressed",
        "TD14-dump-matches-behavior",
        "TD13-capture",
    ):
        assert rows[key]["status"] == "PASS_AUTOMATED", key
    assert rows["TD15-consumer-canary"]["status"] == "PENDING", "the game-place canary must stay honest"
    forward = rows["TD13-forward-traversal"]
    assert focus_paths(forward)[2] == grip, "the grip must be reached THIRD, in document position"
    assert all(e["gameProcessed"] is False for e in forward["rawInput"]), "raw Tab must reach the developer binding"
    arrows = focus_paths(rows["TD2-arrows-unregressed"])
    assert not any("Track" in p for p in arrows), "the ARROWS must not visit the grip"
    traversal = [e["path"] for e in rows["TD14-dump-matches-behavior"]["dump"]["traversal"]]
    assert traversal[3] == grip, "dump must agree with the observed order"
    navigation = rows["TD14-dump-matches-behavior"]["dump"]["navigation"]
    assert navigation[-1]["name"] == "auto-grips", "the arrows keep the trailing grip group"
    if not os.path.isfile(CAPTURE):
        fail(f"missing {CAPTURE}")


if __name__ == "__main__":
    main()
