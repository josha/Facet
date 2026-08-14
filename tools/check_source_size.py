#!/usr/bin/env python3
"""check_source_size — no NEW module may cross the 200,000-char Source cap.

WHY THIS EXISTS. Roblox refuses a `Script.Source` assignment over 200,000
characters. Loading a big module from a built `.rbxl` is fine — `rojo build`
writes the file directly and is not capped — but **every live path is a write**:
Rojo's Studio plugin, `execute_luau`, any plugin. So the moment a module crosses
the cap it stops live-syncing into an open Studio session, silently.

That is not a tidiness problem. It manufactures FALSE EVIDENCE: an agent runs a
live check in Studio, gets a result, and reports it as proof about code the
session has never loaded. On 2026-08-14 that happened repeatedly in one session —
one live verification had to be re-run as a clean-room experiment, and one agent
could not verify its fix at all (O-29). Full write-up:
`docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md`.

WHAT THIS CHECKS, and what it deliberately does not. FIVE modules are already
over — the fifth, `solver.luau`, was found by this check on the day it was
written and nobody knew. Failing on them would make the gate un-passable and
force either a rushed refactor of the most defect-dense files in the framework or a blanket
waiver — both worse than the problem. So each carries its CURRENT size as a
ceiling:

  * a file over the cap and NOT listed  -> FAIL (another file just crossed)
  * a listed file that GREW             -> FAIL (the problem is getting worse)
  * a listed file that SHRANK           -> FAIL, asking for the ceiling to be
                                           lowered, so progress ratchets and
                                           cannot silently reverse

The ceilings are the split work's scoreboard. `docs/handoff/` carries the seam
the architecture gate proposed; when a module lands under 200,000, delete its
row and it is guarded normally from then on.

THE CEILINGS WERE SNAPSHOT 2026-08-14 during a ten-agent session with features
still landing, so they are a high-water mark rather than a considered budget.
Re-snapshot them once the wave lands: a ceiling set mid-churn that nobody
revisits becomes a licence to grow.
"""

import sys
from pathlib import Path

CAP = 200_000

# path -> (ceiling, why it is over and what the plan is)
KNOWN_OVER = {
    "src/controls/row_actions.luau": (
        227_821,
        "the ONE ENGINE: ~3,230 lines are a single closure sharing ~60 mutable "
        "upvalues, deliberately never forked. The architecture gate recommends "
        "extracting ~375 lines of periphery (spec helpers, the coordinator which "
        "is ALREADY a public export, the Table reorder composition) and leaving "
        "buildEngine whole — splitting it means threading a state record through "
        "every function across code four device rounds hardened.",
    ),
    "src/client/screen_target.luau": (
        234_055,
        "many-purposed: a factory returning ~45 adapter methods, already "
        "banner-sectioned. The architecture gate proposes four extractions in "
        "order (scroll indicators ~215 lines as the cheap proof, then paint ~930, "
        "presentation ~575, pointer ~310), each following the screen_chrome "
        "precedent already inside this file so no call site changes.",
    ),
    "src/render/renderer.luau": (
        227_880,
        "no seam proposed yet. Crossed during round 3.",
    ),
    "src/layout/solver.luau": (
        213_731,
        "found BY THIS CHECK on the day it was written — nobody knew it was over. "
        "No seam proposed yet; it is the measure/arrange core and the most "
        "carefully-ordered file in the library.",
    ),
    "src/present/presenter.luau": (
        207_333,
        "crossed on 2026-08-14 (O-29) and immediately cost a live verification of "
        "ruling 9 — the running session held 198,387 chars, i.e. pre-fix code.",
    ),
}

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    problems: list[str] = []
    listed_seen: set[str] = set()

    for path in sorted(ROOT.glob("src/**/*.luau")):
        rel = path.relative_to(ROOT).as_posix()
        size = len(path.read_bytes())
        if rel in KNOWN_OVER:
            listed_seen.add(rel)
            ceiling, _why = KNOWN_OVER[rel]
            if size > ceiling:
                problems.append(
                    f"{rel} GREW to {size:,} against its {ceiling:,} ceiling "
                    f"(+{size - ceiling:,}) — it is already unsyncable; making it "
                    f"worse is not allowed"
                )
            elif size < ceiling:
                problems.append(
                    f"{rel} SHRANK to {size:,} (ceiling {ceiling:,}). Good — lower "
                    f"the ceiling in tools/check_source_size.py so the progress "
                    f"ratchets and cannot silently reverse"
                )
        elif size > CAP:
            problems.append(
                f"{rel} is {size:,} chars, over the {CAP:,} Source-write cap, and "
                f"is NOT a known offender. It will stop live-syncing into an open "
                f"Studio session — silently, so a live check against it tests the "
                f"place file rather than your edits. Split it, or add it to "
                f"KNOWN_OVER with the reason and the plan"
            )

    for rel in KNOWN_OVER:
        if rel not in listed_seen:
            problems.append(
                f"{rel} is listed in KNOWN_OVER but does not exist — if it was "
                f"split, delete its row"
            )

    if problems:
        print(f"check_source_size: FAIL — {len(problems)} problem(s):")
        for p in problems:
            print(f"  - {p}")
        return 1

    over = len(KNOWN_OVER)
    total = sum(c for c, _ in KNOWN_OVER.values())
    print(
        f"check_source_size: PASS — no new module over the {CAP:,}-char "
        f"Source-write cap. {over} known offender(s) at their ceilings "
        f"({total:,} chars total, {total - over * CAP:,} over)."
    )
    print(
        "  these cannot live-sync into an open Studio session; a live check "
        "against them tests the built place, not your edits"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
