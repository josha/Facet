# Card.browseTarget

`browseTarget` is a function that returns the browse stop of the card, such
as the `RowHit` of a VirtualGrid cell. `controls` is an optional table. The
card sets `enterActions()`, `leaveActions()`, `diagnostics()` and the readables
`engaged`, `revealed`, `scale`, `lifting` (true while the lift applies) and
`revealExtent` (`{ body }`, the measured root height). `enterActions()` holds the reveal and selects the first eligible
action. It returns false for a disabled or unmounted card, or when no action
is eligible. It never runs the primary action. While the actions are entered,
the action row is a `SelectionGroup` whose selection behavior is `Stop` on all
four sides. Escape or ButtonB leaves the actions and selects the browse stop.
The menu closes first when it is open. A press outside the card also leaves.
When the card is removed or recycled, it releases the entry.

The root has the attributes `FacetReveal`, `FacetRevealed`, `FacetEngaged`,
`FacetHovered`, `FacetFocusWithin`, `FacetPressing`, `FacetBrowsing`,
`FacetEntered`, `FacetMenuOpen` and `FacetBody` (`button` or `informational`).

```luau
local controls = {}
local cards = {}
UI.VirtualGrid {
    from = games,
    key = "id",
    columns = 3,
    itemSize = 320,
    measure = true,
    gap = 16,
    onActivate = function(_item, key) local entry = controls[key]; if entry then entry.enterActions() end end,
    render = function(current, _placement, key)
        controls[key] = {}
        local card = UI.Card {
            image = art,
            title = function(use) return use(current).title end,
            controls = controls[key],
            browseTarget = function()
                local node = cards[key]
                return node and node.Parent and node.Parent:FindFirstChild("RowHit")
            end,
            primaryAction = { label = "Play", onActivate = function() play(key) end },
            menu = { items = { { id = "hide", label = "Not interested", onSelect = function() hide(key) end } } },
        }
        cards[key] = card
        Compose.cleanup(function() cards[key], controls[key] = nil, nil end)
        return card
    end,
}
```
