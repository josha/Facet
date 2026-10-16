# Effect sequence

The game gives ordered steps. A step can wait, change game presentation,
sample a value, or run children in parallel. The game owns word data, colours,
points, sounds and refill. Compose owns sequence scheduling and cancellation. Facet resolves theme timing tokens.

UI.sequence returns play, cancel, finish, running and completed. Each step
has delay and duration token names, optional easing, onStart, sample and
onEnd. A parallel group starts its children together and ends after its
longest child. A second play cancels the old run at the current sample.
Reduced motion runs start, final sample and end in order without waiting.
Callbacks run in the Compose owner. Cleanup stops the sequence.

Compose runtime.sequence supplies ordered callbacks and parallel groups. runtime.tween supplies numeric interpolation and retargeting for UI.countUp. Facet maps theme tokens to these mechanisms. Do not add another scheduler, task loop, or general motion engine.

Roblox Frame painting supplies a transient GUI flash. UIStroke supplies a
border but cannot paint the sweep.
UI.Flash uses the existing overlay portal, measured GUI bounds and a
progress readable from 0 to 1. It draws one pulse or sweep, then hides.
It never changes the target's paint or input. Highlight.Adornee is for
world geometry, not GUI paint. TweenService cannot order arbitrary callbacks
and parallel groups with Compose ownership. Compose runtime.sequence supplies that scheduling.

Test ordered delays, parallel tracks,
count-up, transient paint, interruption, finish, reduced motion and disposal
on every frame. The Lab reward sequence shows generic cells, a highlight,
a premium flash, Travel to a total, count-up and a final refill callback.
Phone timing and text paint still need native evidence.
