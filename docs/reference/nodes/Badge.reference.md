# Badge

Badge.reference option values and behavior.

An unwrapped label with automatic size keeps its largest measured box while its text keeps the same length, as Text does.

A Badge needs text, or an `icon` with a `name`. While a bound `label` is `nil`
or empty and there is no named icon, the Badge sets `Visible` to false.
`Visible = false` from the author also hides it. A fixed `label` that is `nil`
or empty, without a named icon, is an error when the Badge is made.

| Control | Main contract |
|---|---|
| `Badge` | `label`, `status`, an optional icon and position, appearance, corners and control size. The icon and the label share one pill. The status appearance keeps a neutral pill and shows the status as a leading dot. |
