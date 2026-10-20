# Interactive transitions

Use [custom transitions](Custom-transitions.md) for a journal, card pager or
swipe-controlled detail reveal. Do not replace a ScrollView or Slider with
this pattern.

`transition.progress` accepts a Compose readable of `number?`.
A number from 0 to 1 holds the transition at that position without easing.
The presented page uses that value; departing pages use its complement.
Set the readable to `nil` to settle from the held position to the current
presentation target, with the same Compose tween and theme timing.
Facet retains departing content while progress is held, even at an endpoint.
Content input is blocked during the hold and settlement.

Use native `UIDragDetector` with `ResponseStyle = CustomOffset` on a stable
parent outside the retained page layers. Bind its events through `Host`.
Do not put the detector inside a page whose input the transition blocks.
Keep the detector's parent still; bind page artwork to `phase.progress`.
The game owns direction, distance, velocity, the commit threshold and page data.

For TabView:

1. Create `Compose.cell(nil :: number?)` and pass it as `transition.progress`.
2. On drag start, save the original selection. In one `runtime:batch`, set
   progress to 0 and select the destination. This selection is provisional.
3. On drag continue, write normalized progress. Do not tween pointer samples.
4. On release, use one batch to restore the original selection if cancelled
   and clear progress to `nil`. On commit, keep the destination selection.
5. Keep explicit Previous/Next buttons for keyboard and gamepad. Disable
   conflicting actions during a drag. Cancel a gesture when its task is closed.

For a Sheet dismissal, keep the Sheet open during the drag and reduce progress
from 1 toward 0. On release, batch the chosen open state and clear progress.
Keep the native drag detector outside the Sheet's blocked content.

Under limited or no motion, keep gesture distance for the release decision,
but defer the selection change until release. Facet keeps custom transforms
at rest under these settings.

The [journal example](../../../examples/facet-lab/src/journal_demo.luau) shows
the native detector, Compose cells, Facet TabView and authored fold together.
Its text remains visible on each face and clips at the turning edge. This
native 2D treatment does not project text onto a curved 3D surface.

Test a slow hold, a short cancelled drag, direction reversal, a quick flick,
release outside the page, resizing and closing during a drag. Check reduced
motion and the same task through the explicit navigation buttons.
