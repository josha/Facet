# Large-text accessibility — decision packets (LTN-*)

## LTN-1 — the exact authority seam (DECIDED 2026-08-03, probe-backed)

Measured (artifacts/large-text-accessibility/probe/preference-probe.json):

- The engine paints every text node at `TextSize + offset(preference)`, where the
  offset is a per-preference CONSTANT — Medium=0, Large=4, Larger=10, Largest=14 —
  identical across font, weight, and size (built-ins and theme fonts).
- `GetTextBoundsAsync` does NOT include the preference (answers for the literal
  requested size at all four values). This refutes the 2026-07-23 grounding.
- `GetTextSizeOffsetAsync` returns the exact constant; the change signal fires
  reliably; existing labels re-wrap by themselves on a change.
- `TextScaled` text is preference-independent (engine fits the box).
- The official announcement names a SECOND opt-out this stage does not touch:
  a `UITextSizeConstraint.MaxTextSize` caps the scaled size (platform review
  F5). LuauUI emits no `UITextSizeConstraint` anywhere (grep-verified), so the
  offset model holds for every node the framework paints; a future control
  that adds one must revisit this rule.

Decision: `preferredTextOffset` stays ONE additive px env fact applied exactly
once at the solver's measure seam (`size*scale + offset`); paint never carries it.
The live adapter (src/client/roblox_env.luau + src/client/preferred_text.luau)
applies a measured fallback table synchronously, confirms each preference once
through the yielding lookup (cached, failure-safe, stale-safe, never loops), and
subscribes to the change signal. The renderer's existing `preferredTextOffset`
watch makes a change one atomic re-solve — never a remount. The injectable
multiplier seam (`preferredTextSize`) stays test/profile-only; the two
authorities never overlap. Premeasure/calibration are preference-independent, so
measuring words at the inflated size is EXACT; the double-application belief is
retired with the wrong grounding comments.

## LTN-2 — engaged reveal (marquee): NOT SHIPPED (DECIDED 2026-08-03)

The plan's overflow ladder ends "animate only as an engaged last resort". The
last resort is not needed: full-value access for permitted truncation ships as a
STATIC engaged disclosure (below), which

- works identically for pointer (hover dwell), keyboard/gamepad (focus), and
  touch (long-press) — every applicable input class;
- is reduced-motion-equivalent BY CONSTRUCTION (nothing moves);
- creates zero per-frame work and zero moving text surfaces (the moving-label
  diagnostic ships with an allowed maximum of 1, so a future reveal cannot
  proliferate silently);
- preserves self-paced reading and backtracking, which a travelling reveal
  structurally cannot.

A horizontal engaged reveal remains a possible future addition behind the same
engagement affordance; if it is ever proposed, the plan's full constraint list
(delay, reading direction, grapheme boundaries, pause-at-ends, static
alternative, reduced-motion, one-at-a-time, no per-label frame loops) binds.
Rapid serial visual presentation (character/word replacement) stays a separately
approved opt-in research question, per the plan.

## LTN-3 — Sponsor truncation-rule corrections (recorded 2026-08-03; more added
as the fixture sweep finds them)

1. **S16.13 "what truncates" purged of essentials** (spec corrected in place):
   countdown (status), coin total/gain (result facts), CTA label (action), and
   section heads left the truncation list. Countdown owns the masthead centre;
   coin totals reserve to measured content; CTA labels reflow via the
   ViewThatFits column candidate and composition step-down; section heads wrap
   to 2. The spec's own §8 Step 8.5 ruling already forbade all four; the S16.13
   line predated it and was never reconciled.
2. **§8 one-line truncation list corrected**: position numerals, the watched
   position, and lap text are required facts — their boxes reserve to measured
   content at every preference. Identity labels (racer/standings/watched names,
   ticker target, card caption) remain one-line truncatable WITH the full value
   reachable (disclose).
3. **Live observed** (probe session): the production role-pick secondary CTA
   truncated at Largest ("Sponsor a…") — an action label behind game-local
   box-fit math blind to the paint offset. Fix tracked in the consumer-impact
   ledger (framework-owned offset-aware fit).

**Antecedent lines for the negative greps** (phase-gate review F11 — the spec
folder is not under git, so the pre-correction text is recorded here verbatim):

- S16.13 before: `What truncates: standings name,` / `seat name, countdown,
  coin total/gain, CTA label, section heads.` → after: `What truncates
  (identity only, full value reachable per §8's Step 8.5 ruling): standings
  name, seat name.`
- §8 before: `**Truncates (one line, ellipsized):** racer row name, position
  numeral, ticker target name, watched-racer name and position, card caption,
  lap text, standings row name.` → after: the identity-only list with position
  numerals, the watched position and lap text moved to reserve-to-fit.

## LTN-8 — the auto reveal SHIPS for declared surfaces (DECIDED 2026-08-04,
supersedes LTN-2's "not needed" for exactly the nodes that declare it)

Director ruling (finish-screen recap, verbatim): "the text row on the finish
screen likely will need to scroll on narrower screens horizontally — make it
auto-scroll/animate vs being a scrollbar." The recap's REDUCED form is a
non-interactive span (recorded finding E·3): disclosure's engagements cannot
reach it on every input class, raising its line budget makes the composition
report NO legal arrangement at 635x233, and a scrollbar was refused by name. So
the ladder's rung 4 ships, as the smallest public mechanism:
`UI.Text{ reveal = "auto" }` — construction-only, Text-only, inert while the
text fits. "auto" names the UNENGAGED variant the ruling ordered (the surface
presenting IS the engagement); an engaged variant remains a possible future
enum value.

LTN-2's full constraint list, line by line:

- **Start delay** — the cycle rests in the engine's own ellipsis for 1.2 s
  before anything moves (and between cycles, and at the end pose).
- **Reading direction** — the strip travels LEFT, revealing the tail. The
  framework carries no RTL fact today; when one lands, the travel sign reads it
  in one place (presenter stepReveal).
- **Grapheme boundaries** — structural: the whole string travels as ONE strip
  at the solve's own `naturalWidth`; it is never re-segmented, and the resting
  paint is the engine's own ellipsis. The strip's clipped edges crop moving
  glyphs exactly as any scroll region does — the constraint forbids BREAKING
  the string, not clipping a moving edge.
- **Pause-at-ends** — the tail holds 1.2 s fully shown (travel == distance,
  pinned), then the return leg ends back in the ellipsis rest.
- **Static full-value alternative** — a reveal node is ALSO a disclosure
  source: the renderer wires the same engagement zones, the LTN-4 plate
  answers, and a live plate for the label OUTRANKS the travel.
- **Reduced motion** — travel never starts; a mid-flight flip retires the strip
  on the next tick. The plate remains the full-value path. (For the recap's
  keyboard-only + reduced-motion corner the full value also lives in the wider
  arrangements' wrapped form — the reduced form is a narrow-viewport pose.)
- **One at a time** — one strip across every surface, topmost-first, document
  order; `presenter.movingText()` feeds `text_audit.movingText`, allowance 1.
- **No per-label frame loops** — the presenter's ONE tick drives the cycle; an
  idle presentation pays a 0.5 s timer-gated rescan behind a per-surface
  `hasReveal` stamp; a live strip costs one signal write per frame.

Mechanism (the disclosure plate's own architecture): presenter-private overlay
(`__reveal__`), a `clipChildren` window fixed at the source label's rect, the
full string inside at `textFacts.naturalWidth` (recorded by the SAME measure
pass as the truncation verdict — never a second opinion), travel as one anchor
offset signal. While the strip covers the source, the source's own paint is
held via the new `controller.setPaintHeld` (presentation-layer only: solve,
rects and facts untouched, so the target stays "truncated" and the audits stay
honest; the hold survives re-solves and remounts and dies with the surface).
Speed is a GLYPH rate (3 glyphs/s × 0.62 em × the offset-inclusive measured
size), so a raised preference reads at the same pace instead of racing bigger
glyphs. Facts channel: `policy = "truncate+reveal"`, `reveal`, `naturalWidth`;
`clippedEssential` accepts a reveal path as full-value access.

Proof: tests/text_reveal.spec.luau (14 pins: declaration/enum, facts, the full
cycle with maxTravel == distance, fits/undeclared negatives, re-solve retire,
HIDDEN-mid-flight retire (found LIVE at the Medium drive — a losing arrangement
candidate keeps its facts, so the tick verify re-reads `hiddenRoots` exactly as
it re-reads the facts), dismiss retire, reduced-motion both ways, one-strip +
audit rule, plate-outranks-strip). Rapid serial visual presentation stays out,
per the plan. Live-verified in the production RR place at real Medium AND
Largest, 2026-08-04 (evidence in this stage's consumer-impact.md).

## LTN-5 — the matrix's found gaps: fix shapes (DECIDED 2026-08-03)

The headless matrix (LT-8 build) surfaced three framework gaps; dispositions:

- **LT-G1 (Toggle label)** — the one-line label form STAYS (it is measured,
  director-signed design: wrapping plus the press-scale affordance produced
  mid-word breaks — "Musi/c"). The ladder is satisfied by giving the Toggle the
  full-value path instead: `UI.Toggle.disclose` (construction-only) rides the
  same textFacts/plate contract as `Text.disclose`, class-agnostic in the
  presenter walker and the adapter zone wiring.
- **LT-G2 (control-owned labels)** — `Table` columns gain `disclose: boolean?`,
  stamped on the table-authored value cells and the header title. A custom
  `cell`/`cellFor` blueprint keeps declaring disclose on its own Text. Granular
  by column on purpose (identity columns disclose; numeric columns never).
- **LT-G3 (pinned rowHeight)** — pinned px row heights remain preference-blind
  BY CONTRACT: an authoring rule (documented in api.md) — pin only what clears
  `(textSize + 14) * lineHeight`, or stay unpinned (the default row box
  composes the offset). The clippedEssential check catches violations.
- **Diagnostics hole** — `text_audit.outOfBounds(rects, bounds, opts)` added
  (the plan's "leaving their declared bounds" check): unclipped content past
  the declared bounds is a finding; declared `scrollHosts` descendants are the
  legal escape.

## LTN-4 — full-value disclosure contract (DECIDED 2026-08-03)

The smallest public mechanism, per the constitution:

- `UI.Text` gains ONE construction-only prop: `disclose: boolean?` (default
  false/absent). Declaring it says "this is bounded secondary/identity text;
  when it truncates, the framework owes the reader the full string". It is legal
  on any Text; it does nothing while the text is not truncated.
- The presenter owns the affordance (screens declare, never implement): when a
  disclosed Text is truncated, engaging it presents a STATIC full-value plate —
  hover dwell (pointer), focus enter (keyboard/gamepad focus on the containing
  focusable), long-press (touch). Disengaging (leave/blur/release/tap-away)
  dismisses it. At most ONE disclosure plate is live per presenter at a time.
- The plate is presentation chrome: non-focusable, non-interactive, never in the
  focus order, painted above content, anchored near the source node, clamped to
  the safe viewport, themed through the active ThemeSnapshot. No motion is
  required for it to appear or leave (reduced-motion parity is structural).
- The dump reports, per text node: effective preference/offset, font descriptor
  and role, natural/actual bounds and line counts, truncation state, the chosen
  overflow policy, and how the full value is reached ("none" | "disclose").
  Truncated + no full-value path is a diagnostic finding unless the node is
  declared flavour (`disclose` absent AND the audit caller lists it as
  non-essential — the audit takes a declared allowlist so the crude global check
  cannot false-fail intentional cases).


## LTN-7 — fresh-context review dispositions (2026-08-03)

Three independent reviews ran at stage close (platform, architecture,
phase-gate). Every BLOCKER/MAJOR was FIXED same-session and pinned by a named
test: the confirm-cache epoch guard (stale answers discarded, never cached),
ceiling answers clamped up instead of discarded, the two-face max confirm,
same-finger touch filtering + Destroying defusal in enableDisclosure, the
hidden-candidate disclosure gate, dwell re-ask at expiry, `enableDisclosure` on
the render-target OPTIONAL contract, strict Table column / text.fit boundaries,
and the capability-flip retrofit for disclosure zones. Recorded-not-fixed (each
with rationale): the long-press-also-activates side effect on touch (observing
input never sinks it; the engine TouchLongPress + gesture-arbiter route is the
follow-up — judged on the phone pass), the plate-over-source hover-flicker
hypothesis (unverified occlusion semantics; one Studio look owed), the
mount-time-only gating shared with enableHover for classes that VANISH (arrival
is retrofitted; removal leaves inert zones, matching hover's shipped rule), and
the legacy racer item HUD's missing preferred-text seam (consumer ledger §C
follow-up). The public-surface drift that reddens the code-simplicity-cleanup
prior gate is v0.7→v0.8 API-stage growth, not this stage's regression; its
check is corrected to pin what that stage actually promised (no REMOVALS from
its frozen surface) with current-surface governance owned by the
api-architecture-consistency surface ledger.
