# 17. Composing common controls

Use `local UI, Compose = app.controls, Facet.Compose` inside an application.
These are ordinary screen functions composed from existing controls; no separate
recipe namespace or input wiring is needed. The gallery's **All controls →
Actions → Recipes** page shows all six compositions.

## 17.1 Action rows

Measure the labels with ViewThatFits. Its first candidate hugs a row; its fallback
stacks full-width buttons. Keep Cancel, Save, Delete in the same order, with Save
emphasized and Delete marked destructive. The available width decides the form.

```luau
local function actions(width)
    return {
        UI.Button("Cancel")({ label = "Cancel", role = "cancel", width = width }),
        UI.Button("Save")({ label = "Save changes", appearance = "emphasis", width = width }),
        UI.Button("Delete")({ label = "Delete", role = "destructive", appearance = "utility", width = width }),
    }
end
return UI.ViewThatFits("Actions")({
    width = UI.fill(),
    UI.HStack("Row")({ gap = "s", table.unpack(actions(UI.hug())) }),
    UI.VStack("Column")({ width = UI.fill(), gap = "s", table.unpack(actions(UI.fill())) }),
})
```

For an equal-width row, use HStack with fill-width buttons instead. This is a
separate choice from the measured fit/stack example; long labels still need a
narrow-width reading strategy.

## 17.2 Independent checkbox settings

Keep one caller-owned boolean table. A Toggle callback requests a value; accepting
it means updating the latest table. Ignoring the request leaves model and paint
unchanged. A shared legend and consistent rung/indicator side unite the group.
Use a Picker when exactly one item may be selected.

```luau
local settings = Compose.cell({ tires = true })
local function checkbox(id, label, width)
    return UI.Toggle(id)({
        label = label, presentation = "checkbox", controlSize = "compact",
        indicatorPosition = "leading", width = width,
        value = function(use) return use(settings)[id] == true end,
        onChange = function(requested)
            local next = table.clone(settings:peek())
            next[id] = requested
            settings:set(next)
        end,
    })
end
return UI.VStack("Settings")({ width = UI.fill(), gap = "xs",
    checkbox("tires", "Tire wear"), checkbox("fuel", "Fuel use"),
})
```

The vertical list suits settings labels and hints. Reuse the same helper and model
for a wrapping block: `UI.HStack { wrap = true, gap = "s", checkbox("tires", "Tire wear", UI.hug()), checkbox("fuel", "Fuel use", UI.hug()) }`.
Each item measures its label instead of filling the row; either view updates both.

## 17.3 Wrapping and scrolling chip groups

Use one writable boolean cell per tag. Chip updates that cell, then sends its
optional onToggle notification; it is not a request veto. Rows borrow these
cells, so removing a row does not remove the caller's selection model.

```luau
local tags = Compose.cell({ "Rain", "Night", "Mirror" })
local selected = { Rain = Compose.cell(false), Night = Compose.cell(false), Mirror = Compose.cell(false) }
local function chips()
    return UI.ForEach("Tags")({ items = tags, key = function(tag) return tag end,
        row = function(tag) return UI.Chip(tag)({ label = tag, selected = selected[tag] }) end,
    })
end
return UI.HStack("Tags")({ width = UI.fill(), wrap = true, gap = "s", chips() })
```

For one horizontal rail, put an unwrapped HStack in
`UI.ScrollView("Rail")({ axis="x", width=UI.fill(), height=UI.hug(), ... })`.
Ordinary focus navigation carries the focused chip into view. Keep stable keys
when reordering or removing tags; read a changing row's current third-argument
readable inside `function(use)` bindings when its data is not itself the key.

## 17.4 Empty states

Compose a centered VStack containing an optional semantic Label, a title, a
message, and one soft Button. Empty collection → **Create**, no results →
**Clear search**, and failed load → **Retry** have different explanations and
commands. Each callback changes the caller's model or retries its request.
A loading Skeleton means the answer has not arrived; a Notice reports a transient
condition. Neither replaces the empty page's own explanation and next action.

## 17.5 Divider insets

Pad a plain wrapper; Divider has no content to inset. Use no padding for full
width, `{left="m"}`, `{right="m"}`, or both for the three inset forms. Leave
thickness omitted for the theme hairline; explicitly use `thickness=3` for a
heavier line.

```luau
return UI.VStack("Inset")({ width=UI.fill(), padding={left="m",right="m"},
    UI.Divider("Line")({}),
})
```

## 17.6 Single-open accordion

Give each header one caller-owned boolean cell. DisclosureGroup changes it before
onToggle; opening one closes the others inside the application's batch. Reporting
can derive the open id from these cells instead of keeping another writable id.

```luau
local expanded = { rules=Compose.cell(false), rewards=Compose.cell(false) }
local function section(id, label, content)
    return UI.DisclosureGroup(id)({ label=label, appearance="divided",
        expanded=expanded[id], content=content,
        onToggle=function(open)
            if open then app.runtime:batch(function()
                for other, cell in expanded do if other~=id then cell:set(false) end end
            end) end
        end,
    })
end
```

After an activation, at most one section is open; closing that section leaves
none. The activated header keeps focus. The callback batch does not enclose the
control's earlier write, so this recipe does not promise atomicity to arbitrary
observers between the write and notification.

## 17.7 Containers without a View

Facet has no catchall `View`. Every container job is an existing primitive, and
the gallery's **Motion and layout → Layout → Containers** tab shows each one.

| Job | Use |
|---|---|
| A styled group | `UI.Box` or `UI.ZStack` with a `surface`, or a `tint` for a flat face |
| One activation | a `UI.Button` inside the group; `enabled = false` on the group disables everything under it |
| Size | `{ type = "fixed" }`, `percent`, `UI.fill()`, `UI.hug()`, and `UI.frame(bp, { minWidth = … })` for a floor. A fixed axis lets a larger child overflow; a hugging axis grows to fit it |
| Aspect ratio in a known box | size the subject from the box: `width = 96 * math.min(1, r)`, `height = 96 / math.max(1, r)`, centred in the 96 × 96 parent |
| Scale | `scale` on a `ZStack` paints larger or smaller; the solved rect and the tap target stay where layout put them |
| Group opacity | `opacity` on a `Box` or `ZStack` fades the subtree as one group. At `0` it is still laid out, focusable and tappable; use `hidden` to remove all three |
| Direction, alignment, gap, padding | `HStack` / `VStack`; `alignH` / `alignV` (`start`, `center`, `end`) move a child through spare room, so a hugging parent has none to give; `gap` spaces siblings without insetting them; `padding = { left = 32, top = 8, right = 8, bottom = 8 }` moves only the edges it names |
| Wrap and clip | `wrap = true` on a stack moves children to the next line; without it a row overruns its parent. `overflow = "clip"` cuts at the edge; a `ScrollView` with `axis = "x"` keeps an unwrapped row reachable |
| Rounding, border, shadow | `UI.corners(bp, { topLeft = 16, bottomRight = 16 })` (unset corners are 0; an engine without per-corner radii rounds every corner with the largest), `UI.stroke` (drawn inside the box), `UI.shadow` (drawn where the engine has `UIShadow`, data otherwise) |

```luau
local function contain(id, ratio)
    return UI.ZStack(id)({ width = { type = "fixed", px = 96 }, height = { type = "fixed", px = 96 },
        alignH = "center", alignV = "center",
        UI.Image("Art")({ image = art, scaleMode = "crop",
            width = { type = "fixed", px = 96 * math.min(1, ratio) },
            height = { type = "fixed", px = 96 / math.max(1, ratio) } }),
    })
end
```

Colour, stroke, radius and shadow values come from the theme's tokens (`accent`,
`hairline`, `raised`, …). A game that wants a larger named catalog adds it to its
own theme package rather than to these calls.
