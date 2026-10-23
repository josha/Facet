### ButtonGuide

<!-- aliases: ButtonGuide | button guide | button legend | buttonGuides -->

ButtonGuide shows one row of hints, such as "A Buy  B Back  LB/RB Tabs", for commands that have no control of their own.

Use it for the commands that act on the focused item, the bumpers and
triggers, and Back on a surface without a visible Close. A command with its
own control shows its glyph on that control (`ShortcutHint` with
`cap = false`). Never list a command twice.

- `entries`: a list or a readable list. Each entry is
  `{ action = InputAction, label = ... }` or
  `{ keys = { { "LB" }, { "RB" } }, label = ... }`, the two sources of
  [ShortcutHint](Chip-and-ShortcutHint.md). `label` is a string or a readable
  string. Facet draws each entry as a `ShortcutHint` named `Entry`, with the
  label in the secondary text role. An `action` entry whose native `Enabled`
  is false is hidden, so the guide shows only the live commands and changes as
  focus moves. When no entry shows, the guide hides. Keep it to about four
  entries, in button order. Do not use the same action twice.
- `inputs`: the input classes that show the guide. The default is
  `{ "Gamepad" }`. Add `"KeyboardAndMouse"` only when the game asks for it.
  `"Touch"` stops with an error, because glyphs have no meaning on touch.
- `controlSize`: the size of the hints.

The guide follows the input class (`UI.environment().effectiveInput`), not
each input event. Mouse movement on keyboard and mouse never makes it flash.
With a gamepad the hints draw the bare platform glyph (`cap = false`). With
keyboard and mouse they keep the key cap.

The guide is a readout, never a focus stop. Nothing in it is `Selectable` or
`Active`, so the selection route, D-pad moves and the first focus of a surface
skip it. A `Selectable` property that you pass has no effect.

The guide hides while a modal surface that does not hold it is open, such as
an Alert above the HUD. The Alert shows its own choices. A guide inside the
open Sheet stays.

Players can hide every guide. The `buttonGuides` option of `Facet.app` and
`controls` takes a boolean or a readable boolean. The default is `true`. Bind
one settings Toggle to it.

The guide is a native Frame that hugs its content. It takes native Frame
properties, such as `Position`, `AnchorPoint`, `LayoutOrder` and `Visible`.
Put it along the bottom edge of the surface that owns input, inside the safe
area. In a Sheet, use the [Sheet guide slot](Sheet.guide.md).

Give each `action` entry the InputAction that the game binds for the command.

```luau
local buy = Host.InputAction { Name = "Buy" }
return UI.ButtonGuide {
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.fromScale(1, 1),
    entries = {
        { action = buy, label = "Buy" },
        { keys = { { "LB" }, { "RB" } }, label = "Tabs" },
    },
}
```
