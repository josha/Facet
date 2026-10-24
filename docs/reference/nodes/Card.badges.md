# Card.badges

Card `badges` show item states, such as Owned, Rare or Locked, on the top
corners of the art.

- `badges` is a table with the optional fields `leading` and `trailing`.
- Each badge takes the Badge options `label`, `status`, `icon` and `name`.
  `label`, `status` and `icon` can be a value or a readable. The badge is a
  [Badge](Badge.card.md), so it follows the theme. Without `status`, it has
  the Badge plate.
- The `leading` badge is at the top-left corner of the art. The `trailing`
  badge is at the top-right corner.
- A frame named `Badges` covers the art, above the artwork. Its padding keeps
  both badges `space.s` from the edges of the art.
- A badge with a `label` shows only while the label is a nonempty string. A
  badge without a `label` needs `icon` and `name`, and it always shows. A
  badge with neither is an error when the Card is made.
- A text card, without `image` or `artwork`, does not accept `badges`.
- Keep the labels short, so that the two badges do not touch.
- For a dot or a count on the corner of a Button, use [badged](badged.md).

Do not put Badges in `artwork` with ZStack, Position or ZIndex. Give the item
state to `badges`:

```luau
local owned = Compose.cell({ coast = true })
local card = UI.Card "Kart" {
    title = "Coast Racer",
    image = "rbxassetid://0",
    badges = {
        leading = { label = "Rare", status = "accent" },
        trailing = {
            label = function(use) return if use(owned).coast then "Owned" else nil end,
            status = "success",
            icon = "checkmark",
        },
    },
}
```

Keep the item state in the game model. Here `owned` holds it.
