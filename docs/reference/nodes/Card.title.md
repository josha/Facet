# Card.title

Card shows one item of a browsable collection: artwork, a title and an
optional caption, with a primary action and a More menu that show on
engagement. It requires `title` and `image` (nonempty strings or readables).
`artwork` can replace `image`. The other options are `caption`,
`imageAspectRatio` (default `16/9`),
`imageFraming` (`fit` or `crop`), `onActivate`, `primaryAction = { label,
icon?, onActivate, enabled?, busy? }`, `menu = { items, label? }`, `reveal`
(`automatic` or `always`), `browseTarget`, `enabled`, `ringTarget` and
`controls`.

With `onActivate`, the selection ring of the body surrounds the whole card: the
artwork, the text and the action row. `ringTarget = "media"` rings only the
artwork. The body keeps the PlayerGui's live focus look (see
[focusRing](focusRing.md)) and sets its `FacetFocusHeight` attribute, the height
of that area as a multiple of the body's, which the look reads. So a card's look
pulses, hides after mouse input and follows a theme change like every other
control's. A selected action keeps the look on itself.

Use a Card for a game, a track or a kart, where the picture helps the player
choose. For rows of text, use VirtualList or Table.
