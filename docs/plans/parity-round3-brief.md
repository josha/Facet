# SwiftUI parity round 3 — mission brief

The binding, full-length statement of the mission. The `/goal` prompt is a
summary and points here; where the two differ, **this file wins**.

Round 2 shipped `withAnimation`, the layout vocabulary, indicators,
`sensoryFeedback`, Table primary actions, a rewritten and cited parity doc, and
a device-bug round. Round 3 closes the gaps that round exposed — and the way it
exposed them is the reason this brief leads with rules rather than features.

## The standing rules — these bind every item below

1. **Prefer a Roblox-native mechanism over one we build.** Check the *current*
   docs before writing anything; do not trust memory that "Roblox doesn't have
   X" — this repo has been wrong about that twice. If a first-party feature
   exists, use it and say so; hand-roll only after stating the tradeoff and
   getting approval. Applies to layout, input, scrolling, text, styling,
   haptics — everything.

2. **General mechanism, never a special case.** Round 2's recurring trap: the
   auto Edit/Done toggle keyed on `reorderable` when the real question was "is
   any capability reachable *only* in edit mode"; the animation precedence rule
   excluded a whole subtree when it needed to exclude one node. When you find
   yourself writing a second `if` for a sibling case, the first one was the bug.
   A two-member union with a comment beats a registry — but say which you chose
   and why.

3. **Performance is a feature — and the headless bench is not the instrument
   you think it is.** Three "improvements" in round 2 evaporated when measured
   properly, so: state the harness's same-arm spread *before* any delta, and
   prove a new feature's off-path cost is ~zero rather than asserting it.

   But `tools/perf.sh` runs against a **fake target under Lune**. The roadmap
   marks it non-authoritative on purpose: it is a **regression signal**, never a
   device claim. Round 2 leaned on it exclusively, which means every performance
   statement that mission made is "nothing got obviously worse in a simulation",
   not "this is fast on a phone".

   **We already ship the real instrument and have never once read it.**
   `src/core/profile.luau` emits **twelve** MicroProfiler scopes through
   `debug.profilebegin`/`profileend`, with balance-on-every-exit-path and a
   cardinality bound proved by `tests/profile_scopes.spec.luau` — because Lune
   has no `debug.profilebegin`, so the instrumented branch is otherwise never
   executed at all. And `examples/places/Facet-PerformanceLab.rbxl` exists,
   is current, and is built for exactly this.

   So the scope discipline is proved and the capture has never been taken. That
   is the `the-solver-already-told-you` pattern again: an instrument shipped,
   and the thing it exists for never happened.

   **This round changes that.** Establish a MicroProfiler capture path over the
   performance lab: which scenes, what the twelve scopes should look like, what
   a healthy frame costs, and where the captures live. Then treat the three
   tiers honestly and label every number with its tier — **headless Lune** =
   regression signal; **MicroProfiler in Studio** = real engine work with real
   instance counts; **a physical device run** = the only thing that supports a
   device claim. Where a claim needs a tier we have not run, it is a
   `PENDING_PHYSICAL` row, not a rounded-up number.

4. **Every gap closure ships its showcase demo**, registered in
   `scenarios/init.luau` `ORDER` **and** `demo_picker.DEMOS`, swept by
   `tests/overflow_sweep.spec.luau` at all viewports, and verified to not
   overlap or clip **across every shipped theme** — Pixel Quest and Parchment
   have both broken layouts that Studio Neutral survived.

5. **Docs and guide in plain language**, ELI5 where a concept is new. A reader
   who has never seen the framework should understand what a thing is for
   before how it works. Every SwiftUI claim carries a citation per the §16
   convention now enforced by `check_docs`. The relevant parity doc section 
   is rewritten fresh, changes are not listed as a changelog so that the doc always
   reads cleanly.

6. **Commit as you go**, in coherent chunks. Round 2 lost uncommitted work to a
   concurrent `git checkout`; do not repeat it.

7. **Adapt deliberately**: display size, orientation, input class
   (pointer/touch/keyboard/gamepad), and platform paradigm. Where the right
   behaviour is ambiguous, follow SwiftUI/HIG — but verify it, don't recall it.
   Round 2 asserted three SwiftUI facts from memory and all three were wrong.

8. **Verify in Studio** where only a real adapter can show it. Headless green is
   necessary, never sufficient — every one of the nine device bugs passed a
   green suite.

## The work

**A. Native flex parity — finish it.** Round 2 closed three of four gaps
(`distribute`, `layoutPriority`×`shrinkWeight`, `lineAlign`). **Flow-wrap
(`UIListLayout.Wraps`) remains, and Facet is behind the native controls until
it lands.** It is a real arrange branch: line breaking, per-line cross extent,
and a cross-axis line-distribution rule Roblox does not define — so we must.
Interacts with incremental layout, instance recycling and virtualization, each
with live budgets. See `parity-round2.md` §2.7.

**B. The custom `Layout` protocol — evaluate first, then decide.** Ranked
mid-list in the completeness audit but with leverage far above its rank: it
would make flow-wrap and radial layouts *consumer* code rather than framework
missions. Decide **before** building A whether A should be its first client.

**C. Per-row capability opt-outs.** `selectionDisabled` / `deleteDisabled` /
`moveDisabled`. The director's correction stands: this is a legitimate user
option and the framework should offer it — the "its only candidate wouldn't
adopt it" argument was about one screen's UX, not about the primitive. The
real constraint is sequencing: it is a **family across two controls**
(`Table`, `VirtualList`) that `swiftui-parity.md` §13 already says should be
unified. Do the unification question first, then ship the family once.

**D. The completeness audit's ranked gaps** —
`parity-completeness-audit-2026-08-13.md`, 39 capabilities, clustered blind
spots (preferences **5/5**, view groupings 5/7, scroll views 6/12). Take the top
of the ranked list; leave the rest recorded. Note four capabilities **already
ship and were never rowed** (`newAsyncImage`, `canvasGroup`,
`TextField.keyboardType`, `effectiveTransparency`) — row them, that is free
parity we are not claiming.

**D2. Circular progress indicators — both forms, and they are missing.**
Game-director request, 2026-08-13, citing Apple's HIG
[Progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators):
the **determinate circular** (a ring that fills) and the **indeterminate
circular spinner** (the rotating one). Facet ships **neither**.

What actually ships today: `presentation = "bar" | "spinner"` where `"spinner"`
is **indeterminate-only** — a determinate spinner is refused at construction
(`src/controls/progress_view.luau:19-23`) — and the thing called a spinner is
**five pulsing dots**, not a rotating circular indicator at all.

**The refusal was right for its phase and is wrong now.** Its stated reason is
*"the blueprint has no rotation or trim channel to draw one with — offering it
would mean inventing a styling system this control is explicitly not allowed to
grow (§3.1: No new styling system)"*. Correct under round 2's constraint. But
two sanctioned vehicles already exist and it did not reach for either:

- **`Path2D`** — `UI.Path` and `src/controls/path_shapes.luau` ship, and
  `parity-next.md` investment 7 already names this exact case: *"`Gauge`
  and radial progress on `Path2D` only after the path spike proves authored
  curves, clipping, layering, and device cost."* The spike has happened.
- **Rotation is already a presentation-channel property** — the transform
  carries `rotation` and the adapter writes `instance.Rotation`
  (`screen_target.luau`'s `applyPresentationPaint`).

So: **check for a native Roblox radial/arc primitive first** (standing rule 1 —
do not trust memory that the platform lacks one), and if there is none, build
both forms on `Path2D` rather than inventing a channel. Requirements:

- **both** determinate (ring fills to `value`) and indeterminate (rotates);
- **small by default** — the director asked for a *smaller* indicator, so the
  size comes from a theme metric beside `controls.progress.spinnerDotSize`, not
  a per-call number, and the existing `height`-is-the-bar's-track refusal
  (`:25-32`) tells you where a spinner's size is allowed to come from;
- the **reduced-motion policy is already decided and must be inherited**: the
  indeterminate cycle is `informational`, so under reduced motion it keeps
  advancing on the quantized tick rather than freezing — *"a frozen spinner and
  a hung process look identical"* (`:50`, `:63`);
- the indeterminate cycle **acquires a clock entry**, so it inherits round 2's
  `scope` requirement — the leak must stay unrepresentable;
- device cost measured on the **MicroProfiler** path (standing rule 3), because
  a rotating arc is the first per-frame *paint* this control has drawn.

**D3. Re-prove the five clean-room reference apps against the new surface.**
Game-director request, 2026-08-13. `examples/reference/p1_glade`, `p2_cartwheel`,
`p3_sipworks`, `p4_foyer`, `p5_wardrobe` — Facet's answer to Apple's sample
apps, and the only artefacts in the repo built **clean-room**: written from a
spec by an author who did not read framework internals, which is what makes them
evidence rather than demos.

**So this is a re-proof, not a refresh, and the finding is more valuable than the
diff.** Round 2 added `withAnimation`, `distribute`, `layoutPriority` ×
`shrinkWeight`, `lineAlign`, `GridRow` + `gridSpan`, `containerRelativeFrame`, a
horizontal `newVirtualList`, indeterminate progress, `sensoryFeedback`, Table
`onPrimaryAction` and hosted swipe actions. The question these apps exist to
answer: **does an author reach for them unprompted?** Work each app the way its
original author would — from the guide and `api.md`, not from the source — and
record, per adoption:

- **found unaided** — the API was discoverable from the docs alone;
- **found only after being told** — a documentation defect, and the more useful
  result. Fix the doc, do not just adopt the API;
- **wanted and absent** — a genuine gap; cross-check it against
  `parity-completeness-audit-2026-08-13.md`'s 39, since these apps are the most
  likely place its clustered blind spots (preferences 5/5, view groupings 5/7)
  actually bite.

**Hunt the obsolete workarounds specifically.** Each app carries hand-tuning that
predates the new vocabulary and is now the wrong shape — `p4_foyer`'s
`ViewThatFits` ladder for its wings, any hand-placed `Spacer` doing a
`distribute`'s job, any percent-of-parent dim that wanted
`containerRelativeFrame`, any manual compression that wanted `shrinkWeight`.
Replacing one is a *stronger* proof than adding a new call, because it shows the
framework absorbed something the author previously had to hand-build. Note the
live precedent and its trap: `06_tile_game`'s `ViewThatFits` ladder forced its
readouts to be written twice, which moved them off their published paths and
past a green suite — so when a ladder comes out, assert the paths.

**These apps are gated.** Their specs (`tests/reference/*_spec.luau`) run in the
suite and `swiftui-reference-app-validation` is a registered gate stage; the
five places are built by `tools/build_places.sh`. Any change ships with its
specs, its rebuilt place, and the showcase rule in full.

**E. Owed from round 2** — the full list is in `parity-round2.md` and
`device-bug-round-2026-08-12.md`; the load-bearing ones: the Studio device
canary on the rebuilt showcase; the `traversal-document-order` re-record (that
gate is honestly RED); the chrome restructure (chrome is unreachable without a
pointer — `[SHOWCASE-CHROME]: CONCERNS 16`); the reduced-motion settings
surface; `api.md`'s round-2 prose skim; and the shrink-pass design gaps in the
RED-TEAM list (a shrinkable label can still land outside its box;
`shrinkWeight` changes which `ViewThatFits` candidate wins, undefined).

**E2. Owed to the device pass, with the measurement already taken: a vertical
pan that begins on a hosted row still fires that row's `onActivate`.**
RED-TEAM final pass, 2026-08-13 — **recorded, deliberately not fixed**.
`virtual_list.luau`'s `hostedResolveAxis` declines a gesture that resolves
vertical (`pending.declined = true`) and arms nothing, so the `Activated` the
row's `Hit` fires at the end of a scroll pan started on that row reaches
`spec.onActivate`. Measured on the clean-room hosted list
(`tests/virtual_list_row_actions.spec.luau`'s `world` + `dragDown` +
`releaseActivating`, 40px rows): **1 stray activation in all four combinations**
— `dy=20` (release still inside the row rect) and `dy=90`, on both release
orders, with `engagedKey=nil` and no tray action fired. **Unchanged by
`79649d6`**; pre-existing.

**The open premise is the reason it is not fixed from a desk.** Leaving it
unarmed is only correct if a native `ScrollingFrame` drag *cancels* its child
button's `Activated` — in which case the stray cannot happen on a device and any
arm we add would be a suppression that eats real taps. That is the very premise
the **horizontal** branch refuses to rely on (it arms at the axis lock instead),
nothing in the repo tests it, and there is no device evidence for it anywhere.
So the device pass answers one question — *does a real touch pan over a hosted
row fire that row's `Activated`?* — and the code decision (arm on the vertical
resolve too, vs. leave it to the engine) follows the answer. Carried in
`row-actions-hosted-mode-plan.md`'s device-pass riders as item 5. Do not block
round 3 on it.

## Orchestration rules — earned the hard way in round 2

These are about running the mission, not about the code. Each cost real time or
real work.

**A gate that returns no verdict has not run.** Five specialist verifier
dispatches ended on their opening sentence after 30–55 tool calls of genuine
work, producing nothing — while the harness reported `completed`. That converts
a mandatory gate into a no-op with every outward sign it ran. **Redispatch to
`general-purpose` rather than nudging** (the nudge worked once and failed once,
at higher cost each time), put the delivery instruction *in* the brief, and
never close a milestone on a verifier's silence. Full write-up:
[`../lessons/a-specialist-verifier-that-reports-nothing.md`](../lessons/a-specialist-verifier-that-reports-nothing.md).

**Never tell an agent the tree is exclusively its own unless you have just
checked.** Round 2's orchestrator said so while another agent was live in the
same files; that agent hit a filename collision, read the state as corruption,
ran `git checkout`, and discarded ~114 lines of uncommitted work. Two separate
`git checkout` incidents destroyed uncommitted work in one mission. Verify with
`ListAgents` before claiming exclusivity, keep concurrent agents in disjoint
files, and back up to the session scratchpad — never a generic `/tmp` name.

**Do not narrate a plausible story ahead of the data.** The orchestrator twice
described a defect to the director more confidently than the evidence supported
— "the score display is gone" (it rendered correctly at all eleven viewports;
what was lost was its *path*) and "my predicate change caused the Edit button
bug" (the declaration disproved it before any measurement). Both were corrected
by an agent that measured. State the symptom and the hypothesis separately.

**Two device reports can be one cause.** "The Edit button doesn't make rows
editable" and "we lost swipe-to-reveal" were the same complaint: the table
declared no `rowActions`, so edit mode surfaced a reorder handle and nothing
else. Root-cause before splitting work.

**A test can be satisfied by a hidden copy.** A losing `ViewThatFits` candidate
stays mounted with its props and text intact at 0×0 — so an assertion that "a
node at this path has this text" passes against content no player can see. If a
check is about *visibility*, assert a non-zero rect, not presence.

**An instrument nobody runs is a comment.** `check_flat_baseline` caught the
tile-game regression and is not in `./run-tests.sh`; the overflow diagnostic
described nine device bugs in words before they shipped and nothing called it.
When you add a check, decide where it *runs*, not just that it exists.

## The bar, unchanged from round 2

TDD; both suites green; **every new check mutation-proved to bite** — more than
twenty in round 2 did not on the first attempt, and one shipped test was found
pinning a defect as a feature. Four-input proof plus a conformance-registry
entry for new interactive behaviour. Reduced motion decided deliberately and
written down. Text survives 1.4× pseudo-loc. Strict schema, exported types.
RascalRally evidence in the same phase, no game behaviour change without
separate authorization. Milestone gates: fresh-context architecture verifier and
a RED-TEAM pass — round 2's REJECTED the first cut and caught a blocker that
would have shipped.
