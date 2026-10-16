#### Proposals and commits

The value belongs to you. A pick sends a proposal to `onChange` or
`onRangeChange`. The calendar shows only the value that you then hold. If you
refuse a pick, the calendar does not change.

Without `draft`, each change commits at once. A pick, a time step and a typed
date each call `onCommit`. A single pick without `time` also closes the panel.
In a range, the first pick sets `start`. The second pick sets `finish`. If the
second day is earlier, the two ends change places. `onRangeCommit` runs only
when both ends are set. B, Escape and a tap outside close the panel and keep
the value.

With `draft = true`, only Apply commits. Typed text also only proposes. Each
other way out proposes the value that the panel opened with. Cancel does this
too. Reset all proposes an empty value. If you write the value while the panel
is open, your value becomes the value that Cancel restores.

A pointer or a finger can drag the start or the end of a complete range. Each
move proposes a new range. If the end crosses the other end, the two ends
change places. The release commits once, as the draft rules permit. A cancelled
drag proposes the range that the drag started from. A press on another day
does not start a drag, so a tap there still picks.
