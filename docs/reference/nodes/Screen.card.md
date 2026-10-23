# Screen.card

Keep a screen in the safe area.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Screen "Inventory" {
    UI.NavBar "Header" { title = "Inventory" },
    UI.ScrollView "Body" {
        UI.fill(),
        UI.Text { text = "Choose an item", wrap = true },
    },
}
```

Key options: `padding`, `gap`.

Use one app and one mounted root.
On a child page, give NavBar an `onBack` callback that returns to the previous
task. A root page has no Back command.
The header keeps its height; `UI.fill()` gives the scroll viewport the remaining
height. A full-height body beside a header would extend past the page.

Related controls: [Controls](Controls.md).

Open:

- [Screen.reference](Screen.reference.md)
