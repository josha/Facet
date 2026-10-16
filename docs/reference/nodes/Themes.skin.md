# Themes.skin

Themes.skin option values and behavior.

- `skin(runtime, packageOrReadable, slot, options?)` builds native control
  artwork. The options include `state`, `selected`, `target`, `label`,
  `onCaption`, `ZIndex` and injected `types`. When a state has no art of its
  own and `selected` is true, the skin uses the `selected` art before the
  `default` art. A plaque layer with `text = true` is title art: it shows
  `label` and is drawn only while `label` is not empty. It grows around the
  text by its `textInsets`, never below its own size, and stays centred on its
  edge. `onCaption(shown)` reports whether the plaque shows the label.
  `shadowTransparency` blends the shadow toward transparent; fading controls
  bind it to their paint so their glow cannot outlast their visible panel.
  A `target` that is a TextBox gets no art images, only the recipe shadow.
  Roblox draws children above their parent, so art in a TextBox would cover
  its text and placeholder.


`createStyleSheet` contract:
