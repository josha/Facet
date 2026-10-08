# Travel convergence

An item owns one stable visual and has one slot. A slot change moves the
visual. Travel measures the common ancestor, clipping and UIScale boundaries
at the change. A safe common container keeps the visual in place. Other
routes use the overlay. The model still owns accepted moves.

Travel adds a spring or ease motion choice and a readable transparency.
Theme durations, easing and spring metrics own all motion values. Use the
existing quick spring shape for the travel spring. Reduced motion lands at
once. The visual is the reusable carrier; it is not cloned per move.

Roblox AbsolutePosition, AbsoluteSize, ClipsDescendants and UIScale describe
routing. Native parent coordinates describe the in-place route. Compose
createSpringState, stepSpring and springAtRest supply the spring engine and
preserve velocity on retarget. One shared host-frame subscription serves all
active items. Compose owns each item and removes its registration at cleanup.
The internal engine also accepts a normalized progress sample for drag travel.

Check 64 simultaneous items, per-frame positions, overlay routing, spring
interruption velocity, leaving fade and unchanged game behavior. Keep the
existing game specs. Record the real-tree test pruning as a port constraint.
Writer D alone adapts its drag files to the shared engine.
