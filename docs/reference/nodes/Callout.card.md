# Callout.card

Attach guidance to a control.

Inside an app mount, set `local UI = app.UI`.

```luau
local anchor = UI.Button "Play" { label = "Play" }
UI.Callout "Help" { anchor = anchor, title = "Start here", onRetire = function() print("Seen") end }
```

Key options: `anchor`, `content`, `actions`, `seen`.

Use a live native anchor.

Related controls: [Controls](Controls.md).

Open:

- [Callout.reference](Callout.reference.md)
