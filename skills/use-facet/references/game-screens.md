# Game screens

Recipes for the screens most games share. Each names its footprint, its
controls and the mistakes that read as unfinished. Adapt the content and keep
the relationships. Read this before building the first screen; it replaces
reading node pages for these choices.

## Rules for every screen

- **Show the options of a small fixed choice.** Up to four short options are a
  segmented `UI.Picker { style = "segmented" }`. Swatches, decals, tags and
  categories are `UI.Chip`s in `UI.HStack { width = "fill", wrap = true }`. A
  Button that cycles its own label ("Shade / 100%") hides the other options.
- **Rows that wrap, not columns.** `AdaptiveStack` is for two or three actions;
  when its row does not fit it becomes one item per row, which is how swatches
  and filters end up as a narrow column in a wide panel. Facet.review reports
  this as `stacked-choices`.
- **One title and one close route per surface.** The NavBar or Sheet header
  owns the title, Back and Close. Do not add a footer "Close / Back" button.
- **Key hints are hints.** Give a Button `shortcutHint = action`; never write
  the key into the label ("Standings / L"). A slash between two words in one
  label is two facts.
- **Destinations are pages.** Shop, garage, livery, upgrades and other places
  the player browses are `UI.Screen` pages in one `NavigationStack`, with
  `surface` so the plate reaches the screen edge. A `UI.Sheet` is for a
  confirmation, a quick pick or a short glance. A fixed-width window over the
  hub wastes a wide screen and clips on a phone.
- **The current choice is marked by more than a tint.** Declare `selection`
  and `onSelection` in the theme palette (see [game themes](game-themes.md));
  Chip, Picker and Collection then draw the chosen item in that color.

## Hub

A `UI.Composition` over the live world, not a panel.

- `topLeft`: game mark and the player's level. `topRight`: both currencies as
  `numeral` values with their glyphs, each its own element.
- `bottomRight` (or `bottom` in portrait): the primary action, large, in
  `appearance = "emphasis"`, with the next race or mode as its subtitle.
- Four or more destinations: a persistent bar in `bottomLeft` or `bottom` of
  circle Buttons with `icon` and `caption` (`car` Garage, `bag` Shop, `wrench`
  Upgrades, `gift` Rewards, `person` Drivers, `settings` Settings), plus a
  `Badge` for a ready reward. The bar stays while the world shows.
- Keep the centre of the view clear. A welcome or status line is a `Toast`.

## Shop and other catalogues

A Screen page with the [Collection](../examples/collection.luau) structure.

- Category: a segmented Picker or Chips above the grid, with the result count.
- Each item: its subject or a theme glyph, the name in `strong`, the one fact
  that matters (effect or stat) as a numeral with a caption label, and the
  price on the Button itself: `UI.Button { label = "Buy", subtitle = "1,200 C" }`.
  Owned and equipped are quiet states, distinct from Buy; unaffordable shows
  the shortfall.
- Purchases confirm in a Sheet with the item, the full price and Cancel.

## Garage, inventory and other browse-and-inspect screens

Collection beside its detail when the page is 900 or more wide; on a narrow
page the detail is the next step with Back.

- Filters are one row above the list and span the page: a search
  `UI.TextInput`, then menu Pickers and Clear in a wrapping row:

```luau
UI.HStack "Filters" { width = "fill", wrap = true, gap = "s",
    UI.Picker "Class" { style = "menu", valueAlignment = "start", selected = class, options = classOptions },
    UI.Picker "Rarity" { style = "menu", valueAlignment = "start", selected = rarity, options = rarityOptions },
    UI.Picker "Sort" { style = "menu", valueAlignment = "start", selected = order, options = orderOptions },
    UI.Button "Clear" { label = "Clear search", onActivate = clearSearch },
}
```

- Never put filters in a column beside the list.
- The detail leads with the subject (a `UI.Stage` model or image), then the
  name, then two to four stats as numeral blocks, then one emphasis action
  ("Race this kart"). Secondary actions share one row below it.

## Customize: livery, outfit, loadout colors

Preview beside the controls on a wide page; preview above them in portrait,
190 to 240 tall, so the first choices show without scrolling.

```luau
local function swatch(color: Color3): Frame
    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(20, 20)
    dot.BackgroundColor3 = color
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
    return dot
end
local chips = {}
for index, paint in PAINTS do -- { value, label, color }
    chips[index] = UI.Chip(paint.value) {
        label = paint.label,
        leading = swatch(paint.color),
        selected = C.formula(function(use) return use(draft).body == paint.value end),
        onToggle = function() setDraft("body", paint.value) end,
    }
end
UI.VStack "Body" { width = "fill", gap = "s",
    UI.Text { text = "Body color", textRole = "label" },
    UI.HStack "Swatches" { width = "fill", wrap = true, gap = "s", table.unpack(chips) },
}
```

- Shade is a segmented Picker; decals are Chips. Bind the preview's parts to
  the draft so every choice changes the subject at once.
- One row ends the form: "Unsaved changes" in caption, Revert, and Save in
  emphasis. Leaving with unsaved changes asks in a Dialog.
- `UI.ColorPicker` is for free color: it shows RGB, HSV and hex fields. Use it
  only when the player may pick any color, not for a named palette.

## HUD during play

A Composition with corner regions: position as a large numeral with its
total in caption (`topLeft`), lap and time (`topRight`), boost or energy as a
bar near the thumb that uses it. On a phone nothing sits in the centre or over
the touch controls; the standings open from a circle Button with a
`shortcutHint`. Read [HUD-actions](../../../docs/reference/nodes/HUD-actions.md)
for gamepad routes.

## Tutorial and first use

A `UI.Callout` anchored to the live target, with the step ("2 of 5"), Back,
Next and `closeButton`. Mount a new Callout when the step changes. Never cover
the highlighted action or centre a panel over the hub.

## Results and settings

Results: [Outcome](../examples/outcome.luau). Settings: [Settings](../examples/settings.luau).
