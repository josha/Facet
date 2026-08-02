# Modal outside-tap dismissal — best-practice survey, two-region verdict, and presenter spec

Date: 2026-07-21 · Author: UI Designer · Status: **spec for director ruling** (not yet built)
Commissioned by: game director · Feeds: `src/present/presenter.luau` (outside-tap path,
`onNodeTap`), a follow-up ADR to `ADR-0014` §Drive-F1, `docs/guide/07-input.md` §7.2.
Related: `ADR-0013` (modal outside-tap dismiss, `outsideTapCancel`), `ADR-0014`
(first-responder / passive-engaged resign-on-outside-tap), `contract.luau` (`minHitSize = 44`),
`tokens/default_style.luau` (`scrimOpacity = 0.45`, `space.l = 24`).

---

## 0. ELI5 (for the director, plain language)

When a pop-up (a "modal") is open, tapping *off* it usually means "never mind, close it."
Today that only works if your finger lands on some other button behind the pop-up; tap the
empty black nothing beside it and the game shrugs. That is the bug from the Studio drive
(`ADR-0014` Drive-F1).

The director's fix idea: think of the screen as two zones. **Zone A** is the pop-up itself
(and a little forgiveness ring around it, so a near-miss doesn't nuke it). **Zone B** is
everywhere else. Tap Zone A → nothing bad happens. Tap Zone B → close the pop-up.

This spec says: **that model is right**, with one precise correction about *what Zone A is
made of* (the pop-up's visible panel, not an invisible box that might secretly cover the whole
screen), and it gives the builder exact numbers: a full-screen dim sheet behind every modal
that catches the "empty nothing" taps, a 24 px forgiveness ring, and one iron rule —
**tapping outside must always land on the SAFE choice, never the dangerous one.**

---

## 1. Best-practice survey (touch · pointer · gamepad)

The single organizing finding across every platform: **outside-interaction dismissal is only
safe when "dismiss" resolves to the non-destructive / cancel outcome.** Every platform that
allows outside-tap-to-close also guarantees it discards nothing dangerous. The platforms
diverge on *which modal kinds* opt into it, and that divergence is the design signal.

### 1.1 Apple (touch + pointer)

| Modal kind | Outside tap | Why |
|---|---|---|
| **Nonmodal popover** | **Dismisses** | Light-dismiss. HIG: people can *unintentionally* dismiss a nonmodal popover, so **"always save work when automatically closing… discard work only when people click or tap an explicit Cancel button."** |
| **Modal popover** | Dismisses; other views disabled while up | "When a popover is visible, interactions with other views are normally disabled." (a true barrier) |
| **Action sheet** (`.actionSheet`) | **Dismisses = Cancel** | Always carries an explicit Cancel; outside-tap is a synonym for the *safe* Cancel row. |
| **Sheet** (`.sheet`, page/form) | Swipe-down / outside dismisses **unless** `interactiveDismissDisabled()` | Default is dismissible; a form with unsaved edits sets `interactiveDismissDisabled(hasChanges)` and instead shows a "Discard Changes?" action sheet. |
| **Alert** (`.alert`, incl. destructive) | **Does NOT dismiss** | "An alert interrupts… requires a tap to dismiss." A destructive confirm forces an explicit button. |
| **Full-screen cover** (`.fullScreenCover`) | No outside exists | Exit is a Close/Cancel control, never an outside tap. |

Load-bearing Apple lesson: **the more destructive the decision, the less the modal relies on
outside-tap.** Alerts (dangerous) require an explicit press; popovers/sheets (recoverable)
light-dismiss, and even then Apple mandates the auto-close outcome be *save*, not *discard*.
([HIG Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers),
[HIG Modality](https://codershigh.github.io/guidelines/ios/human-interface-guidelines/interaction/modality/index.html),
[hackingwithswift: interactiveDismissDisabled](https://www.hackingwithswift.com/quick-start/swiftui/how-to-prevent-a-sheet-from-being-dismissed-with-a-swipe))

### 1.2 Material Design 3 (touch + pointer)

- **Basic / confirmation dialogs dismiss by tapping the scrim** (outside) or the system Back
  button — by default.
- `scrimClickAction` / `escapeKeyAction` can disable that, **but the guideline explicitly
  cautions "it should always be possible for a user to dismiss the dialog."**
- The pattern to copy verbatim: **the Cancel button, the scrim tap, and Escape all map to the
  *same* "dismiss without taking an action" outcome** — three doors, one safe room.
- Material always paints a **scrim** behind a modal dialog (the dim = the barrier + the "tap
  here to close" affordance).
([Material 3 dialogs](https://m3.material.io/components/dialogs/guidelines),
[MDC dialog README](https://github.com/material-components/material-components-web/blob/master/packages/mdc-dialog/README.md))

### 1.3 Desktop (pointer + keyboard)

- **Popovers / menus / comboboxes / date-pickers**: *light dismiss* — click-away closes them
  (macOS, Windows flyouts). Cheap, recoverable, non-destructive.
- **Modal dialogs (esp. destructive/OK-Cancel)**: clicking the greyed backdrop typically does
  **nothing** (or beeps); you must choose a button. `Esc` = Cancel, `Enter` = default.
- Rule of thumb desktop teaches: *transient/contextual → click-away; decision/dialog →
  explicit.*

### 1.4 Console / TV / gamepad

- There is **no pointer and therefore no "outside tap."** The entire two-region model is a
  **touch + mouse concept only.**
- The universal grammar is **B / Circle = Cancel = back out one level**, plus an on-screen
  focusable Close/Cancel, plus A/Cross to activate the focused choice. This is exactly what
  LuauUI already binds (`cancel.bind ButtonB`; Escape is engine-reserved, `07-input.md` §7.4).
- Consequence for this spec: **gamepad behavior does not change at all.** Whatever we decide
  about scrims and forgiveness rings, the pad still cancels with B and the region math is
  simply not consulted.

### 1.5 Touch-accuracy / forgiveness research

- The finger contact patch is ~7–10 mm; Apple's 44 pt and Material's 48 dp minimum targets
  exist because the *centroid* of a touch lands with roughly ±half-a-target of slop. LuauUI
  encodes this as `minHitSize = 44` (`contract.luau`) — every Button/Toggle/TextField already
  gets a 44 px effective hit rect that may exceed its visual rect.
- The relevant forgiveness for *dismissal* is the mirror of target forgiveness: a tap aimed at
  the panel edge that lands a few px outside should be read as "meant for the panel," not as a
  destructive outside tap. A near-miss that does **nothing** is strictly safer than a near-miss
  that closes (or, worse, that reaches a button behind the modal).
- **Verdict from the research:** a small forgiveness ring is justified *specifically because
  outside-tap-dismiss is an un-undoable, context-destroying gesture with no confirmation* — the
  one place the studio's own touch-slop reasoning should also protect the *boundary*, not just
  the targets.

### 1.6 What modal KIND should modulate the default

Synthesizing 1.1–1.4, modal kinds fall into two families, and **kind should set the default**:

| Family | Examples | Outside-tap default | Rationale |
|---|---|---|---|
| **Light / recoverable** | popover, action sheet, bottom sheet, info panel, picker | **dismiss ON** | Cheap to reopen; dismiss = the safe/cancel outcome. |
| **Decision / confirm** | destructive confirm (example 04), required consent, form with unsaved input | **dismiss ON *iff* dismiss = the safe outcome; otherwise OFF** | Never let a stray tap perform or skip the dangerous thing. |

The nuance in row 2 is the whole game (see §3.5): a destructive **confirm** *should* default to
outside-dismiss, because in LuauUI dismissing runs neither button — it just closes, leaving the
dangerous action **not taken**. A form with **unsaved input** should default outside-dismiss OFF
(or intercepted), because there the safe outcome is not "close," it's "keep my edits."

---

## 2. Verdict on the director's two-region model

**The two-region model is CORRECT and matches platform convention — with one precise
correction and two additions.** Endorsed as the framework default, refined as follows.

### 2.1 The correction: define Zone A geometrically (painted panel), not by blueprint path

The director's own hazard is real and is the crux. Today the presenter decides "inside vs
outside" by **path prefix** (`isPathPrefix(surfaceRoot, path)` in `onNodeTap`): a tap on any
node whose path descends from the modal's Screen root counts as inside. That works only because
today's modal Screen roots are **content-sized** — the solver sizes a non-`fill` root to its
measured content and pins it to the top-left of the safe area (`solver.solve`: `rootW = if fill
then contentRect.w else min(measured, contentRect.w)`; example 04's dialog is a tight panel, no
scrim). So the modal's path-region *happens* to equal its visible panel.

But if an author declares a **`fill` Screen root with a transparent background** and a small
visible panel inside it, the modal's path-region silently spans the whole viewport — and a
path-based Zone A would **swallow every tap, so nothing ever dismisses.** That is exactly the
director's worry, and it is a live footgun.

**Resolution — Zone A is the union of the modal's *painted* rects, never its path envelope:**

> **Zone A (no-dismiss)** = ( the modal's outermost **visible** panel rect ⊕ a forgiveness
> margin ) ∪ ( every focusable descendant's effective 44 px hit rect ). An **invisible /
> transparent** container contributes **nothing** to Zone A even if it geometrically covers the
> screen — only painted surface counts.

This dissolves the footgun by construction: a transparent `fill` root paints nothing, so it
adds nothing to Zone A; only the real panel does. And it correctly handles the *legitimate*
fullscreen case — a **visible** viewport-filling panel (a takeover dialog) makes Zone A the
whole screen, which is right: a fullscreen dialog *has no outside*, and its exit is a Close
button (Apple `.fullScreenCover`, §1.1). So "root spans everything" is only a bug when the
root is *invisible*; the painted-rect rule turns it into correct behavior in both branches.

**Doctrine that keeps this simple (the recommendation): a modal blueprint is the PANEL; the
presenter owns the backdrop.** Authors size modal roots to content (as example 04 already
does) and never hand-author a full-viewport scrim. The presenter synthesizes the backdrop
(§2.2). This is principle-1 (simplest thing that works) and it means Zone A is *always* just
the panel + ring, and the geometric rule above is the safety net for authors who don't comply.

### 2.2 First addition: Zone B is a presenter-synthesized full-screen scrim/catcher

"Everywhere else" must be a real, tappable thing, or empty display space keeps doing nothing
(Drive-F1). **The presenter synthesizes one full-viewport node beneath the top modal** — the
**scrim/catcher**:

- Full viewport (`edgeToEdge`), z-ordered **above every lower surface but below the top
  modal's panel**.
- Owns a presenter-private path **not** under any modal's blueprint root (so the existing
  "outside if not a modal descendant" test classifies a tap on it as *outside*).
- **Not focusable** (absent from the focus walk — it is neither `Button/Toggle/TextField` nor a
  focusable Grip), so gamepad/keyboard navigation never lands on it and §1.4 is preserved.
- Renders with `surface = "scrim"` (already supported: `screen_target.luau` dims a scrim Button
  at `scrimOpacity`) at the token opacity, or fully transparent when the modal opts for no dim
  (a lightweight popover) — **transparent but still catching.**

With the scrim present, **every** tap now hits *something* (scrim or panel), so `onNodeTap`
always fires and the empty-space gap is closed. The scrim doubles as the **modal barrier**
(blocks interaction with lower surfaces — Apple's "other views disabled," Material's scrim) and
as the **affordance** that a region B exists.

### 2.3 Second addition: the safety invariant that makes it all sound

From §1.1/§1.2, one rule governs correctness and must be stated in the spec and the guide:

> **Outside-tap, Cancel (B), and the Close button MUST all resolve to the same
> non-destructive outcome.** A modal where dismissing performs or skips a dangerous or
> data-losing action MUST set `outsideTapCancel = false` (and typically supply an explicit
> Cancel), OR intercept dismissal to confirm (the "Discard changes?" pattern, §4).

### 2.4 The two regions, precisely, in LuauUI terms

- **Zone A — no dismiss (forgiveness):** ( outermost painted panel rect **⊕ 24 px forgiveness
  margin** ) ∪ ( each focusable's 44 px effective hit rect ). A tap here that is *not* on an
  interactive target does nothing (a benign near-miss); a tap on a target activates it. Never
  dismisses.
- **Zone B — dismiss:** the synthesized full-viewport scrim/catcher (everything not Zone A). A
  tap here dismisses the top modal (if `outsideTapCancel`) or is swallowed (if not), and
  **never** clicks through to a lower surface.

---

## 3. The concrete spec for the presenter

Engine-free; all values are tokens/LuauUI px. This refines the `onNodeTap` outside-tap path and
adds the synthesized scrim. Gamepad/keyboard paths (`cancel.onPressed`, focus walk) are
unchanged.

### 3.1 Synthesized scrim/catcher (per top modal)

- On `presentModal`, the presenter mounts a presenter-owned **scrim node** as the modal handle's
  first sibling in z: full viewport, `edgeToEdge`, path e.g. `"/__scrim__<modalId>"` (outside
  every blueprint root).
- Paint: `surface = "scrim"` at `scrimOpacity` (token, default **0.45**) when
  `scrim ~= "none"`; fully transparent when `scrim = "none"` (still catches).
- Not focusable; not in the contribution walk; disposed with the modal.
- Stacked modals: exactly **one** scrim, belonging to the **top** modal, re-parented as the top
  changes. Only the top modal has a live scrim/catcher (matches iOS one-at-a-time light
  dismiss).

### 3.2 Hit-region rules (the numbers)

- **Forgiveness margin = `space.l` = 24 LuauUI px** around the panel's painted rect. Chosen as
  ≈ half the 44 px hit floor (22 px) rounded up to the existing grid step — the same touch-slop
  logic that sets `minHitSize`, applied to the boundary. It is a **token**, not a literal, so a
  game can retune it; it collapses to a smaller value on precise-pointer-only environments is
  **not** done (keep it uniform — see §3.3).
- **Interaction with the 44 px hit floor:** the two do not double-count. Edge buttons already
  inflate to 44 px and may spill slightly outside the visual panel; those spilled hit rects are
  part of Zone A by the union. The 24 px panel-margin extends Zone A a bit further at the *panel
  background* edge for the non-button gaps. Where a button's 44 px spill exceeds 24 px, the
  button's rect governs (union = max). Net: **Zone A ≥ the panel inflated by 24 px, and ≥ every
  target inflated to 44 px.** No dead sliver between them.
- **Resolution test on a tap:** if the tap point ∈ Zone A → not outside (activate-or-nothing);
  else → outside (§3.4). Implemented as a geometric point-in-rect test over the modal's solved
  rects (the presenter already holds `controller.rectOf`), *replacing* the pure path-prefix test
  for the dismiss decision. (Path prefix is retained only as the cheap fast-path for taps that
  land squarely on a modal descendant node.)

### 3.3 Per-input behavior

- **Touch and pointer: identical geometry.** Same Zone A/B, same 24 px ring. Pointer is precise
  so the ring is essentially never exercised by a mouse; keeping it uniform avoids a
  device-branch and is harmless (a mouse user practically never lands in the ring). This honors
  "one spec, all devices."
- **Gamepad: unchanged.** No outside-tap concept; **B / Circle cancels**, the focus ring +
  Close button remain the exits. The scrim is non-focusable, so navigation cannot reach it. The
  region math is never consulted on a pad.
- **Keyboard: unchanged.** No pointer; Escape is engine-reserved; exit is the focusable Close
  button (Return/A) or B. The scrim is not a keyboard target.

### 3.4 Outside-tap outcome (Zone B), gated by `outsideTapCancel`

- `outsideTapCancel = true` (default): dismiss the **top** modal only; **never** click through
  to a lower surface.
- `outsideTapCancel = false`: **swallow** the tap — no dismiss, **no clickthrough.** This is a
  deliberate change from today's code path, whose comment lets an `outsideTapCancel = false`
  outside tap "fall through to legacy routing" (i.e. reach the lower surface). A modal is a
  barrier; a decision modal that declines outside-dismiss must still block the world behind it
  (Apple "other views disabled," Material scrim). The synthesized scrim makes this correct by
  construction — it catches and eats the tap.
- Either way, a tap in **Zone A** on a non-target does nothing; on a target, activates it.

### 3.5 Stacked modals

- Each additional modal pushes its own scrim above the modal below it; only the **top** modal's
  scrim is live. A tap outside the top modal — whether on empty space *or on the visible panel
  of the modal beneath* — dismisses **only the top** modal (one level per tap), matching iOS
  stacked-sheet light dismiss and today's "never clickthrough" guarantee. B likewise pops one.

### 3.6 `responder = "passive"` engaged surfaces (ADR-0014)

The same machinery already governs an engaged-from-passive surface's outside-tap → **resign**
(not dismiss). Apply §3.1–3.4 identically, with two deltas: (a) an engaged HUD surface usually
wants **no dim** — default its scrim to `scrim = "none"` (transparent catcher) so the game world
stays fully visible while the surface is merely first responder; (b) outside-tap **resigns**
(back to passive), it does not dispose. The 24 px forgiveness ring applies so a near-miss beside
an engaged HUD panel doesn't kick it out of first-responder mid-interaction.

### 3.7 Confirm-style dialogs: the default + opt-out (recommendation, not a menu)

**Default: destructive *confirm* dialogs (like example 04) DEFAULT to `outsideTapCancel = true`
(outside-tap dismisses).** Rationale, decisive: in LuauUI `presenter.dismiss` runs **neither**
button — it just closes — so an outside tap on example 04 leaves `result` at `"none"`: the
delete **does not happen.** Outside-tap therefore already maps to the *safe* outcome, satisfying
the §2.3 invariant, and matches Material (dialogs scrim-dismiss by default) and Apple action
sheets (outside = the safe Cancel). Forcing users to hunt for a Cancel button when a tap-away
already means "never mind" is friction with no safety benefit *here*, because here dismiss is
safe.

**Opt-out (`outsideTapCancel = false`) is required only when dismissal is NOT the safe
outcome**, i.e.:
1. A modal where closing-without-choosing itself performs or commits something dangerous
   (rare; usually a design smell — reshape so dismiss = safe).
2. A **form with unsaved input**, where the safe outcome is "keep editing," not "close." These
   should set `outsideTapCancel = false` **and** intercept the exit to confirm (§4) — the iOS
   `interactiveDismissDisabled` + "Discard Changes?" pattern.
3. A **required** gate (legal consent, mandatory selection) with no valid "no choice" state.

Stated as one rule: **default outside-dismiss ON; opt OUT only where dismiss ≠ safe.** This is a
single default with a single, testable exception, not a per-screen menu.

---

## 4. Accessibility & expectation notes

- **Mis-tap forgiveness.** The 24 px ring (§3.2) is the boundary mirror of the 44 px target
  floor: a near-miss beside the panel does nothing rather than destroying context. This is the
  accessibility win for motor-imprecision and one-handed thumb use (the studio's stress case is
  the iPhone-mini thumb reach) — the destructive gesture (dismiss) is the *hardest* to trigger
  by accident, exactly inverting the usual "big target" logic because here the "target" is the
  danger.
- **Scrim affordance — recommend a VISIBLE scrim whenever outside-dismiss is ON.** The dim is
  the only signal that region B exists and is tappable; an invisible-background modal that
  silently dismisses on outside tap is undiscoverable and makes empty-space taps feel like dead
  zones. Recommendation: **default `scrim` to the 0.45 dim for `presentModal`** (barrier +
  affordance + focal-plane separation, principle 2 "one focal plane at a time"); allow
  `scrim = "none"` only for transient popovers/engaged HUDs where the world must stay visible —
  and where the panel's own elevation (`overlay` shadow) supplies the "this floats, tap off to
  close" cue instead.
- **Accidental dismissal of forms with unsaved input.** Follow SwiftUI/UIKit/Material:
  SwiftUI `interactiveDismissDisabled(hasChanges)` / UIKit `isModalInPresentation`, and
  Material's disable-scrim-click — all block the casual dismiss *and* substitute a "Discard
  changes?" confirmation rather than silently eating data. LuauUI's equivalent: a form modal
  sets `outsideTapCancel = false` and, on an attempted exit (B or a Close press), presents a
  small confirm modal ("Discard changes?" → Discard / Keep editing). The framework guarantees
  the *barrier* (§3.4 swallow); the *discard-confirm* is a consumer composition the guide should
  show as the canonical unsaved-input recipe. This keeps the §2.3 invariant intact: the
  low-effort gesture always resolves to the safe outcome ("keep editing").
- **Contrast / reduced motion / color.** The scrim is a dim of the `surface` token at
  `scrimOpacity`; it is decorative and carries no text, so it faces no 4.5:1 gate. Its
  appear/disappear rides the `normal` motion token (fade), which already collapses correctly
  under reduced motion. Dismissal is never signaled by color alone — the scrim's presence + the
  panel's disappearance are the signal.

---

## 5. Summary for the director

- **Two-region model: VALIDATED**, with one correction and two additions.
- **Correction:** Zone A ("no-dismiss") is the modal's **painted panel rect + a 24 px
  forgiveness ring + its buttons' 44 px hit rects** — a **geometric** region, **not** the
  modal's blueprint-path envelope. This directly defuses the "invisible root spans the whole
  screen and swallows every tap" footgun (an invisible container contributes nothing; a
  *visible* fullscreen panel correctly has no outside).
- **Addition 1:** the presenter **synthesizes a full-viewport scrim/catcher** beneath the top
  modal — this is "everywhere else," it closes the Drive-F1 empty-space gap, and it doubles as
  the barrier and the affordance. Default dim `scrimOpacity = 0.45`; `scrim = "none"` for
  transparent-but-catching popovers/HUDs.
- **Addition 2 (the safety invariant):** outside-tap, B/Cancel, and the Close button must all
  resolve to the **same non-destructive outcome**; a modal where dismiss would be dangerous or
  lose data sets `outsideTapCancel = false`.
- **Key numbers:** forgiveness ring **24 px** (`space.l`, ≈ half the 44 px hit floor, a token);
  hit floor **44 px** unchanged; scrim opacity **0.45** (`scrimOpacity` token).
- **Per input:** touch = pointer (identical geometry); **gamepad/keyboard unchanged** (B
  cancels; no outside-tap concept; scrim non-focusable).
- **`outsideTapCancel = false`** now **swallows** the outside tap (true barrier), instead of
  today's fall-through-to-clickthrough.
- **Confirm dialogs (example 04): DEFAULT outside-dismiss ON** — because in LuauUI dismiss runs
  neither button, so tap-away = the safe "do nothing." Opt OUT only for unsaved-input forms and
  genuinely-required gates, which additionally use the "Discard changes?" intercept.

**Artifact:**
`/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/LuauUI/docs/research/2026-07-21-modal-dismissal-spec.md`

## Sources

- [Apple HIG — Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers)
- [Apple iOS HIG — Modality](https://codershigh.github.io/guidelines/ios/human-interface-guidelines/interaction/modality/index.html)
- [Apple iOS HIG — Action Sheets](https://codershigh.github.io/guidelines/ios/human-interface-guidelines/ui-views/action-sheets/index.html)
- [Material Design 3 — Dialogs guidelines](https://m3.material.io/components/dialogs/guidelines)
- [Material Components Web — dialog README (scrimClickAction)](https://github.com/material-components/material-components-web/blob/master/packages/mdc-dialog/README.md)
- [Hacking with Swift — interactiveDismissDisabled](https://www.hackingwithswift.com/quick-start/swiftui/how-to-prevent-a-sheet-from-being-dismissed-with-a-swipe)
- [Sarunw — disable swipe-to-dismiss sheet](https://sarunw.com/posts/swiftui-interactive-dismiss-disabled/)
</content>
</invoke>
