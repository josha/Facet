# Timer.card

Show time to a deadline.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Timer "Timer" { deadline = os.clock() + 60, now = os.clock }
```

Key options: `deadline`, `start`, `now`, `onComplete`.

Use the same clock for deadline and now. `start` counts up and `deadline`
counts down; both update without a loop. For a time inside another label, such
as "Offer 4:51", call `app.runtime.clock { deadline = t, interval = 1 }` inside
the mount. It returns a readable of the seconds left in `os.clock` time. Round
the value up with `math.ceil`, as Timer does.

Related controls: [Controls](Controls.md).

Open:

- [Timer.reference](Timer.reference.md)
