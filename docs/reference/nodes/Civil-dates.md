## Civil dates

<!-- aliases: Civil dates | civil-dates -->

`Facet.civilDate` is the calendar that `UI.DateTimePicker` keeps its values in.
A `CivilDate` is `{ year, month, day, hour?, minute? }` in no time zone. A
`CivilRange` is `{ start?, finish? }`.

- Arithmetic: `isLeap(year)`, `daysIn(year, month)`, `toDays(d)` and
  `fromDays(n)` (days from 1970-01-01), `dateOf(d)` (the date without its
  time), `addDays(d, n)`, `addMonths(d, n)`, `compare(a, b)` (by date),
  `same(a, b)` (every field), `weekday(d)` (1 is Sunday),
  `monthGrid(year, month, weekStart)` (six weeks of dates),
  `within(d, min?, max?)`, `clampRange(range, min?, max?)` and
  `problem(d, withTime?)`. `addMonths` clamps the day: January 31 plus one
  month is the last day of February. `clampRange` returns `nil` when the range
  is fully outside the bounds. `problem` returns why a value is not a date, or
  `nil`.
- Words: `format(d, locale?)`, `formatTime(d, hourCycle)` and
  `parse(text, locale?, withTime?)`. They use the numeric order of the locale.
  `parse` returns two values, `(date?, why?)`. Test the date before you use it.
  A year has four digits. On a 12-hour clock, an hour from 1 to 12 needs AM or
  PM. `ENGLISH` is the default locale: `months`, `weekdays` (Sunday first),
  `order` (`mdy`, `dmy` or `ymd`), `separator` and `hourCycle`.
- Instants: `fromUnix(seconds, offsetMinutes)` and
  `toUnix(date, offsetMinutes)` always name their offset. There is no zone
  database. Convert a zone with daylight time to a fixed offset yourself.
  `systemClock(offsetMinutes?)` returns the default clock: the local date and
  time of the player, or the engine clock at the offset that you name.

```luau
local civil = Facet.civilDate
local start = { year = 2026, month = 2, day = 27 }
print(civil.format(civil.addDays(start, 3))) -- "03/02/2026"
local date, why = civil.parse("02/30/2026")
if date == nil then
    print(why)
end
```
