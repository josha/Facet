# Travel.ZIndexBehavior

Moving carriers have distinct native ZIndex values above resting siblings.
Travel restores scale on landing. Its landing depth stays above the slot's
child controls, so a cell button cannot cover the item. Travel subtracts
effective native UIPadding and inset borders from the slot geometry. The
flight targets the content box that a native fill child occupies at rest.
An outline UIStroke does not change that box. The hand-off keeps the same
screen rectangle. Use native
`ZIndexBehavior = Sibling` for the game root. A rack shuffle changes seven
keyed items' destination slots; it needs no consumer frame loop.

Arc height uses `motion.distances.travelArc`. Reduced motion places and fades
at once. All active items use one shared Compose host-frame stepper. Keyed
items retain their carriers across moves. The root's `FacetTravelMoving`
attribute reports motion. Buttons, gamepad commands and drag callbacks all
change the same destination model. Native bounds, selection, clipping and
paint continuity still need live verification.
