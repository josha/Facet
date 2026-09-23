# Adding artwork to a control

Keep the control's behavior independent of its artwork. Input, selection, value changes, cancellation and lifetime use the same code for native and illustrated appearances.

Declare a semantic chrome slot in the theme package and consume it with `themes.skin(runtime, package, slot, options)`. The helper returns Compose-owned native artwork. Pass a state readable for hover/pressed/disabled/selected variants, and the target/label information needed by the recipe. Native ImageLabel slicing, tiling and resampling do the rendering.

Choose a nine-slice for stretchable edges, a layered recipe for corners/frames/plaques, or native/none when no extra image is required. Define required assets and coverage in the package. Keep text and hit targets usable when artwork fails to load.

Do not add a separate skin renderer, game-local event handler or cleanup registry. Test state transitions, theme switching, missing art, clipping and owner removal. Verify the actual control in Studio at multiple sizes and with keyboard/gamepad selection. Record the supported skin contract in the API and [rich skinning guide](../guide/10-rich-skinning.md).
