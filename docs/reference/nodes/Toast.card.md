# Toast.card

Show a transient result.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Toast "Toast" { message = "Settings saved" }
```

Key options: `message`, `action`, `key`, `isPresented`.

A bound toast that can close itself needs onPresentedChange.

For a one-shot result, use `app.presentToast`; it stops the toast's mount on
retirement. `UI.Toast` keeps its empty anchor while its component stays mounted.
See [Tasks.notices](Tasks.notices.md) for the result pattern.

Related controls: [Controls](Controls.md).

Open:

- [Toast.reference](Toast.reference.md)
