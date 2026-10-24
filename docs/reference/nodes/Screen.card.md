# Screen.card

Keep a screen in the safe area.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Screen "Inventory" {
    surface = "surface",
    UI.NavBar "Header" { title = "Inventory" },
    UI.ScrollView "Body" {
        UI.fill(),
        UI.Text { text = "Choose an item", wrap = true },
    },
}
```

Key options: `padding`, `gap`, `surface`.

With `surface`, the plate reaches the glass and the content stays safe. Keep
the app's ScreenInsets. Use it when a store or garage is a new mode that
replaces play for a while. Use a [Sheet](Sheet.card.md) for temporary, modal
focus over the game: a confirm, a quick pick or a short glance.

Use one app and one mounted root.
On a child page, give NavBar an `onBack`. A root page has no Back command.
`UI.fill()` gives the scroll viewport the height below the header; a
full-height body would extend past the page.

Related controls: [Controls](Controls.md).

Open:

- [Screen.reference](Screen.reference.md)
