### Notice

<!-- aliases: Notice | notice -->

`UI.Notice` returns the notice Frame. It keeps a status in the page until the
state changes. It is never modal.

- `message`: required, a string or a bound string. `title` is optional.
- `severity`: `info` (the default), `success`, `warning` or `error`.
- `appearance`: `standard` or `emphasis`. `emphasis` fills the plate with the
  severity color. A `standard` plate pads its content by the theme's `panel`
  chrome `contentInsets`, and not less than 8 pixels, so art in the frame does
  not cover the content. The title wraps and is never cut.
- `icon`: `true` (the severity icon), `false`, or an icon name or source.
- `link`: `{ label, onActivate }`. It uses the link appearance on a standard
  plate.
- `actions`: up to two actions. Roles only paint. There is no default or
  cancel key.
- `onDismiss`: shows a close button. A press closes the height of the
  notice and then calls `onDismiss`. Remove the notice yourself. If the notice
  stays mounted, it opens again. Under reduced motion, or before the notice
  has drawn a frame, `onDismiss` runs at once.
- `placement`: `inline` (the default) or `affixed`.

The link and actions sit beside the copy when the measured width holds them.
Otherwise they move below it. The notice does not take the selection. A new
notice opens its height from 0, so the content below it moves down smoothly.
While the height moves, the notice clips its content and uses
`AutomaticSize = None`. At rest it uses its own `Size` and `AutomaticSize`. An
affixed notice fills the width and sets the `FacetInsetTop` attribute on its
layer to its bottom edge. Several affixed notices keep the deepest edge.
Content that must avoid the notice reads the attribute and pads by it.
