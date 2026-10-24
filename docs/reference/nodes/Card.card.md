# Card.card

Show a collection item with actions.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Card "Card" {
    title = "Kart",
    image = "rbxassetid://0",
    badges = { trailing = { label = "Owned", status = "success", icon = "checkmark" } },
}
```

Key options: `title`, `image`, `onActivate`, `primaryAction`, `menu`, `badges`.

Facet shows item states, such as Owned or Rare, as `badges` on the top corners
of the art. Do not put Badges in `artwork` with ZStack, Position or ZIndex.

A card without `primaryAction` and `menu` ends at its body. In a selectable
collection, the card shows the selected color on its own plate.

Keep durable item state in the model.

Related controls: [Controls](Controls.md).

Open:

- [Card.reference](Card.reference.md)
