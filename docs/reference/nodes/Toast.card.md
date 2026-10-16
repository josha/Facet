# Toast.card

Show a transient result.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Toast "Toast" { message = "Settings saved" }
```

Key options: `message`, `action`, `key`, `isPresented`.

A bound toast that can close itself needs onPresentedChange.

Related controls: [Controls](Controls.md).

Open:

- [Toast.reference](Toast.reference.md)
