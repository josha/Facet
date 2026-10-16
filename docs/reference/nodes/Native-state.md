#### Native state

<!-- aliases: Native state | native-state -->

`ref` receives the root Frame. The root has the `facet-date-time-picker` tag
and these attributes: `month` (for example `2026-09`), `dual`, `route`
(`inline`, `popover` or `sheet`), `presented`, `text`, `typedError` and
`diagnostics`. A readable value that is not a legal date does not change the
picker. The picker keeps the last legal value, adds one to `diagnostics`, and
sends the message to the `onError` factory option.

The theme paints the calendar through these tags: `facet-calendar-day`,
`facet-calendar-band`, `facet-calendar-disc`, `facet-calendar-end`,
`facet-calendar-today`, `facet-calendar-strike`, `facet-calendar-number`,
`facet-calendar-banded`, `facet-calendar-dim`, `facet-calendar-chosen` and
`facet-calendar-chosen-end`. The band is `controlSelected`, and a day number on
it (`facet-calendar-banded`) is `onSelected`.
