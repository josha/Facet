# Motion and feedback

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

Motion explains a change: where a page went, what gained focus, which value
changed, or where an accepted object arrived. It must not delay essential input
or make the player follow an animation to learn the result.

Use theme timing and easing. Controls already provide shared feedback; do not
stack a custom loop on the same property. Use native StyleSheet transitions
where supported and Compose-owned tween or spring for other reactive motion.
Do not create another animation scheduler.

Keep direct manipulation attached to input. After release, motion can explain
arrival or return. Hover and press must not change measured layout, move hit
targets or clip the emphasized control. Keep text readable during transitions.

Use Travel for an object moving between meaningful locations and Sequence
for ordered presentation. Keep accepted ownership in the model, independent
of either animation. Skip, interruption, navigation away and reduced motion
must preserve the same final state and cleanup.

Reduced motion can execute sequence callbacks immediately. Do not depend on
a duration to grant rewards, release input or complete a task. Repeated state
updates should retarget or settle coherently rather than accumulating effects.

Test rapid reversal, repeat activation, resizing, theme changes, removal,
navigation during motion and reduced motion. At a fixed viewport, an idle
surface must settle. Measure frame cost and retained resources across repeated
navigation, not only during one quiet frame.
