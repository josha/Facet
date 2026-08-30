# ADR-0035 — The player asked for opaque backgrounds, and Facet has exactly one background to make opaque

**Date:** 2026-08-15
**Status:** Accepted
**Number:** 0035, not 0031. `ADR-0031` is a burned number — [ADR-0032](ADR-0032-nested-instance-tree.md)
records that two agents claimed it in live source in the same week and neither wrote
the file. This one was claimed by creating the file before anything else was written.
**Companions:** [ADR-0029](ADR-0029-leaf-opacity-refusal.md) (the leaf-fade refusal,
whose Decision 2 rule is the instrument used below), [ADR-0026](ADR-0026-authored-presentation-composition.md)
(the authored presentation terms this deliberately does not touch),
[ADR-0018](ADR-0018-native-stylesheets.md) / [ADR-0019](ADR-0019-theme-packages.md) §4
(native stylesheet ownership), `docs/lessons/the-base-term-is-destroyed-by-composing.md`,
`artifacts/adr-0035-preferred-transparency/live-probes.md` (every number below).
**Closes:** owed row **O-26** of that stage's owed ledger, which is archived
with its gate evidence rather than carried in the maintained tree. What the row
asked for is stated in full below, so this record stands without it.

## Context — a first-class signal with no reader

`GuiService.PreferredTransparency` is the player's **Background Transparency**
setting: a 0–1 scalar, 1 meaning "paint what the designer said" and 0 meaning "I want
opaque backgrounds". Facet has read it into the `preferredTransparency` fact since
the native-substrate stage, derives `effectiveTransparency` from it, clamps garbage
readings into the legal domain, and fault-tests that clamp.

And **nothing painted with it.** Round 3's completeness audit rowed it *Partial* and
`owed.md` row O-26 left it open on purpose, because the only demo available would
have been consumer code honouring the preference by hand — advertising a capability
the framework did not have. The director ruled on 2026-08-15: make our painting
honour it.

This is the same shape as the `setReducedMotion` repair (C1, 2026-08-12), and that
repair's own comment is the warning this ADR is written under:

> *"A construction-time opt four call sites forgot is the defect; the repair is that
> the framework pushes the fact instead of hoping a consumer wires it."*

## Decision 1 — the scope is a measurement, not a taste call

The tempting edit is "multiply every transparency in the framework by the
preference". It is wrong twice over, and neither reason is aesthetic.

**The platform names the scope.** The setting is called *Background Transparency* in
the menu the player moves it in, and Roblox's own reference page states the recipe:
*"Multiplying a UI element's `BackgroundTransparency` with `PreferredTransparency` is
the recommended approach, such that backgrounds become more opaque as
`PreferredTransparency` approaches 0."* Roblox's worked example does not sweep the
tree either — it tags the elements that mean to be see-through.

**The arithmetic refuses the sweep outright.** In this engine transparency `1` means
*invisible*. Multiplying an invisible background by 0.5 does not make it more opaque;
it makes it **appear**. Facet's class-default rules exist precisely to hold every
`Frame`/`TextLabel`/`TextButton`/`ImageLabel`/`TextBox`/`ScrollingFrame` background at
1 — *"invisible until a surface says otherwise"* is itself sheet-owned — so a blanket
multiply paints a plate behind every label in every tree.

So the audit walked all of it instead. Every partial alpha the framework chooses
lives in four tokens plus three shadow constants; there is not one hard-coded partial
transparency at any write site. The result:

> **`Scrim backdrop` is the only rule in Facet's generated sheet whose
> `BackgroundTransparency` is strictly between 0 and 1**, and the bespoke painter
> mirrors that exactly — of its eight `surface` branches, only `scrim` writes a
> partial value. Every other framework background is already `0` (a surface) or
> already `1` (a class default).

That is the whole scope, and it is one rule. `tests/preferred_transparency.spec.luau`
re-derives that set from a freshly built sheet and asserts it **equals** the declared
patch scope (`sheet_model.PREFERENCE_RULE_PROPS`), in both directions: a new
translucent background reddens, and so does a patch entry with nothing translucent to
patch.

### The refusals, each with its own reason

| not touched | why |
|---|---|
| `disabledContentOpacity` (0.4) | **Semantic.** The alpha *is* the disabled state. Making it opaque deletes an accessibility affordance in the name of an accessibility preference — and it is `TextTransparency`/`ImageTransparency`, straight into ADR-0029's measured trap. |
| `hairlineOpacity` (0.92) | **A border is not a background.** It is a `UIStroke.Transparency` — a line drawn faintly *over* what it sits on. Solidifying it is a contrast change (the separate *Increase Contrast*, which Roblox does not surface), and the player moved a setting named Background Transparency. |
| shadows (0.35–0.75) and the focus glow (0.25) | A shadow that is opaque is a black box, and a glow that is opaque is a rectangle. The alpha there is the mark's identity, not a backdrop something shows through. |
| every background already at `0` or `1` | `0` is unchanged by any multiply; `1` would be **revealed** by one. |
| authored `opacity` / `withAnimation`'s `o` term / transition fades | Decision 2. |

## Decision 2 — the preference sits at the token seam, never on the authored presentation channel

ADR-0026 made `opacity`, `scale` and `rotation` **authored** props folded into the
presentation authority's own write as a second *term*. The obvious-looking home for a
transparency preference is that channel. It is the wrong home, and the reason is the
one the director named: *getting this wrong would make an author's explicit value and
a player's preference fight.*

- An author who writes `UI.ZStack{ opacity = 0.5 }` declared a **number**, not a
  wish. Scaling it means their 0.5 silently is not 0.5.
- Worse, the dominant use of that term is **transitional**: `withAnimation` and
  `render/transitions` interpolate it, and the framework's own toast/modal
  presentations request `fade = true`. A preference folded in there retargets a
  running animation mid-flight.
- And the framework cannot tell an author's *decorative* translucency from an
  author's *transitional* translucency. It can tell for its own decoration, because
  its own decoration is declared as decoration **by name** (`scrimOpacity`) and **by
  role** (`surface = "scrim"`).

> **The rule.** The preference scales translucency the FRAMEWORK declared as
> decorative. It never scales a number an author or an animation is driving.

So it lives one level lower: at the seam between a **theme's decoration token** and
the single writer that paints it. An author is not shut out of it either — `surface =
"scrim"` is public, and a consumer that declares its own backdrop with it is honoured
by the same one writer, measured below.

## Decision 3 — no property changed hands, so the authority manifest does not move

The one-writer rule (`src/render/authority.luau`, "exactly one authority per engine
render property per class") binds hard here, because `BackgroundTransparency` is in
`NATIVE_SHEET_OWNED` and on this platform a second writer is **silent**: an explicit
write defeats the rule, fires no signal, and `GetStyled` returns your own write from
then on (ADR-0029 Decision 1, measured).

**No second writer was added.** In each mode the property already had exactly one
owner, and each of them keeps it:

| mode | the single writer, before and after | what changed |
|---|---|---|
| native sheet | the `Scrim backdrop` **StyleRule** | the value that rule carries |
| bespoke | `screen_paint.applySurface`'s `scrim` branch | the value it writes |

`NATIVE_SHEET_OWNED`, `MANIFEST`, `BESPOKE_INSTANCES` and `SEAM_OWNED` are untouched.

**And ADR-0029 is not re-opened.** That ADR closed *"animate the RULE instead of the
instance"* with two measurements: a rule-property edit reaches `GetStyled` after **3
frames**, and a per-node fade would need one generated rule per faded node. Neither
objection survives contact with a *preference*:

- **3 frames is not a cost for a settings change.** A fade needs the value in the
  frame it paints; a player moving a slider in the pause menu does not.
- **Per-selector is not a limitation here, it is the requirement.** Every backdrop in
  the session must answer the setting identically. ADR-0029 needed per-node and could
  not have it; this needs per-selector and the rule *is* per-selector.

ADR-0029's Decision 2 rule was the instrument that found this home rather than an
exception to it: *"an authored presentation term is offerable when ONE engine
property that no style rule owns expresses it"*. A preference is not an authored term
at all, so the question inverts — and the answer is the one place ADR-0029 never
needed: the rule's own value, moved by the rule's own generator.

## Decision 4 — the framework pushes the fact; a consumer wires nothing

One new optional adapter seam, `setPreferredTransparency(effective)`, declared on
`target_contract`'s optional list beside `setReducedMotion` and pushed by the renderer
from `effectiveTransparency` **at attach and on every change** — the same observation
shape, for the same measured reason. A target without it degrades by name.

One difference is written into both files, because it is the only thing about this
seam that is not a copy: **`setReducedMotion` remembers, this one repaints.** Reduced
motion changes how the *next* transition plays; a transparency preference changes
what is on screen right now, and a player who opens Settings from inside a modal is
looking at the backdrop while they move the slider.

### Where the base comes from, and why it is not the model's

The adapter patches **`activeSheetFor()` — whichever sheet is linked** — not its own
`nativeHandle`. A theme controller relinks every root onto a package sheet *it* built,
leaving the target's handle pointing at a sheet nobody is wearing; a patch through the
handle would succeed, change a real rule, and be invisible. `native_style` therefore
grew sheet-taking `ruleProperty` / `setRuleProperty`, and the handle's existing
closure now delegates to them (one implementation, two entry points).

The **base** is read off the live rule **once per sheet identity**, before this target
has written to it. That is ADR-0029 probe L4 defended against directly: a composition
that re-reads its own output multiplies its own tail — measured there as
`0.500 → 0.750 → 0.875 → … → 0.998`, "the label is gone". A newly linked sheet is
freshly generated from its package, so its rule still holds the **designer's** number
— which is also why a package swap re-bases for free without this file ever being
told the new package's `scrimOpacity`.

## Decision 5 — one composition, two writers

`sheet_model.backdropTransparency(base, preference)` is the multiply, with identity on
garbage (an unusable preference means "leave the theme's value alone", never "guess").
Both writers call it. This is the `chrome_slots.DISABLED_CONTENT_OPACITY` shape and
the same reasoning that produced it — *"two writers, one constant"*, because two paint
vocabularies that agree today drift apart the moment either is edited alone. Pinned as
a source contract, since `src/client/*` reaches engine globals at load and cannot run
headlessly.

## Decision 6 — it resolves no palette, so it does not join `refreshThemedPaint`

ADR-0029 Decision 5 wrote down the entry condition: *a paint joins
`screen_paint.refreshThemedPaint` **iff its value resolves a palette**.* The
composed backdrop alpha resolves none — its terms are the sheet's own authored number
and the player's scalar — so a theme commit cannot make it stale.

It needs the **other** sweep instead, and that sweep is new: a *preference* change
stales an adapter-owned paint exactly the way a theme commit does. Bespoke mode gets
`screen_paint.refreshBackdropPaint`, guarded to non-native mode, because in native
mode an explicit write here would not lose a frame — it would make the rule's value
unreadable for good.

## Measured, live, on a real ScreenTarget — 2026-08-15

Full transcript in `artifacts/adr-0035-preferred-transparency/live-probes.md`.

**NATIVE mode**, the shipped fixture driven by its own steps, modal open:

```
              effective  backdrop swatch  modal scrim (raw)  raised panel  authored opacity 0.5
start           1          0.4500          0.4500 (0.0000)     0.0000        0.5000
setHalf         0.5        0.2250          0.2250 (0.0000)     0.0000        0.5000
setOpaque       0          0.0000          0.0000 (0.0000)     0.0000        0.5000
setFull         1          0.4500          0.4500 (0.0000)     0.0000        0.5000
```

Every claim in this document is one column of that table. The transparency columns are
`Instance:GetStyled("BackgroundTransparency")` — the **engine's** answer, not ours.
`raw = 0.0000` throughout is Decision 3 measured: no explicit write happened, the rule
is still the only writer, and ADR-0029's permanent defeat never occurs. The author's
`surface = "scrim"` swatch and the presenter's synthesized modal scrim move together;
the opaque `raised` panel does not move; the authored `opacity = 0.5` does not move.
Returning to 1 restores `0.4500` exactly — no drift, no tail.

**BESPOKE mode** (`nativeStyle = false`), where the adapter's explicit write is the
owner and there is no rule to move, produces the identical numbers on the raw
property — `0.4500 / 0.2250 / 0.1125 / 0.0000 / 0.4500` — and a node **created after**
the preference moved is born at `0.1125`, so the composition is at paint time and not
only in the sweep.

The engine property itself is **not scriptable**: `GuiService.PreferredTransparency`
is read-only, and `UserGameSettings.PreferredTransparency` refuses a non-RobloxScript
thread (both measured 2026-08-15). So the fixture drives the environment fact the
adapter publishes, exactly as `preferred_text` does; everything downstream of that
fact is production code.

## Consequences

- **The one accessibility preference Facet read and did not honour is honoured**, in
  both paint modes, on framework furniture and on any consumer node that declares
  `surface = "scrim"`. The comparison document's `accessibilityReduceTransparency` row
  moves from *Partial* to covered.
- **A default session paints byte-identically to before.** The preference defaults to
  1 and the composition's identity at 1 is the theme's own number, so nothing repaints
  until a player asks.
- **The declared scope is one list and it is asserted against the sheet.** Widening it
  is a decision someone has to make in the open.
- **`native_style` gained two module-level verbs** and lost a duplicated loop; the
  handle's `setRuleProperty` is now a two-line delegation.
- **The showcase teaches the refusals, not only the capability.**
  `examples/gallery/scenarios/preferred_transparency.luau` puts the backdrop, an
  already-opaque panel and an authored fade on one screen, because a preference that
  is *scoped* is only legible when something holds still beside the thing that moves.
- **What is still not on offer:** any way for the preference to reach an authored
  `opacity`, a stroke, a shadow or a disabled dim. If Roblox ever surfaces a separate
  *Increase Contrast* preference, the hairline and the focus glow are the two rows to
  reconsider — under that signal, not this one.
