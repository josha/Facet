### Label

`UI.Label(spec) -> Frame` shows an icon and a title in a row. The title is the
accessible name in every presentation. The root has the `AccessibleLabel`
attribute, which follows a bound title.

- `title` is required. Its first value must be a string that is not empty. It
  can be a readable or a function of `use`. A `Title` child (a `UI.Text`)
  shows it.
- `icon` is a semantic icon name or an asset id. An `Icon` child shows it. An
  unknown semantic name causes an error.
- `presentation` is `titleAndIcon` (the default), `titleOnly` or `iconOnly`.
  Another value causes an error. Without an icon, every presentation shows the
  title only, because an empty square is worse than a word. The root has the
  `FacetPresentation` attribute with the presentation that shows.
- `iconSize` is a number of pixels or a theme metric name. The default is the
  icon size of the regular control size. `textSize` is a number of pixels or a
  type role, default `body`. `gap` is a number of pixels or a spacing step.
- `iconPosition` is `leading` (the default) or `trailing`.
- `text` and `label` cause an error. Use `UI.Text` for plain text.

The semantic names `speaker`, `volume` and `mute` resolve to bundled Roblox
speaker placeholders when the theme supplies no art. They need no uploaded
asset. Give a sound Button an accessible `name`, such as `Mute sound` or
`Unmute sound`. A theme can replace these placeholders through its `icons` map.
The native mute placeholder has a red cross.
