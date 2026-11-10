# Game UI design

Facet supplies reusable behavior. The game supplies purpose and visual
character. Start with the player's experience, then choose interaction,
composition and controls. This page holds the design rules that Roblox games
break most often. The brief and the established art direction take precedence
over every rule here.

## Principles

- **Serve the player's intent.** Make the situation, choices, action and result understandable. Keep deliberate game challenge; remove accidental interface difficulty.
- **Direct attention.** Show what changes the next decision. Urgency, relevance and frequency set priority.
- **Make the game recognizable.** Its world, objects and tone shape art, framing, type and motion.
- **Preserve continuity.** Keep identity, location, useful state and return paths clear as the task changes.
- **Support equivalent tasks.** Adapt to room, reach, input and viewing distance without losing decisions, consequences or exits.
- **Earn trust.** Show what the game accepted. Make commitment, failure, cancellation and recovery predictable.

Trace each task from entry through choice, commitment and feedback to return,
including cancellation and rejection. Preparing equipment ends with accepted
equipment in play; opening the collection does not complete the task. Do not
invent game systems to fill a screen.

## Choose the surface

Decide how much attention the task needs before choosing a control.
[Choose an interaction](choose.md) lists the control for each task, and
[game screens](game-screens.md) covers navigation and lifetime.

- Use a Sheet when the task needs temporary modal focus over the game. Keep
  HUD context visible when it helps the decision. The task root has Close and
  no Back.
- Use a page when the player enters a different mode that replaces the play
  view, such as a store or a garage. A Screen with `surface` paints to the
  edges.
- Keep a short choice near its source. A HUD opener does not decide the
  presentation: a contextual command, a persistent tool and a full-screen map
  have different needs.
- Use a radial choice when direction or a learned spatial arrangement helps.
  A menu or an anchored popover often fits labeled alternatives better.
- Keep frequent safe actions direct. Add review in proportion to consequence.
  A confirmation does not repair an ambiguous label or adjacent targets.

Focus, selection and commitment differ. Moving through options must not buy or
equip them.

## Direct attention and express the game

Establish what the player notices first, second and third. Keep the facts for
one decision together. Reduce competing borders and accents before adding
decoration, and reserve the strong accent for the important action or state.

Art direction sets composition as well as paint. A subject staged beside a
choice, objects arranged on a surface and a chart with commands need different
bodies. Do not build a generic card page and add an illustration above it.
Choose each page's body before writing a shared page helper: share navigation,
input lifetime and visual roles, and let each body arrange its own decision.

Give objects meaningful artwork or a well-framed Stage preview. Show a color as
a swatch and a pattern as a preview, and keep the preview recognizable when it
is selected or focused. Use grids for recognition, lists for descriptions and
tables for shared attributes.

Show one kind of fact in one treatment everywhere, so the eye compares values.
Price does not establish ownership: show ownership, availability and selection
when they affect the decision. Distinguish focus, selection, equipped, pending
and unavailable by more than color.

Hover and focus must not move neighbors or clip the emphasized object. Motion
explains a change and must preserve the result when reduced or skipped.

## Protect play

Keep the camera's focus area and the space under a held thumb clear. Show the
glanceable information that changes the next action, and group HUD content by
meaning with explicit priority. A compact form must keep access to every
required task that it replaces.

The free strip beside Roblox's top bar buttons suits a compact readout or a
menu button, not a frequent action: a phone's top edge is out of thumb reach.
Give the primary action the widest target and put it with its frequent
neighbours in one `action` region. A portrait phone shows that region at the
bottom centre, and a landscape screen at the bottom right. Composition handles
`TopbarInset`; read `HUD-actions` to match Roblox's row.

Composition is passive. Gameplay keeps the movement stick and D-pad, so give
HUD tasks explicit gamepad actions and visible input hints. A page that
replaces gameplay must own input and restore the previous state on return.
Opening an overlay does not pause the world. The
[input chapter](game-ui/INPUT_FOCUS_AND_ACCESS.md) explains input ownership.

## Adapt the task

Room, physical readability, reach, input precision and pace are separate
constraints. A high-resolution handheld can need large text and controller
navigation in a short layout. Choose layout from the usable container bounds,
prompts from the active input and actual bindings, and text size from the
player's preference. Keep selection, drafts and location through a resize or
an input change.

Show browsing and detail together when they fit; otherwise provide a complete
detail step. Reflow groups and disclose optional facts before reducing
legibility, consequences or exits. Do not shrink the whole UI.

Touch needs reachable targets and movement clearance. Pointer hover cannot
hold required information. Gamepad needs visible entry, predictable focus,
scroll access and Back. Give precision gestures a digital alternative. A
displayed shortcut must invoke the same command as its control. Do not bind
Roblox's reserved Escape or gamepad Start.

## Make outcomes truthful

Acknowledge input and distinguish pending, accepted and rejected work. Sending
is not saving; the server owns accepted progression. Keep drafts recoverable
with one dirty-dismissal policy. Preserve query, selection and useful scroll
position on return.

Distinguish no items, no matches, loading, unavailable and failed requests,
and offer the matching next step. Keep important results available after
transient feedback. Sound and haptics need an equivalent visible signal. Lead
results with the personal outcome and accepted gains, then comparison and the
next action.

## Design sources

- Celia Hodent's [game UX practice](https://celiahodent.com/ux-practices-epic-games/) distinguishes intended challenge from interface difficulty.
- Edd Coates's [Game UI Database](https://www.gameuidatabase.com/) and [Interface In Game](https://interfaceingame.com/) supply screen references.
- The Xbox Accessibility Guidelines cover [navigation](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/112) and [context and consequences](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/114).
- Valve's [handheld recommendations](https://partner.steamgames.com/doc/steamhardware/recommendations) separate controller access and physical readability from resolution.
