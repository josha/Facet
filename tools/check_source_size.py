#!/usr/bin/env python3
"""check_source_size — no NEW module may reach the 200,000-char Source cap.

WHY THIS EXISTS. Roblox refuses a `Script.Source` assignment of 200,000
characters or more. MEASURED IN A LIVE SESSION 2026-08-14, on a throwaway
ModuleScript, at four lengths — the engine's own words:

    Unable to assign property Source. Provided string length (200000) is
    greater than or equal to max length (200000)

so the boundary is `>=`, not `>`, and a file sitting at EXACTLY 200,000 is
unsyncable while reading as "not over the cap". This check was written with `>`
and would have passed it. That is the whole reason to measure an operation
instead of quoting its documentation. Loading a big module from a built `.rbxl` is fine — `rojo build`
writes the file directly and is not capped — but **every live path is a write**:
Rojo's Studio plugin, `execute_luau`, any plugin. So the moment a module crosses
the cap it stops live-syncing into an open Studio session, silently.

That is not a tidiness problem. It manufactures FALSE EVIDENCE: an agent runs a
live check in Studio, gets a result, and reports it as proof about code the
session has never loaded. On 2026-08-14 that happened repeatedly in one session —
one live verification had to be re-run as a clean-room experiment, and one agent
could not verify its fix at all (O-29). Full write-up:
`docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md`.

WHAT THIS CHECKS, and what it deliberately does not. FIVE modules were over when
this was written — the fifth, `solver.luau`, was found by this check on the day
it was written and nobody knew; `KNOWN_OVER` below is the live list, and a row
LEAVES it by landing under the cap. Failing on them would make the gate
un-passable and force either a rushed refactor of the most defect-dense files in
the framework or a blanket waiver — both worse than the problem. So each carries
its CURRENT size as a ceiling:

  * a file over the cap and NOT listed  -> FAIL (another file just crossed)
  * a listed file that GREW             -> FAIL (the problem is getting worse)
  * a listed file that SHRANK           -> FAIL, asking for the ceiling to be
                                           lowered, so progress ratchets and
                                           cannot silently reverse

The ceilings are the split work's scoreboard. `docs/handoff/` carries the seam
the architecture gate proposed; when a module lands under 200,000, delete its
row and it is guarded normally from then on.

FIRST ROW CLEARED: `src/controls/row_actions.luau`, 2026-08-14, 234,757 ->
183,738, in six commits and without touching `buildEngine` — the ONE ENGINE
whose ~3,230 lines share ~60 mutable upvalues on purpose. What came out was the
periphery that shares NOTHING with it: the ActionSpec contract, the coordinator
(already a public export), the reorder arbiter, the band metrics, the tray views
and the standalone row node. The test each extraction had to pass was the same
one: does it read or write a mutable upvalue of that closure? If not, it can
leave; if so, it stays. That test, not a line count, is what makes this kind of
split safe — and it is the recipe for the four rows still listed below.

SECOND ROW CLEARED: `src/client/screen_target.luau`, 2026-08-14, 234,055 ->
189,670, in two commits. The same test decided the seam: the scroll indicators
(`screen_scroll_indicators`) share ONE mutable upvalue with the host — the
indicator policy the create path reads at instance birth — and it became a
shared record; the bespoke paint vocabulary (`screen_paint`) reads three
reassigned host locals and takes accessors for them, which is the precedent
`screen_chrome` set inside this same file. Both were proved with a live A/B in
Studio: the same blueprint through the pre-split adapter and the split one
painted 34 nodes/modifiers with every compared property equal. The remaining two
proposed extractions (presentation ~575 lines, pointer ~310) were NOT taken —
10,330 chars of headroom is a real margin, and the paragraph above is the reason
to keep the seams for when they are needed rather than spending them now.

AND STOP AT A REAL MARGIN, not at 199,9xx. Landing this file at 198,960 was
enough to pass and not enough to survive: adding the header comment that tells
the next agent where the six siblings went put it straight back to 201,227, and
this check caught it in one run. The sixth extraction bought ~15k of headroom
instead. A ceiling reached by a hair is a file that crosses again on its next
honest comment.

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
    "src/render/renderer.luau": (
        242_943,
        "RAISED TWICE on 2026-08-14 — by ADR-0026 (authored opacity/scale/rotation) "
        "and again +4,763 by ADR-0028 (cross-surface overlap's alarm). THAT IS THE "
        "TREND WORTH READING: the two files still over the cap are the two where the "
        "interesting work keeps landing, so they get further from the cap while the "
        "stable files were the easy ones to split. renderer now has a proposed seam "
        "(lift the presentation channel out as a factory, ~8 call sites, every "
        "upvalue shareable by reference) and it should be taken before a third raise. "
        "Original ADR-0026 note follows. RAISED 2026-08-14 by ADR-0026, and the "
        "raise is on the record rather than silent. What was NOT allowed to land "
        "here: the whole composition seam — the three composition rules, the "
        "authored triple's domain checks and their reasoning, and the write memo's "
        "comparison — went into a NEW pure module, `src/render/presentation.luau`, "
        "which is where the seam belongs anyway. What did land is state and call "
        "sites that close over `handles`/`adapter`/`nodeAt`/the animation records. "
        "THE SEAM IS NOW PROPOSED, which is the change from the old entry's 'no "
        "seam proposed yet': lift the PRESENTATION CHANNEL out as a factory — "
        "`pushPresentationPaint`, `setPresentationTransform`, "
        "`setPresentationTransparency`, `readAuthoredPresentation`, "
        "`presentationShift`, and the six per-path maps (`lastTransform`, "
        "`lastTransparency`, `authored`, the two composed memos, `presentationLive`) "
        "— against ~8 call sites. Every upvalue it needs is shareable BY REFERENCE "
        "(the handle table, the adapter, `nodeAt`, `animationRecords`), which is "
        "what makes this seam cheap where `row_actions`'s and `presenter`'s are "
        "not. It is a scoped refactor mission (STUDIO.md: flag refactors, do not "
        "smuggle them into feature work) and is worth ~200 lines.",
    ),
    "src/layout/solver.luau": (
        213_731,
        "found BY THIS CHECK on the day it was written — nobody knew it was over. "
        "No seam proposed yet; it is the measure/arrange core and the most "
        "carefully-ordered file in the library.",
    ),
    "src/present/presenter.luau": (
        207_852,
        "crossed on 2026-08-14 (O-29) and immediately cost a live verification of "
        "ruling 9 — the running session held 198,387 chars, i.e. pre-fix code. "
        "RAISED +519 by ADR-0028 (cross-surface overlap): the surface registry and "
        "its dispose-time unregister.",
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
        elif size >= CAP:
            problems.append(
                f"{rel} is {size:,} chars, at or over the {CAP:,} Source-write "
                f"cap (the engine refuses `>= max`, measured live — not `>`), and "
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
        f"check_source_size: PASS — no new module at or over the {CAP:,}-char "
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
