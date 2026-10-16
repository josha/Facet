# ErrorBoundary.card

Show a fallback when a child fails.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.ErrorBoundary "Guard" { view = function() return UI.Text { text = "Ready" } end, fallback = function() return UI.Text { text = "Try again" } end }
```

Key options: `view`, `fallback`, `onError`.

Do not use it to hide a game validation error.

Related controls: [Controls](Controls.md).

Open:

- [ErrorBoundary.reference](ErrorBoundary.reference.md)
