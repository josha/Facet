### ViewThatFits

`UI.ViewThatFits(spec) -> Frame` shows the first child that fits and hides the
others. Each child is a candidate, in order of preference. The last candidate
shows when none fits. It needs at least one candidate. Options: `width` and
`height`. The props type is `ViewThatFitsProps`.

- With one candidate, its authored `Visible` state stays in control. There is
  no choice to make, so the container does not change that state.
- A candidate fits when its `AbsoluteSize` is not larger than the size of the
  container. Roblox measures every candidate, also a hidden one. Facet only
  sets `Visible`.
- Give the candidates a `hug` or a pixel width. A candidate that fills the
  width always fits.
- The container fills the width and hugs the height by default. An axis that
  hugs is unbounded, so only the width is tested. With a bounded `height`, the
  height is tested too. Directly in a `ScrollView`, the scroll axis is
  unbounded and the first candidate shows.

```luau
UI.ViewThatFits "Actions" {
    UI.HStack { gap = "s", save, cancel, help },
    UI.VStack { gap = "xs", save, cancel, help },
}
```
