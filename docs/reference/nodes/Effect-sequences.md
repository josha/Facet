## Effect sequences

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

`UI.countUp(value) -> Readable<number>` interpolates a finite number or
readable using `motion.durations.countUp` and `motion.easing.countUp`. Feed
it to a `UI.Text` formula to format a total. Retargeting starts at the current
number. Reduced motion applies the new number at once.

`UI.Flash { target, progress, color?, mode? } -> Frame` paints a transient
overlay for a GuiObject or readable target. The ownership anchor is empty.
`progress` is a number or readable from zero to one, supplied by a sequence
sample. `mode` is `pulse` (default) or `sweep`. Sweep reveals across the
measured target. Colour defaults to the theme accent. The paint hides at
both ends and under reduced motion. It does not change target paint, parent
or input. Compose owns its portal, observation and paint.

Use `travelStagger` between lock callbacks, a parallel sweep and flash, then
an `onStart` that changes a Travel destination. Use `travel` for that step,
`countUp` for the total and a final refill callback. Use Travel's `onLanded`
when the game must wait for actual placement. The consumer needs no frame loop.
