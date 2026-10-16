### DateTimePicker

`UI.DateTimePicker(spec)` returns a Frame. The player uses it to choose a
calendar date, a date range, or a date with a time. For a count of days, use
`UI.NumberInput`. For a few fixed dates, use `UI.Picker`.

```luau
local raceDay = Compose.cell({ year = 2026, month = 10, day = 3 })
UI.DateTimePicker "RaceDay" {
    label = "Race day",
    value = raceDay,
    onChange = function(date)
        raceDay:set(date)
    end,
    min = { year = 2026, month = 1, day = 1 },
}
```

The values are civil dates. See [Civil dates](Civil-dates.md). A date has no
time zone, so it does not move a day where the player sees it.

- `selection`: `single` (the default) or `range`. Set it at construction.
- A single picker uses `value`, `onChange(date)` and `onCommit(date)`. A range
  picker uses `range = { start?, finish? }`, `onRangeChange(range)` and
  `onRangeCommit(range)`. The keys of the other mode cause an error.
- `time`: a single picker only. The value also has `hour` and `minute`.
  `minuteStep` is the minute grid. It must divide 60. The default is 5.
  `hourCycle` is 12 or 24. The default comes from `locale`.
- `min` and `max`: inclusive bounds, or readables of them. `isDateDisabled(date)`
  returns true for a day that the player cannot choose.
- `weekStart`: 1 (Sunday) to 7 (Saturday). The default is 1.
- `locale`: `months`, `weekdays` (short names, Sunday first), `order` (`mdy`,
  `dmy` or `ymd`), `separator` and `hourCycle`.
- `clock()`: returns today. The default is the local clock of the player.
  `referenceDate` sets the month that an empty picker opens on.
- `presets`: a range picker only. Each preset is
  `{ id, label, range = function(today) }`.
- `draft`: adds Reset all, Cancel and Apply.
- `style`: `automatic` (the default) or `inline`. Set it at construction.
  `automatic` is a field that opens a calendar panel. `inline` shows the
  calendar in place.
- `format(date)`: the words of the field. A custom `format` turns off typed
  entry. `placeholder` is the text of an empty field.
- `isPresented`, `onPresentedChange(next)` and `onDismiss(reason)`: the open
  state of the panel. The reason is `activate`, `outside`, `cancel`,
  `anchorLost` or `apply`. Without `isPresented`, the control keeps its own
  open state.
- `enabled` and `readOnly`: booleans or readables. A read-only picker can omit
  the change callback.
- The field chrome keys: `label`, `requiredMark`, `hint`, `errorText`,
  `controlSize`, `appearance` and `corners`. See
  [Field chrome](Field-chrome.md).

Open:

- [DateTimePicker.Proposals-and-commits](DateTimePicker.Proposals-and-commits.md)
- [Native-state](Native-state.md)
- [The-calendar](The-calendar.md)
- [The-field](The-field.md)
