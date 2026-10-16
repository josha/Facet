# Popover.edge

Placement options: `edge` (`top`, `bottom`, `leading` or `trailing`), `align`
(`start`, `center` or `end`), `gap` (pixels, default 8) and `crossOffset`
(pixels along the alignment axis). Without an authored `edge`, an anchored
popover prefers above its source on touch and below for other input. The
default follows live input changes. The compact sheet route is unchanged.
The placement tries the preferred edge,
then the opposite edge. When neither side holds the panel, it hangs beside the
source before any clamp. `maxWidth` and `maxHeight` bound the whole panel,
chrome included, inside the live safe box. The body scrolls. `tail = false`
removes the arrow.

The tail of a Popover, a Callout and a Button `help` plate is one shape: a
`space.m` square turned 45 degrees under the panel (`facet-tail`), with no
stroke of its own. One closed native `Path2D` named `Outline` draws the
panel corners and the two outer sides of the tail as one border. It has the
`facet-outline` tag. A help plate also uses `facet-outline-tooltip`.
The border sits in a separate `OutlineBoundary` Frame beside the panel.
Thus the content padding and the fade container cannot move or clip the border.
A separate `OutlineFade` Frame contains the border bounds.
During a fade, its CanvasGroup fades the border with the panel and tail.
The group has space around the border so it cannot clip the pointer.
Its size stays fixed while the border moves.
The border uses the theme hairline color blended with the panel fill.
The panel's own `UIStroke` is off (`facet-outlined`).
The panel, border, and tail use the same scale for opening and closing.
The point where the tail joins the panel stays fixed during this motion.
At rest, the tip stops at the specified gap from its source.
The tail stays clear of the panel corners. The tail keeps
8 pixels from the panel's ends; a panel too short for that (a one-line panel
beside its source) centres the tail on its side instead of dropping it. The
tail is dropped only when it would no longer point at the source.

`cancelPolicy` is `dismiss` (the default) or `none`. With `none`, Cancel and a
tap outside propose nothing, so only the caller's fact or an action in the
content closes the panel. The panel stays modal.

`modal = false` makes the panel chrome, such as a coach mark or a hint beside
a control. There is no backdrop, no outside-tap catcher, no Cancel binding and
no selection claim, and the full-layer `Popup` Frame is not `Active`, so input
reaches the controls under and around it. The panel paints in the callout band
(`ZIndex` 95). A chrome panel always uses the anchored route.
