### Timer

<!-- aliases: Timer | timer -->

`UI.Timer(spec: TimerProps) -> TextLabel` shows a deadline or elapsed time.
Set exactly one of `deadline` or `start`. Each accepts a number, a Compose
readable or a function of `use`. A changed value updates the same label.
Times and clock results must be finite.

`now: (() -> number)?` defaults to `runtime.host.frames.now`. Use the same
clock and time unit as the deadline or start. For a server deadline, pass a
clock that reads server time. Remaining time rounds up; elapsed time rounds
down. A future start shows zero until a full elapsed second has passed.
`hours = true` forces the hours field. `textRole` selects a theme type role.
Native TextLabel properties, events, children and `ref` also apply. Timer uses
Text and leaves the font to the theme.

The Compose scheduler updates each displayed second and stops at completion.
Unmount cancels scheduled work. `onComplete()` runs once when a deadline is
reached, including an expired initial deadline. A changed deadline starts a
new completion cycle. Elapsed timers do not complete. To bind completion,
pass a `TimerControls` table as `controls`. The control sets its `completed`
field to a readable boolean and clears the field on unmount. Completion is a
display signal; the game owns round state and server validation.

```luau
local timer: Facet.TimerControls = {}
local roundDeadline = Compose.cell(os.clock() + 77)
UI.Timer "Round" {
    deadline = roundDeadline,
    now = os.clock,
    controls = timer,
    onComplete = function() print("Time reached") end,
}
UI.Text { text = function(use) return if use(assert(timer.completed)) then "Round complete" else "Playing" end }
```
