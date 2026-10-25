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
  A badge on the art has a thin edge in its own ink, so it keeps its shape
  on art of the same colour.
- A badge with a `label` shows only while the label is a nonempty string. A
  badge without a `label` needs `icon` and `name`, and it always shows. A
  badge with neither is an error when the Card is made.
- A text card, without `image` or `artwork`, does not accept `badges`.
- When both badges do not fit across the art, the leading badge's label
  moves to the front of the caption, unless the caption already says it, and
  the trailing badge stays. A badge too wide for the art alone, such as a long
  translated label, moves to the caption the same way, so text never leaves
  the card. Put the fact that decides the choice, such as the
  price or Owned, in `trailing`.
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

A shop card carries the decision. The caption says what the item changes,
and the trailing badge shows the price until the player owns the item. Show
every price the same way, in `contrast`, which reads on any art; show what the
player can afford in the detail and its Buy. An owned item needs no badge. A badge with `name` and an
icon shows the icon alone while its label is empty, so Equipped is a named
check:

```luau
local owned, equipped = Compose.cell(false), Compose.cell(false)
local card = UI.Card "Engine" {
    title = "Turbo Engine",
    image = "rbxassetid://0",
    caption = "+12 top speed",
    onActivate = function() print("Open detail") end,
    badges = {
        leading = { label = "Rare", status = "accent" },
        trailing = {
            label = function(use) return if use(owned) then nil else "450" end,
            icon = function(use)
                return if use(equipped) then "checkmark"
                    elseif use(owned) then nil else "coin"
            end,
            name = "Equipped",
            status = function(use) return if use(equipped) then "success" else "contrast" end,
        },
    },
}
```

A text card has no badges; put the price and its state in the caption.
