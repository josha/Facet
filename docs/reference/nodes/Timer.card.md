# Timer.card

Show time to a deadline.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Timer "Timer" { deadline = os.clock() + 60, now = os.clock }
```

Key options: `deadline`, `start`, `now`, `onComplete`.

Use the same clock for deadline and now.

Related controls: [Controls](Controls.md).

Open:

- [Timer.reference](Timer.reference.md)
