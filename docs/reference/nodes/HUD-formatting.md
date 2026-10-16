### HUD formatting

<!-- aliases: HUD formatting | hud-formatting -->

`Facet.format` is a frozen namespace of pure functions. No runtime is required.
All three functions refuse NaN and infinity with an error.

- `compact(value: number, options: CompactOptions?) -> string` uses K, M, B and T.
  `significantDigits` defaults to 3 and accepts whole numbers from 1 through 15.
  It trims trailing decimal zeros and promotes a rounded value to the next suffix.
  For example, 93210 becomes `93.2K`, 2350 becomes `2.35K`, and 999950 becomes `1M`.
  Values above T keep the T suffix. Small fractions can use exponent notation.
- `grouped(value: number, options: GroupedOptions?) -> string` groups digits in
  threes. `decimals` defaults to 0 and accepts whole numbers from 0 through 15.
  It rounds to that decimal count and keeps the decimal zeros. `separator`
  defaults to `,`. The decimal indicator is `.`. These formats do not select a locale.
- `duration(seconds: number, options: DurationOptions?) -> string` clamps below
  zero and discards fractional seconds. It shows `m:ss` below an hour and
  `h:mm:ss` at or above an hour. `hours = true` always shows the hours field.

```luau
UI.Text { text = Facet.format.compact(93210), textRole = "numeral" }
UI.Text { text = Facet.format.grouped(1234567.5, { decimals = 1, separator = "," }) }
UI.Text { text = Facet.format.duration(3723) }
```
