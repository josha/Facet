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
could not verify its fix at all (O-29). The cap is on WRITING a source, not on
loading one, which is why a built place keeps working while the edits stop
arriving.

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
that binds a nil global instead of an upvalue. It is now a require,
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

FIFTH ROW CLEARED, AND THE LAST ONE: `src/render/renderer.luau`, 2026-08-14,
242,943 -> 175,901 in two commits. `KNOWN_OVER` is now EMPTY, so from here every
module in `src/` is guarded normally and any file that reaches the cap fails this
check on the run that crosses it.

A seam had been proposed for this one (the presentation channel), and the
mechanised test found a bigger one FIRST by asking the question of the whole file
rather than of the proposal: `toLayoutNode`, the measure seam, is not inside
`renderer.attach` at all — it is module-scope, every input already arrives as an
argument, and the nine module locals it reads are never reassigned. 46,476 chars
that entangle NOTHING (`src/render/layout_node.luau`). The proposed seam then
took the rest: the PRESENTATION CHANNEL — the imperative transform/transparency
writes, the authored `opacity`/`scale`/`rotation` triple, the `withAnimation`
records and the one write site they compose through — became a per-surface
factory (`src/render/presentation_channel.luau`, 34,390). Its thirteen pieces of
state are all private to it; the four things it needs from the renderer
(`handles`, `lastRects`, `findNode`, plus `core`/`root`/`adapter`) are shared BY
REFERENCE and never reassigned, which is why it needed no accessor callbacks
where `screen_paint` needed three. The one price: `dispose` now CLEARS
`handles`/`lastRects` in place instead of rebinding them, or the channel would
answer out of a table the surface had abandoned.

WHAT WAS JUDGED TOO ENTANGLED: `ensureTree` (~21.6k) and `solveAndApply` (~25.3k)
are the mount and commit cores and read or write nearly the whole ~120-local
`attach` closure — `handles`, `lastRects`, `lastVisible`, `lastHitRects`,
`lastPadding`, `lastCompact`, `lastWrapped`, `solverHidden`, `authoredHidden`,
`structureEpoch`, `pathNodeCount`, `dirtyContains`, the recycle pool and the
stats record among them, several of which are REASSIGNED (`presentationNodes`
was one, and it left with the channel). `structuralSync` (~10.5k) is the same
closure's retire sweep. None of the three is a mechanical move, and at 175,901 —
24,099 of headroom — none is needed.

LIVE PROOF, which is the whole point of this check: after the second commit the
Rojo plugin live-synced `renderer.luau` into the open Showcase session again, and
the injector reported `refused: []` / `staleModules: 0` where it would previously
have refused the file outright. The running datamodel holds 175,901 chars with
this mission's own pointer comments in it, and the 20-demo walk, a `withAnimation`
press, four theme swaps and both motion modes ran with no library error.

NO SIXTH ROW, BECAUSE THE SIXTH FILE WAS SPLIT BEFORE IT NEEDED ONE:
`src/controls/virtual_list.luau`, 2026-08-15, 195,074 -> 172,552 in two commits.
`KNOWN_OVER` was already empty and this file was never in it — it was 4,926
chars UNDER the cap, which is to say one honest comment from crossing it, and
the mission that had just landed measured extents hit 198,543 on its first draft
and got to 195,074 by TRIMMING 3.4 KB OF COMMENT. That is the wrong lever and it
said so: the comments in this file carry several device rounds of reasoning, and
the file was still one edit from unsyncable afterwards. The right lever was the
same mechanised test as the four rows above, applied BEFORE the check fails.

It found more than an architecture read would have: `virtual_list.build` is a
~3,200-line closure with 180 locals, and only ~24 of them are genuinely
REASSIGNED. (The naive script over-reports: `~=` reads as an assignment, and a
table constructor's `axis = axis` reads as a write. Both are worth filtering out
before believing the list — the second one alone inflated the count by half.)

Two blocks came out. The REORDER/DROP/AUTOSCROLL half
(`src/controls/virtual_reorder.luau`) writes exactly one mutable upvalue,
`lastIndexByKey`, which it also declares and nothing else reads — so the state
left with the code — and the three it READS are the reassigned host locals
(`boundController`/`boundScrollPath`/`mountedScrollPath`), which arrive as the
two accessors `controller()`/`hostPath()`, the `screen_paint` precedent. The
WINDOWING half (`src/controls/virtual_window.luau`) — the running-offset index,
the measurement cache's storage, the keyed window and `scrollTop` — writes two,
`cachedInputs`/`cachedIndex`, and both are its own memo-input cache.

WHAT WAS JUDGED TOO ENTANGLED, and by what. The HOSTED ROW-ACTIONS SECTION
(~45,000 chars, the single biggest remaining block) is this file's `buildEngine`:
nineteen of the reassigned locals are its own — `hostedActiveKey`,
`hostedPending`, `hostedSlidPath`, `hostedKeysContext`, `hostedOverlayItems`,
`hostedFocusRow`, `hostedMapWindow`/`hostedMapRoot`, `engagedKey`/`engagedOffset`,
`hostedCommitKey`/`hostedCommitPx`, `hostedCoordinator` — which would move WITH
it, but three do not: `suppressActivatePath` is written by the keyboard plumbing
600 lines away as well as by six sites inside, the six bind-time relays
(`hostedMotionClock`, `hostedNow`, `hostedActionSystem`, `hostedFocusGraph`,
`hostedPresentModal`, `hostedDismiss`) are written by the contribution bundle
below, and `engagedKey`/`engagedOffset` are read by `dump()` and the public list.
That is a factory with three setters and a shared latch, not a mechanical move,
and at 27,448 of headroom it is not needed. The KEYBOARD/GAMEPAD PLUMBING
(~23,000) is the next-cheapest seam if it ever is: it writes `suppressActivatePath`,
`unwatchRegistry`, `lastIndexOfFocused` and — through `buildFocusGroups` —
`mountedScrollPath`, four accessors' worth. The FOCUS POLICY (~8,200) writes
`pinnedKey`/`pinnedSlot`/`lastIndexOfFocused` and is only worth ~8 KB.

LIVE PROOF, run as an A/B rather than as a "it still boots": both sources loaded
into FRESH cloned library trees in the open Showcase session — so no module cache
could answer for the old code — and driven through the same script. Uniform,
variable and measured lists, keep-visible, an engine scroll write, autoscroll, a
re-sort and `dump()`: 9 compared lines, 0 differ. The measured seam end to end
(mount, feed `syncGeometry` rects, scroll, feed again, prune): 5 compared lines,
0 differ, with the cache converging 0 -> 11 -> 24 rows and the epoch bumping once
per BATCH identically on both. And the 172,552-char `Source` assignment itself
succeeded — which is the whole point of this file.

AND STOP AT A REAL MARGIN, not at 199,9xx. Landing this file at 198,960 was
enough to pass and not enough to survive: adding the header comment that tells
the next agent where the six siblings went put it straight back to 201,227, and
this check caught it in one run. The sixth extraction bought ~15k of headroom
instead. A ceiling reached by a hair is a file that crosses again on its next
honest comment.

SEVENTH FILE, AND THE FIRST SPLIT ALONG A SEAM ITS OWN AUTHOR NAMED:
`src/layout/solver.luau` again, 2026-08-15, 194,222 -> 169,436 in one commit.
5,778 chars from the cap, which is one honest comment, and the seam had been
written down eight days earlier by the mission that grew the file (`02b9df1`):
"the grid is now a coherent ~9k unit (`gridFlowPlan`, `gridColumnPlan`, both
measure and arrange branches). The next grid change should extract it to
`src/layout/grid.luau` the way `shrink.luau` was extracted, not squeeze." It
measured 24,786 rather than ~9k, because the estimate counted the two plan
functions and not the ~430 lines of block comment that carry four device rounds
of reasoning about them — which is the argument for the seam, not against it.

THE MECHANISED TEST WAS RE-RUN RATHER THAN TRUSTED, and it still returns three:
the solver is not a closure (every function is module-scope and takes `ctx`), and
`measure`, `measureUncached` and `setFitProbe` are the only mutable module-level
locals. The grid block WRITES none of them and READS exactly one, `measure`. That
one read is the whole reason its `Deps` record differs from `shrink`'s: a forward
declaration cannot go into a load-time record BY VALUE, so `GRID_DEPS` holds a
two-line forwarder that reads the local at call time. `src/layout/grid.luau`
itself has ZERO mutable module locals, which a case in
`tests/grid_measure_arrange.spec.luau` now pins.

WHAT MOVED WITH IT, AND WHY THE BRANCHES COULD NOT STAY BEHIND. The flow grid is
written once in LANE/FLOW words that bind to width/height in exactly two places:
`innerLane`/`innerFlow` inside `gridFlowPlan`, and the placement in the arrange
branch. Leaving one of those two bindings in the solver would put the transpose
(`flow = "column"`) one edit away from disagreeing with itself, so both measure
branches and both arrange branches came too. The price is honest and visible: the
arrange entries take `place` (the solver's recursive `arrange`) and `alignOffset`
as ORDINARY ARGUMENTS rather than `Deps` fields, because both are declared below
where `GRID_DEPS` is built and a forwarder written up there would resolve the nil
GLOBAL.
Forward-declaring them to avoid that would have added a FOURTH mutable module
local — the opposite of the property this whole ratchet is measured on.

THE SINGLE-OWNER PROPERTY IS THE THING A GRID SPLIT CAN BREAK, and it is now
pinned rather than assumed. Measure and arrange call ONE plan function; the
`ctx.gridPlan` cache is determinism and cost, NOT the guarantee. Measured, not
argued: emptying the arrange side's cache entry (`ctx.gridPlan[node.id] = nil`
immediately before `grid.arrange`) moves NO RECT — the suite goes 5359 -> 5355
passed with 4 red, three of them instance-count/pool cases reacting to the extra
re-measure and the fourth this split's own structural pin objecting to the
mutation itself. So a second copy that agrees today would pass every behavioural
case in the file, which is why the pin is structural and directional: a decoy
second definition in the solver, an arrange that reads the cache instead of the
owner, and a mutable module local in `grid.luau` were each confirmed to redden it.

WHAT IS STILL TOO ENTANGLED, and by what — unchanged from the fourth row above,
because the three forward declarations are what entangle it and the grid took none
of them. `contentSize` (~830 lines) and `arrange` (~1,320) are the measure/arrange
core and both READ `measure`, `measureUncached` and `setFitProbe`: the first two
are mutually recursive through the per-solve memo, and the third is written by
`chosenCandidate` and read by the shrink call site. Splitting either would
duplicate the memo or hand three function references down every recursion.

THE NEXT SEAM, if this file ever needs one, is the FLOW-WRAP branch —
`flowPartition`/`flowPlan` plus its two branches, ~6k, clean by the same test
(it reads `measure`, `dim`, `sides` and nothing mutable) and structurally the
grid's twin: one plan, two passes, a cache on the ctx. It would arrive with the
same `Deps` + call-site-`place` shape this row worked out. It is NOT needed at
169,436 — 30,564 of headroom, the widest margin any file in `src/` has had — and
`flowPartition` is a PUBLIC export the game's `facet_flow_wrap_contract` spec
calls directly, so moving it costs a re-export the grid did not.

LIVE PROOF, which is the whole point of this check: after the commit the Rojo
plugin synced both files into the open Showcase session, and the running datamodel
holds `ReplicatedStorage.Facet.layout.solver` at exactly 169,436 chars with this
mission's `GRID_DEPS` marker in it and a NEW sibling `layout.grid` at 34,447 —
which also proves the directory-mount claim the game-side rider makes, since no
project file was edited. Driven live: both flow directions solve to an exact
transpose with zero diagnostics, the row grid and the `gridrow` branch place their
columns, a bare `UI.GridRow` still files its diagnostic (so the moved arrange
branch really executes rather than dying nil inside a protected boundary), and a
full mount through the presenter paints all three grid layouts with none.

EIGHTH AND NINTH FILES, AND THE TWO SEAMS THE SECOND ROW LEFT ON THE TABLE:
`src/client/screen_target.luau` a third time, 2026-08-15, 194,759 -> 167,749 in
two commits. It was 5,241 chars from the cap — one honest comment — and the
mission that split it last had NAMED both remaining seams and its reason for not
taking them ("the paint bundle was already 17 ctx entries / 9 callbacks; the next
one would have been larger for less. A bundle of twenty callbacks is a worse
module than a big file"). That prediction turned out to be exactly backwards for
these two, and the mechanised test is what showed it rather than a re-read.

THE PRESENTATION CHANNEL (`src/client/screen_presentation.luau`, 19,088) declares
five locals that something outside writes, and only TWO are real:
`presentationCount` and `subtreeCache`. `presentationTransforms` and the host
registry are never reassigned, only mutated, so a table CAN go back to the host
AS ITSELF and its reads stay byte-identical; `path`, `expander` and `live` were
the false positives this header's fourth row warned about. (`presentationTransforms`
still does. The registry stopped: the nested-tree migration renamed it `instanceHosts` and
made it PRIVATE behind `registerHost`/`unregisterHost`/`hostAt`/`hostFor` — not
because the extraction demanded it, but because "which paths get registered" is
the one predicate the nested-tree migration changes, and a shared table has no
single place to put a policy.) Its ctx is THREE entries and TWO
callbacks (`handlesByPath`, `refitIconArt`, `ensureScale`), and it needed no
accessors at all, because nothing in it reads a reassigned host local.

THE POINTER SEAM (`src/client/screen_pointer.luau`, 20,445) is cheaper still: ONE
ctx entry, `handlesByPath`, and ZERO callbacks. The cursor state
(`CURSOR_ART`/`hoverHint`/`captureHint`/`applyCursor`) came with it rather than
staying behind, because `captureHint` is written only from inside the capture and
`hoverHint` only from the hover wiring — leaving them would have bought two
accessors for state neither side shares.

TWO EXPORTS PER MODULE ARE NOT A RENAME, and in both cases they are exactly the
mutable upvalues, which is the shape this whole ratchet keeps arriving at.
Presentation: `setTransform` (setProp's whole `transform` branch, the one writer
of the count), `dropPath` (remove/destroyRoot's identical per-path teardown) and
`invalidateSubtree` (the five structural-change sites). Pointer: `capturedHandle()`
for the host's three reads of `activeCapture`, and `disposeGlobals()` for
destroyRoot's menu-connection-plus-cursor teardown. Everything else is rebound to
a local of its ORIGINAL name, so no call site below either seam moved.

WHERE THIS STOPS, AND THE MEASURE IT STOPS ON. The callback bundle went 17 ctx /
9 callbacks (paint, the row above) -> 3/2 -> 1/0. The next candidate reverses
that: the FOCUS-VISUAL PAIR (`setFocusVisual` + `refreshFocusVisuals`, ~19,200,
the largest remaining coherent block after `setProp` and `create`) READS all three
of the host locals the theme install reassigns — `focusTreatment`, `activeTheme`
and the theme snapshot — so it arrives needing screen_paint's three accessors plus
`focusedHandles`, `chromeState`, `focusArtHost`, `hasUIShadow`, the palette and
the paint-claim ledger. That is a paint-sized bundle for less code, at 32,251 of
headroom. `setProp` (24,813) is the adapter's central switchboard and touches
nearly every local in the closure; `create`/`buildHandle` (16,120) is the
materializer and is where the class table, the elision rules, the clip-host
parenting and the skinning handoff all meet. Neither is a seam, and the file is
now 142 locals with 19 reassigned, most of those forward declarations.

BOTH SPLITS WERE PROVED WITH A LIVE A/B, not a boot check, because the fake target
never runs this file and a green headless suite proves nothing about it. Each
pre-split source was pushed
to the open Showcase session by Rojo as a sibling module and loaded into a FRESH
cloned library tree — require caches by Instance, so a Source write alone is
invisible — then driven identically. Presentation: 51 rows, 0 differ, covering
offset accumulation, the walk stopping at a clip host, the size half, Path2D
control points, the centered pivot and shared UIScale, a node born inside a live
transform, park/adopt/remove/destroyRoot. Pointer: 21 rows, 0 differ, under REAL
synthesized input — a capture opening (captureHeld 0 -> 2), `park` refusing the
captured node, `remove` cancelling with reason "removed", and `destroyRoot` taking
the global connection 1 -> 0. ONE INSTRUMENT TRAP worth recording: the MCP's
synthesized pointer arrives as TOUCH and does NOT drive `GuiButton.Activated`, so
the activate half is proved by the connection census plus `driveActivate` rather
than by a synthetic click.

THE CEILINGS WERE SNAPSHOT 2026-08-14 during a ten-agent session with features
still landing, so they are a high-water mark rather than a considered budget.
Re-snapshot them once the wave lands: a ceiling set mid-churn that nobody
revisits becomes a licence to grow.
"""

import re
import sys
from pathlib import Path

CAP = 200_000

# THE WARNING BAND (MAINT-1, 2026-08-17). The cap alone is not a budget: it is a
# cliff. Before this existed, `main()`'s only size branch was `>= CAP`, so the
# first signal a maintainer got was the commit that made a file unsyncable — and
# the remedy the header prescribes (find a seam by the mutable-upvalue test,
# prove it with a live Studio A/B) is a multi-hour mission, not an edit. Five
# modules were sitting inside 10 KB of the cap and one of them 350 chars from it,
# which turned every ordinary maintenance act on the densest files in the
# framework into a hazard.
#
# So the band is a REQUIREMENT TO HAVE DONE THE THINKING, not a warning to
# ignore: at or over WARN a module fails unless tools/lune/verify/data/source-cap-ledger.md
# carries a row for it that names (a) its size at the time it was recorded,
# within DRIFT_ALLOWANCE of what it is now, (b) a seam analysis — the one-way
# candidates, or the recorded reason none exists — and (c) the trigger that ends
# the deferral. A row that has drifted past the allowance fails too: it means the
# file grew since anyone last looked at the analysis, which is exactly when the
# analysis is worth re-reading.
WARN = 190_000
DRIFT_ALLOWANCE = 2_000
LEDGER = "tools/lune/verify/data/source-cap-ledger.md"

# path -> (ceiling, why it is over and what the plan is)
KNOWN_OVER: dict[str, tuple[int, str]] = {}

ROOT = Path(__file__).resolve().parent.parent


def read_ledger() -> tuple[dict[str, dict[str, str]], list[str]]:
    """Parse source-cap-ledger.md's rows.

    One row per module, in a markdown table whose first cell is the module path
    in backticks:

        | `src/render/renderer.luau` | 194,791 | <seam analysis> | <trigger> |

    Returns (rows, problems). A malformed row is a problem, not a silent skip —
    the whole point is that the ledger cannot be a place text goes to die.
    """
    path = ROOT / LEDGER
    if not path.exists():
        return {}, []
    rows: dict[str, dict[str, str]] = {}
    problems: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 4:
            continue
        module = re.fullmatch(r"`([^`]+)`", cells[0])
        if module is None:
            continue
        rel = module.group(1)
        digits = re.sub(r"[^0-9]", "", cells[1])
        if not digits:
            problems.append(
                f"{LEDGER}: the row for {rel} does not record a size in its "
                f"second column (got {cells[1]!r})"
            )
            continue
        if len(cells[2]) < 40:
            problems.append(
                f"{LEDGER}: the row for {rel} has no real seam analysis — name the "
                f"one-way candidates, or record why none exists"
            )
            continue
        if len(cells[3]) < 20:
            problems.append(
                f"{LEDGER}: the row for {rel} has no next-extraction trigger — a "
                f"deferral with no trigger is a deferral forever"
            )
            continue
        rows[rel] = {"size": int(digits), "seam": cells[2], "trigger": cells[3]}
    return rows, problems


def main() -> int:
    problems: list[str] = []
    listed_seen: set[str] = set()
    ledger, ledger_problems = read_ledger()
    problems.extend(ledger_problems)
    ledger_seen: set[str] = set()
    in_band: list[tuple[str, int]] = []

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
        elif size >= WARN:
            in_band.append((rel, size))
            row = ledger.get(rel)
            if row is None:
                problems.append(
                    f"{rel} is {size:,} chars — inside the {CAP - WARN:,}-char warning "
                    f"band below the {CAP:,} Source-write cap, and it has no row in "
                    f"{LEDGER}. Add one recording its size, a seam analysis (the "
                    f"one-way candidates, or why none exists) and the trigger that "
                    f"ends the deferral. The cap is a cliff; this band is the last "
                    f"place the thinking is cheap"
                )
            else:
                ledger_seen.add(rel)
                drift = size - row["size"]
                if abs(drift) > DRIFT_ALLOWANCE:
                    problems.append(
                        f"{rel} is {size:,} chars against the {row['size']:,} its "
                        f"{LEDGER} row records ({drift:+,}, past the "
                        f"{DRIFT_ALLOWANCE:,} allowance). Re-record the size AND "
                        f"re-read the seam analysis — the file moved since anyone "
                        f"last looked at it, which is when that analysis is worth "
                        f"re-reading"
                    )
        elif rel in ledger:
            ledger_seen.add(rel)

    for rel in ledger:
        if rel not in ledger_seen and not (ROOT / rel).exists():
            problems.append(
                f"{LEDGER} carries a row for {rel}, which does not exist — if it "
                f"was split, delete the row"
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
    if over == 0:
        # the list emptied on 2026-08-14 (see the header). Say so rather than
        # printing "0 known offenders ... 0 over", which reads like a check that
        # is not looking at anything.
        print(
            f"check_source_size: PASS — every module in src/ is under the "
            f"{CAP:,}-char Source-write cap, and KNOWN_OVER is empty. Nothing is "
            f"waived: a file that reaches the cap fails on the run that crosses it."
        )
        if in_band:
            print(
                f"  {len(in_band)} module(s) inside the {CAP - WARN:,}-char warning "
                f"band, each with a seam analysis and a trigger in {LEDGER}:"
            )
            for rel, size in sorted(in_band, key=lambda row: -row[1]):
                print(f"    {rel} — {size:,} ({CAP - size:,} to the cap)")
        return 0
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
