### Chip and ShortcutHint

<!-- aliases: Chip and ShortcutHint | chip-and-shortcuthint -->

Chip takes `label` and either a boolean `selected` or `onRemove`.
`onToggle(next)` is controlled. The other options are `editing`,
`removeLabel`, `removeFocusFallback`, and native `leading` and `trailing`
children.

Removal is edit mode. A chip with both `selected` and `onRemove` requires
`editing`, a boolean or a readable boolean that you own. A chip with
`onRemove` and no `selected` is always in edit mode. Outside edit mode, a
chip only selects and shows no close mark. In edit mode, a `Remove` text mark
shows inside the one chip button, and the `AccessibleLabel` attribute is
`removeLabel` (the default is "Remove" and the label). Then activation, and
Delete, Backspace or ButtonX while the chip is selected, call `onRemove`. The
mark is not a separate button or focus stop. `onRemove` does not change your
collection. Remove the item yourself. When a selected chip is removed,
selection moves to the next removable chip, then the previous one, then
`removeFocusFallback`. A Delete or Backspace key that is still down when
selection arrives does not remove the next chip.

A Chip has the `facet-selection-mark` tag. A chosen chip uses the `selection`
and `onSelection` colors when a palette of the theme package declares
`selection`. Otherwise it keeps the selected wash (`controlSelected`).

ShortcutHint takes `keys = { { "Ctrl", "K" } }` or an `action` InputAction. It
also takes an optional `separator` and `controlSize`. The default separator is
` / `. The theme metric `controls.shortcutHint.capStroke` sets the width of the
cap outline. Without it, the outline is `strokes.hairline`. A value of 0 draws
no outline.

With `action`, the hint shows the action's native `PreferredBinding`: the
binding's `DisplayImage` or the platform glyph when there is one, else the
binding's `DisplayName`, else the key names. A touch control usually binds a
`Scriptable` binding that has no key. Set that binding's native `DisplayName`
(for example `"ITEM"`, the words on the touch button) so the hint shows them
on touch. Without a name the hint shows no words for that binding.

`label` shows the words for the action beside the keys in the secondary text
color, such as `label = "Interact"`. `labelPosition` is `end` (the default,
after the keys) or `start`. With a label, ShortcutHint returns a row Frame that
holds the keys, named `Keys`, and the `Label`.
