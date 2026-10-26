## Effect sequences

<!-- aliases: Effect sequences | effect-sequences | UI.shake | shake -->

`UI.sequence(spec) -> Sequence` owns an ordered effect sequence. It creates
no GUI. `steps` is an array of `SequenceStep`. A step accepts:

- `delay` and `duration`: names in `motion.durations`. Omit either for zero.
- `easing`: a name in `motion.easing`, default `sequence`.
- `onStart()` and `onEnd()`: callbacks for the step boundaries.
- `sample(progress)`: eased progress from zero to one on the Compose clock.
- `parallel`: child steps that start from the same point. The group ends
  after its longest child. Its end callback follows all child ends.

The handle has `play()`, `cancel()`, `finish()`, and readable `running` and
`completed` values. `play()` interrupts the previous run at its current
sample and starts a new run. `cancel()` stops sequence samples and suppresses later callbacks.
Motion already started by a callback remains owned by that control. `finish()` applies every remaining end state.
`onCompleted()` on the spec runs after all steps. Compose owns callbacks and
cleanup. Reduced motion runs start, final sample and end in order without
waiting. A game owns durable state and validation in its callbacks.

`UI.countUp(value) -> ReadOnlyValue<number>` interpolates a finite number
with `motion.durations.countUp` and `motion.easing.countUp`, from the current
number. Reduced motion applies the new number at once.

`UI.follow(value, role)` follows a value with the theme spring
`motion.springs[role]`, such as `move`. It moves numbers, `Color3`, `UDim2` and
`Vector2`. `UI.toward(value, target)` is a step `sample` that moves a number
value to `target`.

`UI.Flash { target, progress, color?, mode? } -> Frame` paints a transient
overlay for a GuiObject or readable target. The ownership anchor is empty.
`progress` is a number or readable from zero to one, supplied by a sequence
sample. `mode` is `pulse` (default) or `sweep`. Sweep reveals across the
measured target. Colour defaults to the theme accent. The paint hides at
both ends and under reduced motion. It does not change target paint, parent
or input. Compose owns its portal, observation and paint.

A reward uses `travelStagger` between locks, a parallel sweep and flash, a
`travel` step that changes a Travel destination, `countUp` and a refill. Use
Travel's `onLanded` to wait for placement. No frame loop is needed.

`UI.shake(targets, options?) -> Sequence` creates no GUI. `targets` is a
`{ GuiObject }` array or a readable array. `options.intensity` is a finite,
nonnegative multiplier, default `1`. Zero keeps the targets still.
Call `play()` for each rejected action. All targets use the same phase.
Duplicate targets count once. An empty array is valid.

Shake offsets native `Rotation` about each target's centre. It does not change
Position, Size, AnchorPoint or Parent. Use a face inside a stable layout slot:
native list and grid layouts can override the transforms of their direct children.
Leave room for the rotated face and check clipping in Studio. Keep Rotation
under this effect's control during the run. Do not run two effects on one face.

Each play captures the current rotations. Completion, `finish()`, `cancel()`,
replay and owner cleanup restore those rotations. Replay restores before it
captures again. A readable target change cancels the active run and restores
the old targets. Target destruction also cancels the run. The new array applies
on the next play. Replace the array through its readable; do not mutate it
during a run. Cleanup disables replay.

The theme supplies `motion.durations.shake`, `motion.easing.shake`,
`motion.distances.shakeAngle` in degrees and `motion.materialize.shakeCycles`.
The eased phase drives a sine wave whose amplitude falls to zero. Neutral uses
0.3 seconds, linear easing, 6 degrees and 3 cycles. Shipped themes inherit
these tokens through the theme schema. Limited, none and device reduced motion
complete without movement. A change to reduced motion restores at once.
Keep the rejection reason visible after the effect ends.
