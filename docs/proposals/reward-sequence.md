# Effect sequence

The game gives ordered steps. A step can wait, change game presentation,
sample a value, or run children in parallel. The game owns word data, colours,
points, sounds and refill. Facet owns the clock and cancellation.

UI.sequence returns play, cancel, finish, running and completed. Each step
has delay and duration token names, optional easing, onStart, sample and
onEnd. A parallel group starts its children together and ends after its
longest child. A second play cancels the old run at the current sample.
Reduced motion runs start, final sample and end in order without waiting.
Callbacks run in the Compose owner. Cleanup stops the sequence.

Compose runtime.timeline has elapsed, restart, pause and seek. It supplies
one owned motion clock for the whole sequence. runtime.tween already has
numeric interpolation and retargeting; use it for UI.countUp, which returns
a readable number with theme timing. Facet has no count-up label helper.
Compose createSharedResource and boundary manage async work, not ordered
effect tracks. cleanup and withOwner own callbacks and motion. Do not add
another scheduler, task loop or general motion engine.

Roblox Frame painting supplies a transient GUI flash. UIStroke supplies a
border but cannot paint the sweep.
UI.Flash uses the existing overlay portal, measured GUI bounds and a
progress readable from 0 to 1. It draws one pulse or sweep, then hides.
It never changes the target's paint or input. Highlight.Adornee is for
world geometry, not GUI paint. TweenService cannot order arbitrary callbacks
and parallel groups with Compose ownership. Facet adds that small policy.

Prove failure before implementation. Sample ordered delays, parallel tracks,
count-up, transient paint, interruption, finish, reduced motion and disposal
on every frame. The Lab reward sequence shows generic cells, a highlight,
a premium flash, Travel to a total, count-up and a final refill callback.
Phone timing and text paint still need native evidence.
