# Native input

Roblox owns selection, editing and input routing. Facet supplies control policy.
Use the [input design chapter](../../skills/use-facet/references/game-ui/INPUT_FOCUS_AND_ACCESS.md)
for player-facing decisions and [focus API](../reference/nodes/Focus-and-command-scopes.md)
for exact contracts.

A passive HUD needs an explicit entry into gamepad navigation. Controls use
native selection stops and preserve logical focus through collection recycling.
Do not require every row to remain mounted to support traversal.
Composition is already passive: the movement stick and D-pad stay with
gameplay. Give HUD tasks explicit game actions that open their task surfaces.

Native selection is spatial. Layout, overlapping selectable parents and nested
scrolling can change which target wins. Test actual directional input instead
of inferring reachability from a screenshot or a list of Selectable objects.
GuiService.SelectedObject and input-context behavior are engine facts; a custom
focus graph is not a substitute.

Modal controls trap selection, choose an enabled initial target, own Back and
restore the previous selection when it still exists. A Sheet's initial target
is its `initialFocus`, else its first content control, and its Close only when
nothing else can be acted on; a Dialog starts on its cancel action. GuiButton.Modal affects
mouse locking; it is not a focus trap. Do not bind reserved Escape or gamepad
Start. A game must separately suppress gameplay commands while UI owns input.

TextInput leaves IME, caret and text selection to the engine. Facet owns
validation, bounds, change, commit and cancel policy. External model writes
must not be mistaken for user editing.

World-fixed UI is a flat SurfaceGui. World anchors do not establish a new
three-dimensional input system. See
[native targets](../reference/nodes/Native-targets-and-boundaries.md).

Run relevant live cases using [device verification](device-verification.md).
Tests retain engine regressions; this guide does not maintain a history of
individual probe observations.
