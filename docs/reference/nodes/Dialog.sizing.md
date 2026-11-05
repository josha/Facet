# Dialog.sizing

Use a bounded body when a Dialog contains a fill NavigationStack, ScrollView or
form. Use the default body for a short confirmation that should hug its text.

`bodyHeight` accepts a finite nonnegative number or `"fill"`, fixed or readable.
A number is a preferred height in logical units. Facet applies the theme's
resolution scale and the active viewing-distance scale once. `"fill"` uses the
remaining height. Both offers subtract the header, hero, action label, actions,
gaps, panel insets, outer margins and keyboard. The offered body has a finite
height before its child reports native bounds.

With `bodyHeight`, the child fills that bounded body. Put long content in a
ScrollView inside the NavigationStack page. The page owns its overflow scrolling;
the Dialog does not measure the page to choose a presentation. The body wrapper
adds no selection stop. If the pinned regions cannot fit with a short body, the
existing Room scroller keeps the complete task reachable.

Without `bodyHeight`, the body keeps its natural height and the Dialog scrolls
its overflow. `contentSelectable` applies to this natural body.

`presentation` accepts `"automatic"` (the default) or `"inset"`, fixed or readable.
Automatic presentation can cover the safe area when natural content cannot
leave clear margins. Inset presentation keeps the theme's `space.m` outer margin
and caps the body inside it. Use inset presentation when the player needs to
see the context around a modal form, including on a short landscape screen.

`width` keeps the `automatic`, `narrow` and `wide` presets. For a bounded body,
automatic width uses the wide preset at the wide size class and the automatic
preset otherwise. The size class uses the layer width divided by the active
metric scale. Every preset is capped by the layer width less the outer margins.
Unbounded confirmations keep their existing automatic width.

Derive the host theme with `themes.forResolution(base, displayWidth, displayHeight)`
from the full display viewport. Bind that same theme to the existing controls
and StyleSheet. Do not multiply `bodyHeight` by the resolution scale yourself.
See [resolution scaling](Themes.resolution.md).

The canonical [Design](../../../examples/blocks/navigable_dialog_design.luau)
contains the Dialog, native NavigationStack and scrolling form. Its
[sample](../../../examples/blocks/navigable_dialog.luau) supplies presentation,
route and draft cells. Build `examples/dialog.project.json` with Rojo to run the
[host](../../../examples/dialog_sample.client.luau). The host derives a reactive
resolution theme and mounts the sample with Facet.app. In an existing app, call
the sample with that app's UI. The Dialog shares the host Compose runtime and
ScreenGui. The example's 420-unit preferred body height is an assumption for
this small preferences form.

Both sizing modes keep native navigation, modal focus and dismissal. A child
page owns Back. The root page has no Back. Closing returns focus to the opener.
