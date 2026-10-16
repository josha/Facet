# Notice.card

Show a persistent status message.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Notice "Notice" { message = "Connection restored", severity = "success" }
```

Key options: `message`, `severity`, `placement`, `actions`.

Use Toast for a transient message.

Related controls: [Controls](Controls.md).

Open:

- [Notice.reference](Notice.reference.md)
