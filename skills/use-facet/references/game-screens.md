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
- **Destinations are bounded pages over the world.** Shop, garage, livery,
  upgrades and other places the player browses are `UI.Screen` pages in one
  `NavigationStack`, built with the page shell below: a centred panel at most
  about 1000 wide, with the world still visible around it on a wide screen.
  Never paint the whole screen and leave the content in one corner. A
  `UI.Sheet` is for a confirmation, a quick pick or a short glance.
- **Size plates to what they hold.** A plate that stretches across a wide
  page while its content fills one corner reads as empty. Repeated items go
  in a `UI.Grid` whose column count follows the width; a list goes beside the
  selected item's detail.
- **Use Facet icons, not characters.** Give items and destinations an `icon`
  from Icons.names (`bolt`, `car`, `wrench`, `coin`, `gem`, `star`, `trophy`,
  `gift`, `bag`) on a tinted tile; "ϟ" or "◎" in text is not a visual.
- **Repeat the accent where the player acts.** Each affordable Buy and the
  primary action use `appearance = "emphasis"`; Owned and unaffordable are
  quiet. The repeated accent is most of what makes a theme read as that theme.
- **The current choice is marked by more than a tint.** Declare `selection`
  and `onSelection` in the theme palette (see [game themes](game-themes.md));
  Chip, Picker and Collection then draw the chosen item in that color.

## Page shell

Every destination uses this shell. The Screen has no `surface`, so the world
shows at the sides; the panel carries the plate, the title, Back and the
wallet, and only its body scrolls.

```luau
local function page(title: string, back: () -> (), children: { GuiObject }): Frame
    return UI.Screen(title) { padding = "m", align = "center",
        UI.VStack "Panel" { width = "fill", maxWidth = 1000, surface = "surface", padding = "l", gap = "m", UI.fill(),
            UI.NavBar "Header" { title = title, onBack = back, trailing = wallet() },
            UI.ScrollView "Body" { UI.fill(), UI.VStack "Content" { width = "fill", gap = "m", table.unpack(children) } },
        },
    }
end
```

On a phone the panel takes the width and the world shows only at the edges.
Give a long title `wrap = true`; a wide display font needs it at 390.

## Hub

A `UI.Composition` over the live world. Its readouts sit on panels, never
straight on the scene, where signs and lights collide with them.

```luau
local env = UI.environment()
local function bottomClearance(use: Facet.Use): number
    if use(env.interactionClasses).primary ~= "touch" then
        return 16
    end
    -- Roblox draws Jump 90 (small screens) or 210 pixels above the bottom edge.
    return if use(env.thumbTarget) <= 70 then 100 else 220
end
UI.Composition "Hub" {
    padding = function(use: Facet.Use) return { top = 16, left = 16, right = 16, bottom = bottomClearance(use) } end,
    UI.Region "Player" { zone = "topLeft", rank = 2, UI.VStack { surface = "panel", padding = "m", gap = "xs",
        UI.Text { text = "ION CIRCUIT", textRole = "heading" },
        UI.HStack { gap = "s", align = "end", UI.Text { text = level, textRole = "numeral" }, UI.Text { text = "level", textRole = "caption" } },
        UI.ProgressView { value = xp, max = xpForLevel, showValue = false, Size = UDim2.fromOffset(200, 8) },
    } },
    UI.Region "Wallet" { zone = "topRight", rank = 1, UI.HStack { surface = "panel", padding = "m", gap = "m",
        UI.Label { title = credits, icon = "coin", textSize = "numeral" },
        UI.Label { title = gems, icon = "gem", textSize = "numeral" },
    } },
    UI.Region "Destinations" { zone = "bottomLeft", rank = 2, UI.HStack { gap = "l",
        UI.Button "Garage" { icon = "car", shape = "circle", caption = "Garage", onActivate = openGarage },
        UI.Button "Shop" { icon = "bag", shape = "circle", caption = "Shop", onActivate = openShop },
        UI.Button "Upgrades" { icon = "wrench", shape = "circle", caption = "Upgrades", onActivate = openUpgrades },
        UI.Button "Rewards" { icon = "gift", shape = "circle", caption = "Rewards", onActivate = openRewards },
    } },
    UI.Region "Race" { zone = "bottomRight", rank = 1,
        UI.Button "Race" { label = "ENTER RACE", subtitle = "2 laps", appearance = "emphasis", controlSize = "large", onActivate = queue } },
}
```

- On touch the bottom padding lifts every bottom region above the thumbstick
  and Jump; Facet does not measure them. Facet.review reports a control on
  Jump as `touch-control-overlap`.
- Give a ready reward a `Badge` on its destination. A welcome or status line
  is a `Toast`, not text in the centre of the view.
- In portrait, keep two or three destinations and put the rest behind one
  Menu circle; a region's second form is its compact form.

## Shop and other catalogues

The page shell with category Chips and a Grid of item tiles. The column count
follows the width; the tile holds a tinted icon tile, the name, the one fact
that matters and a full-width Buy.

```luau
local function tile(part: Part): Frame
    local tint = SLOT_COLORS[part.slot]
    local glyph = Host.Frame "Glyph" { Size = UDim2.fromOffset(56, 56), BackgroundColor3 = tint, BackgroundTransparency = 0.75,
        Host.UICorner { CornerRadius = UDim.new(0, 10) },
        Host.UIStroke { Color = tint, Thickness = 1.5 },
        UI.Label { title = part.name, icon = part.icon, presentation = "iconOnly", iconSize = 32,
            Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) },
    }
    return UI.VStack(part.id) { surface = "panel", padding = "m", gap = "s", width = "fill",
        UI.HStack "Head" { gap = "m", align = "center", glyph,
            UI.VStack "Name" { gap = 2, UI.Text { text = part.name, textRole = "strong" }, UI.Text { text = part.slot, textRole = "caption" } } },
        UI.HStack "Fact" { gap = "s", align = "end", UI.Text { text = part.value, textRole = "numeral" }, UI.Text { text = part.fact, textRole = "caption" } },
        buyButton(part), -- Size = UDim2.new(1, 0, 0, 0); emphasis when affordable, quiet when owned
    }
end
UI.Grid "Parts" { gap = 12, cellHeight = 210,
    columns = function(use: Facet.Use) return math.clamp(math.floor(use(env.viewportWidth) / 320), 1, 3) end,
    table.unpack(tiles) }
```

- Put the price on the Buy itself ("Buy 450" with `icon = "coin"`); show the
  shortfall when the player cannot afford it ("Need 200 more").
- Purchases confirm in a Sheet with the item, the full price and Cancel.

## Garage, inventory and other browse-and-inspect screens

In the page shell, the list beside the selected item's detail when the
viewport is 900 or more wide; on a narrow page the detail is the next step
with Back.

```luau
local wide = function(use: Facet.Use) return use(env.viewportWidth) >= 900 end
UI.HStack "Body" { width = "fill", gap = "l", align = "start", UI.fill(),
    UI.VStack "List" { gap = "s",
        width = function(use: Facet.Use) return if wide(use) then 360 else "fill" end,
        UI.TextInput "Search" { value = query, placeholder = "Search karts" },
        UI.HStack "Filters" { width = "fill", wrap = true, gap = "s",
            UI.Picker "Class" { style = "menu", valueAlignment = "start", selected = class, options = classOptions },
            UI.Picker "Sort" { style = "menu", valueAlignment = "start", selected = order, options = orderOptions },
        },
        table.unpack(rows), -- one Button per kart: icon, name, class subtitle; the chosen row in emphasis
    },
    C.show(wide, function()
        return UI.VStack "Detail" { UI.fill(), surface = "panel", padding = "l", gap = "m",
            preview, -- UI.Stage, 240 to 280 tall
            UI.Text { text = name, textRole = "title" },
            UI.HStack "Stats" { gap = "xl", stat(speed, "top speed"), stat(steering, "steering"), stat(boost, "boost") },
            UI.Button "Choose" { label = "Race this kart", appearance = "emphasis", Size = UDim2.new(1, 0, 0, 0) },
            UI.HStack "More" { gap = "s", tryButton, favoriteButton, upgradeButton },
        }
    end),
}
```

- Filters are one wrapping row above the list, never a column beside it.
- A stat is a VStack of the value in `numeral` and its label in `caption`.

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

A Composition with corner regions on panels: position as a large numeral with its
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
