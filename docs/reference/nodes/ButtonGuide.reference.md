### ButtonGuide

<!-- aliases: ButtonGuide | button guide | button legend | buttonGuides -->

ButtonGuide shows one row of hints, such as "A Buy  B Back  LB/RB Tabs", for commands that have no control of their own.

Use it for the commands that act on the focused item, the bumpers and
triggers, and Back on a surface without a visible Close. A command with its
own control shows its glyph on that control (`ShortcutHint` with
`cap = false`). List each command once: an action or a key that appears twice
stops with an error.

- `entries`: a list, a readable list or a function of `use`. Each entry has a
  `label` (a string or a readable string) and one source:
  - `action`: a native InputAction. The entry shows the platform glyph of the
    action's `PreferredBinding`. It shows only while the action's native
    `Enabled` is not false and the device has a binding for it.
  - `keyCode`: an `Enum.KeyCode` or a list of them, such as
    `{ Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1 }`. The entry draws each
    platform glyph from `UserInputService:GetImageForKeyCode`, else the
    platform key name from `GetStringForKeyCode`. It always shows.
  - `keys`: chords of written key names, as in
    [ShortcutHint](Chip-and-ShortcutHint.md). The entry draws the text as
    written, so it is the same on every platform. Use `keyCode` for gamepad
    buttons.
- `inputs`: the input classes that show the guide. The default is
  `{ "Gamepad" }`. Add `"KeyboardAndMouse"` only when the game asks for it.
  `"Touch"` stops with an error, because glyphs have no meaning on touch.
- `controlSize`: the size of the hints.

Each entry is a `ShortcutHint`-style row named `Entry`, with the label in the
secondary text role. When no entry shows, the guide hides. Keep it to about
four entries, in button order. An entry keeps its hint while its action, key
codes, or keys and label stay the same.

The legend changes as focus moves when its actions follow focus: use the
actions of a `UI.commandScope` (enabled while the scope holds the selection),
or actions whose native `Enabled` the game sets. An action that no scope or
game code disables stays `Enabled`, so its entry stays.

The guide follows the input class (`UI.environment().effectiveInput`), not
each input event. Mouse movement never makes it flash. With a gamepad the
hints draw the bare platform glyph (`cap = false`). With keyboard and mouse
they keep the key cap.

The guide is a readout, never a focus stop. Nothing in it is `Selectable` or
`Active`, so the selection route, D-pad moves and the first focus of a surface
skip it. A `Selectable` property that you pass has no effect. The guide hides
while a modal surface that does not hold it is open, such as an Alert. A guide
inside the open Sheet stays.

The `buttonGuides` option of `Facet.app` and `controls` hides every guide when
it is false. Bind one player settings Toggle to it.

The guide is a native Frame that hugs its content and takes native Frame
properties, such as `Position`, `AnchorPoint` and `LayoutOrder`. Put it along
the bottom edge of the surface that owns input, inside the safe area. In a
Sheet, use the [Sheet guide slot](Sheet.guide.md).

```luau
local shelf = UI.VStack { UI.Button "Blade" { label = "Blade" } }
local scope = UI.commandScope(shelf, {
    targets = {},
    commands = { { id = "Buy", keys = { "ButtonX" }, onInvoke = function() end } },
})
return UI.VStack {
    shelf,
    UI.ButtonGuide {
        entries = {
            { action = scope.actions.Buy, label = "Buy" },
            { keyCode = { Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1 }, label = "Tabs" },
        },
    },
}
```
