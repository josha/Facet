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
   executed at all. And `examples/places/LuauUI-PerformanceLab.rbxl` exists,
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
(`UIListLayout.Wraps`) remains, and LuauUI is behind the native controls until
it lands.** It is a real arrange branch: line breaking, per-line cross extent,
and a cross-axis line-distribution rule Roblox does not define — so we must.
Interacts with incremental layout, instance recycling and virtualization, each
with live budgets. See `swiftui-parity-round2.md` §2.7.

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

**E. Owed from round 2** — the full list is in `swiftui-parity-round2.md` and
`device-bug-round-2026-08-12.md`; the load-bearing ones: the Studio device
canary on the rebuilt showcase; the `traversal-document-order` re-record (that
gate is honestly RED); the chrome restructure (chrome is unreachable without a
pointer — `[SHOWCASE-CHROME]: CONCERNS 16`); the reduced-motion settings
surface; `api.md`'s round-2 prose skim; and the shrink-pass design gaps in the
RED-TEAM list (a shrinkable label can still land outside its box;
`shrinkWeight` changes which `ViewThatFits` candidate wins, undefined).

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
