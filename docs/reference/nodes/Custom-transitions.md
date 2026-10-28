# Custom transitions

Sheet, TabView, NavigationStack and NavigationSplitView accept
`transition = { seconds?, ease?, motion?, fade?, progress?, apply?, scale? }`.
`false` disables presentation motion. Omit the option to keep the control's
default motion. A table without `apply` or `scale` gives a fade.

`scale` is a zoom preset. The page content does not scale, so its text does
not step between sizes. The content fades in at full size on
`easing.zoomFade`. Behind it, a plate in the color of the nearest opaque
ancestor grows from `scale` to full size around its center on
`easing.zoomScale`. A leaving page plays the reverse. `scale = true` starts the
plate at theme `motion.materialize.zoom`. The duration is
`durations.zoomPresent`. `motion`, `seconds` and `ease` replace them. The plate
is a Frame named `TransitionPlate` with a UIScale named `TransitionScale`. It
exists only during motion. Without an opaque ancestor, and in a Sheet, the
zoom is a fade. You cannot use `scale` with `apply`.

`apply(content, phase)` runs once for each retained presentation, in the
content's Compose owner. Bind native properties with `runtime.decorate`. Do
not start a second animation clock or destroy the content in it.

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

A page that mounts for a transition stays hidden until its layout and text
are stable for two frames, or `motion.restLimit` seconds after its first laid
out frame. One slow frame in the first `motion.frameLimit` seconds adds at most
that time to the clock, so a slow mount does not skip the curve.

The Custom transitions lab page opens on an interactive journal: an opaque
leaf turns across a fixed spine with pointer/touch dragging and Previous/Next
actions. The fold is example artwork made from native Frames, not a Facet
effect API. The neutral theme's `pageTurn` duration is 0.65 seconds.
Roblox GuiObjects do not supply arbitrary 3D
perspective: use authored images or a Stage/ViewportFrame for a true 3D book.
