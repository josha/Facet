# ProgressView.card

<!-- aliases: ProgressView | UI.ProgressView | ProgressBar.card | Progress.card -->

Show measured progress.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.ProgressView "ProgressView" { value = 0.8 }
```

Key options: `value`, `min`, `max`, `presentation`.

Use diameter only with circular or spinner presentation.

Related controls: [Controls](Controls.md).

Open:

- [ProgressView.reference](ProgressView.reference.md)
