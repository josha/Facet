# Custom transitions

Sheet, TabView, NavigationStack and NavigationSplitView accept
`transition = { seconds?, ease?, motion?, fade?, progress?, apply?, scale? }`.
`false` disables presentation motion. Omit the option to keep the control's
default motion. A table without `apply` or `scale` gives a fade.

`scale` is a zoom preset. The content scales from `scale` at progress 0 to
full size at progress 1, around its center. With the default fade, the
content is transparent at progress 0 and opaque at progress 1. A page that
leaves plays the reverse. `transition = { scale = 0.5 }` zooms a page in from
half size. The preset uses the theme's `zoom` duration and `zoom` easing.
`motion`, `seconds` and `ease` replace them. Facet adds a UIScale named
`TransitionScale` to the content. You cannot use `scale` with `apply`. To
combine a zoom with other motion, bind a UIScale in `apply`.

`apply(content, phase)` runs once for each retained presentation. It runs in
the content's Compose owner. Bind native properties with `runtime.decorate`.
Do not start a second animation clock or destroy the content in this callback.

`phase.progress` is a readable number from 0 (absent) to 1 (present).
`phase.isPresented` is a readable boolean. It changes when the page becomes
covered or the surface leaves. An interrupted transition retargets from its
current progress. Reopening a departing Sheet keeps the same content.

```luau
local entrance = {
    motion = "pageTurn",
    apply = function(content, phase)
        runtime.decorate(content, {
            Position = function(use)
                return UDim2.fromOffset(48 * (1 - use(phase.progress)), 0)
            end,
        })
    end,
}
```

`motion` names a duration in the current theme's `motion.durations` table.
The default is `tabFade`. `seconds` overrides that duration and must be
positive. `ease` follows Compose's tween easing contract. Facet applies an
outer fade by default. Set `fade = false` for an opaque page turn or reveal.
This changes paint only. Facet still retains departing content until progress reaches zero, and gates custom
content input until it reaches rest. Focus, Back and modal behavior stay with
the control. The first navigation or tab page appears at rest.
Custom tab departures wait for the destination's native preparation, so both
retained layers start together.

For direct manipulation, bind a nullable Compose readable to `progress`.
See [Interactive transitions](Interactive-transitions.md) for native drag
input, finger-following progress, release settlement and cancellation.

The callback receives an inner GuiObject. Its resting position is zero, its
anchor is zero, and its size fills the control's presentation rectangle.
Keep the frame's rest geometry usable after a resize. Properties set on the
frame do not change the control's outer layout or modal hit region.
Sheets prepare native text at progress 1 while hidden, then start their entry.

Under limited motion, custom progress stays at 1 and the outer presentation
uses a short fade, including when `fade = false`. Under no motion, visibility changes immediately. Do not
derive large motion directly from `isPresented`; use `progress` so this
adaptation applies to the authored effect.

Use this hook for a 2D page turn, staggered menu rows, item detail
entrances, and matching page exits. The Custom transitions lab page opens
directly on an interactive journal: an opaque leaf turns across a fixed spine,
with a bound cover, shaded paper,
a curved fold, pointer/touch dragging, and Previous/Next actions. The print stays
visible on each face and clips at the turning edge. It does not fade or reflow.
This native 2D treatment does not project text onto a curved 3D surface. The fold
is example artwork made from native Frames; it is not a Facet effect API.
The neutral theme's `pageTurn` duration is 0.65 seconds.
Roblox GuiObjects do not supply arbitrary 3D
perspective: use authored images or a Stage/ViewportFrame for a true 3D book.
Engine particle effects remain separate from this presentation contract.
