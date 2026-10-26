# Motion and feedback

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

Motion explains a change: where a page went, what gained focus, which value
changed, or where an accepted object arrived. It must not delay essential input
or make the player follow an animation to learn the result.

Separate immediate input feedback from progress and accepted outcome.
A pressed state can confirm that input arrived while the game still awaits a server result.
Keep the final result readable after motion ends. Reinforce urgent feedback with
more than one signal; sound, haptics or color alone can be missed.

Use theme timing and easing. Controls already provide shared feedback; do not
stack a custom loop on the same property. Use native StyleSheet transitions
where supported and `runtime.tween` or `runtime.spring` for other reactive motion.
Do not create another animation scheduler.

Use `Custom-transitions` for Sheet, TabView and NavigationStack presentation.
Bind through the supplied progress and owner so interruption and cleanup remain coherent.
For other Compose motion, supply a reactive `reducedMotion` policy; Compose core
does not discover the platform preference. Read `Motion.motionLevel` for Facet's policy.

Keep direct manipulation attached to input. After release, motion can explain
arrival or return. Hover and press must not change measured layout, move hit
targets or clip the emphasized control. Keep text readable during transitions.

Use Travel for an object moving between meaningful locations and `UI.sequence`
for ordered presentation. Keep accepted ownership in the model, independent
of either animation. Skip, interruption, navigation away and reduced motion
must preserve the same final state and cleanup.
Read `Effect-sequences` and `Travel.reference` for their contracts.

Use `UI.shake(faces, { intensity = 1 })` for brief rejection feedback.
Pass existing tile faces inside stable layout slots and call the handle's
`play()` method. The effect restores their rotations on completion, cancel,
replay and cleanup. Limited and none motion keep the faces still.
Keep the rejection reason and next action visible after the effect ends.

Reduced motion can execute sequence callbacks immediately. Do not depend on
a duration to grant rewards, release input or complete a task. Repeated state
updates should retarget or settle coherently rather than accumulating effects.

Test rapid reversal, repeat activation, resizing, theme changes, removal,
navigation during motion and reduced motion. At a fixed viewport, an idle
surface must settle. Measure frame cost and retained resources across repeated
navigation, not only during one quiet frame.
