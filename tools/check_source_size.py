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

THIRD ROW CLEARED: `src/present/presenter.luau`, 2026-08-14, 207,852 -> 179,055
in two commits, and the seam was found by MECHANISING the same test rather than
by reading for "things that look separable". A script listed every local
declared at `presenter.new`'s scope, then every later assignment to one, which
splits the closure's 95 locals into ~68 that are only ever READ (a by-reference
table, a pure helper, a constant — all of them safe to pass as arguments) and
~27 that are REASSIGNED. Only the second set entangles. The two catchers —
the modal/engaged scrim and the transient popup catcher — came out first
because they scored ZERO on it: the only mutable upvalues they touch (`scrim`,
`popupCatcher`) are ones they also declare and nothing else in the file reads,
so the state left with the code. Everything else they need is `stack`, the
presenter instance and `metricsNow()`, none of which is ever reassigned.
See `src/present/catchers.luau`. The second commit took the AUTO REVEAL
marquee (`src/present/text_reveal.luau`) on the same score — `revealState` and
`revealScan` are its own, and its one collaborator from the disclosure block,
`plateShows`, is a `local function` that is never reassigned and so goes by
value. Its ONE reader outside itself (`dismiss`'s "retire the strip if this
surface owns it") became `retireRevealFor(owner)`, so the predicate moved in
with the state rather than leaving a hole in it.

STOPPING AT 179,055 — 20,945 of headroom — was deliberate, and the second
commit is why: 192,454 passes this check and is NOT a margin (see the
`screen_target` paragraph below, which learned that at 198,960). What was
judged TOO ENTANGLED and left alone: `makeHandle` (~1,690 lines, ~79k chars),
which is to this file what `buildEngine` is to `row_actions` — it reads and
writes `displayLayer`, `activateEcho`, `handleByPath`, `dismissDisclosure`,
`syncDisclosureFocus` and `motionClock`, and every surface's whole lifetime
closes over them; and `withAnimation`, whose animation records and
`inWithAnimation` re-entrancy flag are read by the commit path. Neither is a
mechanical move, and neither is needed now.

FOURTH ROW CLEARED: `src/layout/solver.luau`, 2026-08-14, 213,731 -> 184,574 in
two commits. NO SEAM HAD BEEN PROPOSED for this one, so finding it was the work,
and the mechanised test found it in one pass: the solver is not a closure at all
— every function is module-scope and takes `ctx` as an argument — so the script
that lists `local` declarations against later assignments returns exactly FOUR
mutable module-level locals, all forward declarations (`measure`,
`measureUncached`, `setFitProbe`, `shrinkStack`). Everything else in the file is
immutable, which is what made a file this carefully ordered tractable.

Two blocks came out. The PLACEMENT-PROP READ TABLE
(`src/layout/placement_audit.luau`) scores zero on the test in the strongest
sense available: it reads no `ctx`, no forward declaration and no other module
local, so it moved verbatim and is re-exported as `solver.auditPlacement`. The
MAIN-AXIS SHRINK PASS and its degrade cascade (`src/layout/shrink.luau`) is the
more interesting one — it WROTE one of the four, and lifting it out is what
makes that upvalue go away: `shrinkStack` was forward-declared near the top and
assigned ~2,300 lines below because both passes call it, exactly the shape
`docs/lessons/later-locals-are-not-upvalues.md` records. It is now a require,
bound before anything can call it, and the solver is down to three. The three
helpers it reads (`mainDimOf`, `sides`, `textTypography`) are immutable
module-level functions, so they are threaded as an explicit `Deps` argument
rather than captured — the module holds no state.

WHAT WAS JUDGED TOO ENTANGLED, and by what: `contentSize` (~830 lines) and
`arrange` (~1,320) are the measure/arrange core, and both READ `measure` /
`measureUncached` / `setFitProbe`, the three forward declarations that remain.
`measure` and `measureUncached` are mutually recursive through the per-solve
memo, and `setFitProbe` is written by `chosenCandidate` and read by the shrink
call site; splitting either of the two big functions would either duplicate the
memo or hand three function references down every recursion. The flow-wrap
branch and the grid arithmetic are both clean by the same test (they read
`measure`, `dim`, `sides` and nothing mutable), so they are the NEXT seams if
this file ever needs them — worth ~6k and ~10k. It does not need them at
184,574, and the recurring defect class here ("a container that measured one
shape and arranged another", fixed four separate times) is a reason to spend a
seam only when the cap forces it.

THE SPLIT'S REAL HAZARD IS A SOURCE PIN, and this one proved it: a structural
test in `tests/stack_distribution.spec.luau` reads the solver as text and
asserts that the shrink pass applies `and weight > 0`. That line moved, and the
pin went red rather than silently passing forever — which is the good outcome,
and it is why `check_prop_parity` now reads the solver as a PARTS LIST the way
it already reads the renderer.

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
        200_109,
        "SPLIT IN PROGRESS, 2026-08-14: 242,943 -> 200,109 with the MEASURE SEAM "
        "out (`src/render/layout_node.luau`, 46,476) — `toLayoutNode` plus the "
        "button-text grammar it shares with the paint seam and the declared hit "
        "floor. It entangles NOTHING: it was already a module-scope function whose "
        "every input arrives as an argument, so the split is a move plus two "
        "re-exports (`renderer.compactForm`/`renderer.drawnButtonText` did not "
        "budge). The pins that read 'the renderer' as text now read it through "
        "`tests/lib/renderer_source.all()`, the same instrument "
        "`tests/lib/adapter_source` already is for the adapter, and "
        "`check_prop_parity`/`check_theme_drift` scan both files — a source pin "
        "that silently stops seeing the code it names is this split's real hazard. "
        "NEXT: the presentation channel, below. Original entry follows. "
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
