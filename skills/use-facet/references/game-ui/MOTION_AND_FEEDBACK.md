# Motion and feedback

Part of [Designing game interfaces with Facet](../GAME_UI_DESIGN_GUIDE.md). Motion communicates change, orientation, feedback, and pacing. Use it when that communication improves the experience enough to justify its attention and time cost.

Choose the interaction separately. [Adaptive interaction and direct manipulation](ADAPTIVE_INTERACTION_AND_DIRECT_MANIPULATION.md) explains how players act on visible objects through touch, pointer, keyboard, and gamepad. This chapter explains how to present the resulting changes. During manipulation, feedback must remain coupled to the active input; after release or commitment, motion can explain settling, arrival, or return.

## Decide whether motion earns its place

Useful motion answers a question: Where did this come from? What changed? Where did that item go? Which thing needs attention? What just happened that deserves celebration?

| Purpose | Good use | Failure to avoid |
| --- | --- | --- |
| Orientation | A detail surface appears from a meaningful origin; Back visibly returns | Every unrelated panel flies from a different edge |
| Continuity | An item moves to its new slot; neighboring records settle into their new order | The item vanishes and another appears with no visible relationship |
| Feedback | A pressed action responds immediately; a changed meter briefly shows the loss | Success animation runs before acceptance, or feedback arrives only after a long flourish |
| Attention | One newly relevant objective receives a brief emphasis | Every counter pulses continuously |
| Progress | A visible amount changes smoothly enough to follow | Interpolation hides the actual value needed for a decision |
| Pacing and delight | An earned result receives a short, skippable presentation | Routine navigation repeatedly forces a cinematic delay |

If motion answers none of these questions and contributes little to the intended atmosphere, leave the change immediate. Motion attracts attention more strongly than many static differences; it can destroy the hierarchy of an otherwise restrained screen.

During active play, keep glances short and required targets stable. Do not animate a brake button away from a finger, delay the appearance of a hazard, or let a reward fly across the aiming area. During planning, motion can explain selection, ordering, and transfer. During results or narrative, it can carry more of the experience, provided players can finish or skip repeated presentation and still understand the outcome.

## Choose the Facet motion mechanism

Start with the control's existing behavior. Facet already animates navigation, sheets, disclosures, menus, collection rearrangement, and many state changes. Adding another animation around the same geometry can create double motion, delayed interaction, clipped text, or unstable measurement.

| Intended effect | Use | When/how to configure |
| --- | --- | --- |
| Ordinary navigation, presentation, expansion, or reorder | The owning control's built-in motion | Start with its defaults and theme `metrics.motion`; change the control's supported transition settings only for a concrete reason |
| Different timing or character across the game | Shared motion tokens | Tune relevant durations, easing, springs, distances, and scales together, preserving the hierarchy between routine feedback and celebration |
| A particular supported navigation/presentation transition | That control's `transition` | Use its actual contract: these options are not interchangeable across controls. `false` disables motion where supported; a custom transition must still honor the chosen motion level |
| A number visibly approaching an accepted new total | `UI.countUp(value)` | Format the returned readable in `Text`; use for reward/progression presentation when temporary interpolation does not mislead |
| One brief pulse or sweep over an existing object | `UI.Flash` | Supply a target and progress; choose `pulse` or `sweep` to emphasize the change, with the lasting state visible separately |
| One persistent visual moving between slots | `UI.Travel` | Change its destination model; preserve mounted slot anchors and let Travel own position, size, and boundary crossing |
| Several meaningful effects in a deliberate order | `UI.sequence` | Coordinate step boundaries, progress, and parallel effects without writing another frame loop |
| A held object following the player, then landing or returning | Drag/drop feedback and transfer travel | Let the drag session own its preview and input; do not add a competing Travel visual under the pointer |
| Paced narrative text | `Typewriter` | Give a finish/skip route; use ordinary Text for information needed immediately |

Use the smallest mechanism that owns the relationship. A tab change does not need a sequence. A reward involving an emphasis, transfer, and total change may. A player dragging an item does not need the game to manually animate a clone each frame.

### Timing, easing, and springs

Input acknowledgement should be immediate. A longer settling animation can follow while the task stays responsive. Exits should relinquish obsolete visual attention promptly. A frequently repeated operation deserves less ceremony than a rare achievement.

Choose eased timed motion when a predictable duration helps coordinate a presentation. Choose spring motion when continuity through retargeting or gesture release matters, such as a slot move that may change direction. Keep overshoot away from exact decision values and tightly packed targets. A playful bounce on a reward can fit the mood; the same bounce on a precise targeting indicator can obscure the answer.

Use named theme timings rather than unrelated literal delays for every component. Preserve settled text legibility and layout size. If a HUD element pops, animate an inner visual inside a stable holder so the Composition does not interpret the temporary scale as a new space requirement. Do not continuously animate layout measurements to disguise a fit problem.

Respect `motionLevel`: `normal` permits the designed motion, `limited` removes most travel/scale/slide in favor of restrained state changes or fades, and `none` makes presentation and paint changes immediate. Custom transitions and authored effects must be checked explicitly. Reduced motion must preserve the same information and result; it is not a slower version of every animation.

For an opaque page turn, use `fade = false` on the custom transition. Keep the
book and its spine still, and turn a leaf with distinct front and back content.
Keep text at its resting width so it does not reflow as the leaf narrows.
Keep the print visible on the turning face; only the edge should hide it.
Move the back-face print with the leaf's outer edge so the reverse side is
recognizable before it lies flat.
Keep the leaf opaque and above the stationary pages and spine shadow.
Use the same paper gradient at rest and on the fold.
Use the page artwork, fold shape and changing shadow to show depth; a width
wipe alone does not look like paper turning. Check intermediate frames, both
directions and reversal before the turn ends.
Limited motion still uses a short fade; no motion shows the destination at once.

For a page that follows a finger, supply a nullable Compose cell as
`transition.progress`. Native `UIDragDetector` events write normalized progress
directly. Place the detector on a stable parent outside the transitioning page
layers, because Facet blocks page content input during the gesture.
Use `runtime:batch` to start with progress 0 and a provisional destination.
Clear progress to `nil` on release to let the existing Compose tween settle.
Restore the original selection in the same batch when cancelled.
The game supplies distance and velocity thresholds; Facet owns retention,
input gating and motion adaptation. Keep Previous/Next buttons for keyboard
and gamepad. Under reduced motion, defer selection until release.
Read [Custom transitions](../../../../docs/reference/nodes/Custom-transitions.md)
and its journal example before implementing this pattern.
Test a slow hold, a short cancelled drag, direction reversal, a quick flick,
release outside the page, resizing and closing during a drag.

For Sheet, TabView and NavigationStack, use `transition.apply(content, phase)` to bind custom native transforms to `phase.progress`. It runs once in the retained content's owner. Progress moves between absent (0) and present (1), and reverses from its current value when interrupted. `motion` selects a theme duration; `seconds` and `ease` can override it. Facet owns departure lifetime, the optional outer fade and input gating. Limited motion rests the custom transform at 1 and uses a short fade. No motion changes visibility immediately.

This supports a journal page turn, staggered menu rows and item-detail entrances without adding a component for each visual treatment. Bind child delays as portions of the same progress range. Keep the resting geometry responsive. Use images or a Stage for perspective artwork; a 2D scale-and-rotation treatment does not supply true 3D projection. Reusable particles and other engine effects are outside this transition contract. Test a close during entry, a reopen during exit, rapid page changes, owner removal, resizing and focus return.

### CountUp and Flash

`UI.countUp(value)` interpolates a finite number or readable using the theme's `countUp` duration/easing. A new target starts from the current displayed amount; reduced motion shows the new amount immediately. Use it for a reward tally or a summary whose animation clarifies accumulation.

Do not use the interpolated number as the authoritative balance, price, eligibility threshold, or exact live deadline. If the player can spend during the animation, show the accepted spendable amount clearly or finish the tally before presenting that decision. A decreasing health value may need an immediate current meter with a separate trail instead of a slowly arriving answer.

`UI.Flash` takes `target` and progress from zero to one. Its overlay is transient, does not take the target's input, and hides at the endpoints and under reduced motion. A sequence's `sample(progress)` can drive that progress. Keep a durable change—new total, selected state, or status label—after the flash disappears. Reserve repeated emphasis for an unresolved condition that deserves it, not for every incoming event.

### Travel

`UI.Travel` creates one reusable visual through `content()` and moves it when `destination` changes. Its first placement is immediate. It owns the visual's position and size and handles crossing clipping/layout boundaries. Keep destination slots mounted for as long as the item needs them; it cannot land in a destroyed or recycled-away anchor.

Use `path = "straight"` for direct correspondence and `"arc"` when a lifted trajectory improves separation or conveys a deliberate shuffle. Choose `motion = "ease"` for timed travel or `"spring"` for smoothly retargeted movement. `lift` adds scale during flight. `stagger` is a zero-based ripple index multiplied by the theme's travel-stagger duration, not a duration in seconds. Use it to clarify a few arrivals, not to delay a large reward set item by item.

`onStarted` and `onLanded` coordinate presentation. Wait for `onLanded` when a subsequent visual really depends on arrival; a sequence duration matching the expected travel time is not proof of arrival. Keep ownership, reward grants, and inventory truth in the model. Closing the screen, interrupting a flight, or disabling motion must not lose or duplicate the item.

### Sequence

Use `UI.sequence` when several effects have an understandable order. It creates no UI by itself. Each step can use named `delay`/`duration` tokens, named `easing`, `onStart`, `sample(progress)`, `onEnd`, or `parallel` children. Parallel effects should describe the same moment; unrelated effects competing simultaneously flatten attention.

Choose lifecycle behavior deliberately:

- `play()` interrupts the preceding run and starts again. Repeated event delivery therefore needs a policy: combine rewards, queue distinct presentations, or deliberately replace the old one.
- `cancel()` stops samples and suppresses later callbacks. It does not cancel independent control motion already launched by a callback. Keep cancellation safe without relying on an eventual `onEnd` to restore interaction.
- `finish()` applies remaining end states. Use it for a meaningful Skip/Finish action, ensuring callbacks are safe and do not grant the reward again.
- `running` and `completed` expose presentation state; they are not the authoritative record that a game transaction succeeded.
- Reduced motion executes starts, final samples, and ends without waiting. Step callbacks must remain correct when the whole sequence completes immediately.

For an earned-item presentation: accept the reward in the model, show its identity, briefly emphasize it if helpful, change the Travel destination, then show the final inventory/count state. Let Skip expose that same result immediately. If the sequence is interrupted, durable inventory still contains the reward. A player who never watches the animation must still understand what was received and where to find it.

## Verify the motion

Test repeated triggers, retargeting, interruption midway through entry/exit, closing the owner, long content, and normal/limited/no motion. Check that targets, text, focus, and final state remain usable. Compare immediate and animated versions: retain the animation only when orientation, feedback, or the intended experience improves.

Evaluate the result during real interaction, not only playback. A visually pleasing transition can still delay a command, obscure a target, or make state ambiguous. Use the [adaptive interaction checks](ADAPTIVE_INTERACTION_AND_DIRECT_MANIPULATION.md#verify-one-task-across-input-methods) when motion accompanies manipulation.
