# Sheet.card

Show temporary modal details.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Sheet "Sheet" { title = "Details", isPresented = Facet.Compose.cell(true), content = function() return UI.Text { text = "Ready" } end }
```

Key options: `detents`, `placement`, `actions`, `onPresentedChange`.

For a centered task panel, use `placement = "center"`. It shows Close without
a grabber. Use one `hug` detent for short content, or a bounded height for a
collection. Dock at an edge when dragging between task heights helps the player.

The content factory takes no arguments and runs when the Sheet is built.
Changing `isPresented` does not rebuild it. Use Compose branches inside the
content for changing pages; see [State](State.md). Sheet owns scrolling and Back.
Use `onPresentedChange` to guard an unsaved draft before accepting dismissal.

Related controls: [Controls](Controls.md).

Open:

- [Sheet.reference](Sheet.reference.md)
- [Sheet.dismissal](Sheet.dismissal.md)
