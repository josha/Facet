# Adding artwork to a control

Keep the behavior of the control independent of its artwork. Input, selection,
value changes, cancellation and lifetime use the same code for native and
illustrated appearances.

## Consume a chrome slot

Declare a semantic chrome slot in the theme package. Consume it with
`themes.skin(runtime, package, slot, options)`. The helper returns native
artwork that Compose owns.

- Give a state readable for the hover, pressed, disabled and selected variants.
- Give the target and label information that the recipe needs.

Native ImageLabel slicing, tiling and resampling do the rendering.

## Choose a recipe

- Use a nine-slice for stretchable edges.
- Use a layered recipe for corners, frames and plaques.
- Use native or none when no extra image is necessary.

Define the necessary assets and coverage in the theme package. Keep text and hit
targets usable when artwork does not load.

## Checks

Do not add a separate skin renderer, a game-local event handler or a cleanup
registry. Test state transitions, theme switching, missing art, clipping and
owner removal. In Studio, verify the actual control at different sizes and with
keyboard and gamepad selection. Record the supported skin contract in the API
reference and in the [rich skinning guide](../guide/10-rich-skinning.md).
