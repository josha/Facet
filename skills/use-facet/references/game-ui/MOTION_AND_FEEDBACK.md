# Motion and feel

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

Feel is how quickly and how fittingly the interface answers.  Motion explains a change: where a page went, what gained focus, which value changed and where an accepted object arrived.  Neither delays essential input, and neither makes the player follow an animation to learn a result.

## Answer in layers

Separate three answers to every action:

1. **Input arrived.**  The pressed state shows in the same frame, with a tick of sound or a haptic where it helps.
2. **Work is under way.**  A pending state or progress shows while the game waits for the server.
3. **The result is accepted.**  The final state, and any celebration, comes only after acceptance.

Scale each answer to its significance.  Moving focus is quiet.  Confirming is crisp.  A routine gain settles without fanfare, and several gains combine into one.  A rare accepted reward can build anticipation, reveal itself and settle into place.  Danger interrupts with more than one signal, because sound, haptics or color alone can be missed.  Keep the final result readable after the motion ends.

## Give sound a system

Facet plays haptics but no sound; the game plays UI sounds from the same events.  Give them one family that fits the world.  Use a distinct sound for focus, confirm, back, error and reward, and keep each one short.  Keep repeated sounds, such as focus moves, quiet enough for long use, and keep UI sound under the game's volume settings.  A sound reinforces a visible change; it never replaces one.

## Give motion meaning

- **Direction.**  Pages arrive from the direction of travel and leave the way they came.
- **Continuity.**  An object that moves between places travels there, so the player sees where it went.
- **Change.**  A value that changes counts or settles to the accepted number.
- **Stability.**  Hover and press never change measured layout, move hit targets or clip the emphasized control.  Text stays readable during a transition.
- **Attachment.**  Direct manipulation stays attached to the input.  After release, motion can explain the arrival or the return.

Timing carries the game's character.  A toy world can use springs with a little overshoot; an instrument panel can use short, clipped transitions.  Set that character once, in the theme.

## Use the shared mechanisms

Use the theme's timing and easing.  Controls already animate their own feedback; do not stack a custom loop on the same property.  Use native StyleSheet transitions where they apply, and `runtime.tween` or `runtime.spring` for other reactive motion.  Do not create another animation scheduler.

Facet:

- `Custom-transitions` change the presentation of Sheet, TabView and NavigationStack.  Bind through the supplied progress and owner, so interruption and cleanup stay coherent.
- Travel moves an object between meaningful places, and `UI.sequence` orders a presentation.  Keep accepted ownership in the model, independent of either animation.
- Flash paints a transient effect over a target.
- `UI.feedback(kind)` plays a haptic for a result that does not come from a press, such as a purchase the server confirms.  A Button's `haptic` plays one on press.  The game plays its own sounds from the same events.
- For other Compose motion, supply a reactive `reducedMotion` policy; Compose core does not discover the platform preference.  Read `Motion.motionLevel` for Facet's policy.

Skip, interruption, navigation away and reduced motion reach the same final state and cleanup.  Reduced motion can run sequence callbacks immediately.  Never depend on a duration to grant a reward, release input or complete a task.  Repeated updates retarget or settle coherently instead of piling up effects.

## Check

Test rapid reversal, repeated activation, resizing, theme changes, removal, navigation during motion and reduced motion.  At a fixed viewport, an idle surface settles completely.  Measure frame cost and retained resources across repeated navigation, not only in one quiet frame.

Read `Effect-sequences`, `Travel.reference`, `Haptics` and `Motion.metrics.motion` for the exact contracts and tokens.
