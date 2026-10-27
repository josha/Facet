# Card.title

Card shows one item of a browsable collection: artwork, a title and an
optional caption, with a primary action and a More menu that show on
engagement. It requires `title` (a nonempty string or readable). `image` or
`artwork` adds art; without either, the Card is a text card with padded title
and caption, for example a shop item. The other options are `caption`,
`imageAspectRatio` (default `16/9`),
`imageFraming` (`fit` or `crop`), `onActivate`, `primaryAction = { label,
icon?, onActivate, enabled?, busy? }`, `menu = { items, label? }`, `reveal`
(`automatic` or `always`), `browseTarget`, `enabled`, `ringTarget`,
`badges = { leading?, trailing? }` and `controls`.

With `reveal = "automatic"`, the action row overlays the bottom of the card
on a pointer device. It uses a plate above the content and adds no layout
height, even while visible. Hover, focus, press, an open menu or gamepad entry
reveals the row. Hidden actions are not interactable. Reduced motion switches
the row without a fade. With `reveal = "always"`, or when touch is available,
the row stays visible in the layout and reserves its height.

With `onActivate`, the selection ring of the body surrounds the whole card: the
artwork, the text and the action row. `ringTarget = "media"` rings only the
artwork. The body keeps the PlayerGui's live focus look (see
[focusRing](focusRing.md)) and sets its `FacetFocusHeight` attribute, the height
of that area as a multiple of the body's, which the look reads. So a card's look
pulses, hides after mouse input and follows a theme change like every other
control's. A selected action keeps the look on itself.

`badges` shows item states, such as Owned or Rare, on the top corners of the
art. See [Card.badges](Card.badges.md).

A card without `primaryAction` and `menu` has no action row. Its plate ends at
its body, and the bottom text of a media card keeps a `space.s` inset. In a
VirtualList or VirtualGrid with selection, the collection paints no plate
under a card. The selected card shows the theme's selected color on its own
plate, and its text uses the selected text color.

Use a Card for a game, a track or a kart, where the picture helps the player
choose. For rows of text, use VirtualList or Table.
