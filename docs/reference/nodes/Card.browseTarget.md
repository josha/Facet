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

For a shop or another task with a frequent primary action, use
`reveal = "always"`. A player must not need hover to discover Buy. This keeps
the action visible; it does not connect the collection's browse stop to the
card's action group. Connect collection `onActivate` to `enterActions()` and
return its `RowHit` from `browseTarget` as below. Gamepad A enters the action
group without buying. Back returns to the same browse stop.

```luau
type Item = { id: string, title: string }
local controls: { [string]: Facet.CardControls } = {}
local cards: { [string]: Frame } = {}
local spec: Facet.KeyedCollectionSpec<Item, string> = {
    from = games,
    key = "id",
    columns = 3,
    itemSize = 320,
    measure = true,
    gap = 16,
    onActivate = function(_item, key)
        local entry = controls[key]
        if entry and entry.enterActions then entry.enterActions() end
    end,
    render = function(current, _placement, key)
        controls[key] = {}
        local card = UI.Card {
            image = art,
            title = function(use) return use(current).title end,
            reveal = "always",
            controls = controls[key],
            browseTarget = function()
                local node = cards[key]
                local hit = node and node.Parent and node.Parent:FindFirstChild("RowHit")
                return if hit and hit:IsA("GuiObject") then hit else nil
            end,
            primaryAction = { label = "Play", onActivate = function() play(key) end },
            menu = { items = { { id = "hide", label = "Not interested", onSelect = function() hide(key) end } } },
        }
        cards[key] = card
        Facet.Compose.cleanup(function() cards[key], controls[key] = nil, nil end)
        return card
    end,
}
local grid = UI.VirtualGrid(spec)
```

`games` supplies the item records; `art`, `play` and `hide` belong to the game.
For separate item detail, use the [collection-detail recipe](Tasks.collection-detail.md). Check entering actions, unavailable actions,
Back, filtering the focused item out and returning after a purchase.
