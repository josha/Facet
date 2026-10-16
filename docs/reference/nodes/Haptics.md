### Haptics

`pressHaptic` plays only for a control that changes a state or a value:

- Toggle and a Chip with `selected`.
- A Picker option that is not selected. A multiple Picker option always plays.
- A Stepper step.
- A Slider with a `step`. The effect plays once for each detent, not for each
  frame.
- Rating and LevelPicker.
- An Alert action with the `destructive` role or the `defaultAction` shortcut.

A plain Button, a tab, a menu row, a keyboard key and a link do not play it.
Set `haptic = true` on a Button to play `pressHaptic` for a game-specific
action. `true` is the shorthand for `pressHaptic`. `haptic` also takes a
feedback kind, which plays that kind whether or not `pressHaptic` is set.
`haptic` can be a readable of either. An explicit `PressHapticEffect` always
wins.

The feedback kinds map to one engine `HapticEffect` each. The controls create
each effect once, when a control or `UI.feedback` first asks for it, and
parent it to the Workspace. The engine plays the press effect through
`GuiButton.PressHapticEffect`.

| Kind | Engine effect | Use it for |
|---|---|---|
| `selection` | `UIClick` preset | a choice that changes |
| `impact` | `GameplayCollision` preset | a heavy press, a hit or a landing |
| `success` | `UINotification` preset | a completed task |
| `warning` | `Custom`: two pulses of 0.7 | a choice with a cost |
| `error` | `Custom`: three pulses of 1 | a refused action |

`UI.feedback(kind)` plays a kind at once, for a result that does not come from
a press, such as a purchase that the server confirms. An unknown kind causes
an error that lists the kinds. Studio plays no motor; a phone or a gamepad on
a supported client feels it.

The `theme` option of `controls` does not install paint. Parent a
`createStyleSheet` result and its StyleLink in the native tree, with the same
theme package source. `Facet.app` does this for you.
Ordinary Roblox consumers use the ambient services and datatypes. The runtime
that you supply must use the Compose Roblox host.
