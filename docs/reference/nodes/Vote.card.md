# Vote.card

Show an up or down vote.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Vote "Rating" { value = "none", onChange = function(value) print(value) end }
```

Key options: `value`, `onChange`, `summary`, `readOnly`.

The game owns the server vote.

Related controls: [Controls](Controls.md).

Open:

- [Vote.reference](Vote.reference.md)
