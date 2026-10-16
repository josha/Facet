#### The calendar

<!-- aliases: The calendar | the-calendar -->

The `Calendar` frame holds these parts in order:

1. `Header`: `Previous`, the `Month` and `Year` menus, and `Next`.
2. `Panes`: `Pane1`, and `Pane2` for a wide range picker. Each pane holds
   `Weekdays` and `Days`, with 42 day buttons `D1` to `D42`.
3. `PageHint`: the page keys, only while the preferred input is a gamepad.
4. `Time`: the `Hour` and `Minute` number fields, and `Half` (AM and PM) on a
   12-hour clock. On touch, it also holds the `Times` list.
5. `Presets`: one chip for each preset, named `Preset-<id>`.
6. `Actions`: `ResetAll` at the leading edge, then `Cancel` and `Apply` in the
   `Commit` row. A sheet without `draft` shows `Done`.

A single date shows one month. A range shows two consecutive months when the
width holds them. The title of each month shows only with two months.

A day outside `min` and `max`, or refused by `isDateDisabled`, stays in the
grid. It is selectable, its label ends with "unavailable", its `Strike` line
shows, and a press does nothing. A day of the next or the previous month is
dim. A press chooses it, but it is not selectable.

The month menu disables a month outside the bounds. The year menu lists the
years up to 50 before and 50 after the shown year, and only the years inside
`min` and `max`. Pick an end year to reach years further away. Each menu opens with the selection on the shown month or year.
A choice moves the calendar to the nearest month inside the bounds. `Previous`
and `Next` stop at a month that is fully outside the bounds.

The day buttons use native GuiService selection. The arrow keys and the
D-pad move one day or one week. Right on the last day of a week moves to the
next day. Left and Right page the month past the first or the last day. Up and
Down move across the shown months. From the first row, Up goes to the `Month`
menu. From the last row, Down goes to the `Hour` field, else to the first
action, else to the next control below. L1, R1, Comma and Period page the
month from each day. When selection enters the grid from another control, it
goes to the chosen day, else to today.

`time` adds the `Hour` and `Minute` fields. Their step buttons follow the
minute grid. The top minute is the last step before 60. `Half` changes between
AM and PM. On touch, the `Times` list shows each time on the minute grid. It
opens at the held time, else at the time of `clock()`.
