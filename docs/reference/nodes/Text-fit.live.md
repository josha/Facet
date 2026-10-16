# Text-fit.live

The Stage content callback mounts into its WorldModel. It can return a teardown
function. The third argument, `live`, is a readable boolean. It is false while
the nearest ScrollingFrame ancestor scrolls and for 0.15 seconds after, and
while less than half of the stage shows in that scroll window. Without a
ScrollingFrame ancestor it is true. Pause scene animation while `live` is
false, so a scrolling feed does not write scene properties on each frame. With
`lazy = true`, the stage builds its content when it comes within half a window
of the scroll window, so a card never scrolls in empty. It builds also while
the window scrolls, and the stages of one control set build one per frame. Its
animation stays paused until `live` is true, and the last frame stays visible.
A stage farther away than that does not build its scene. The stage sets the attributes `FacetLive` and
`FacetBuilt`. Use the `Host.Part`, `Host.Model` and other native constructors of the
same runtime. A 3D view inside a UI rectangle is not the same as 3D UI layout.
