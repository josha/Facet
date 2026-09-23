# Practical recipes

## Confirm a destructive command

Keep presentation state in a cell. An Alert dismisses before calling the selected action, and restores surviving previous selection.

```luau
local confirm = Compose.cell(false)
return Host.Frame {
    UI.Button { label = "Delete", onActivate = function() confirm:set(true) end },
    UI.Alert {
        isPresented = confirm,
        title = "Delete this draft?",
        message = "This removes the saved draft.",
        actions = {
            { id = "cancel", label = "Keep draft", role = "cancel" },
            { id = "delete", label = "Delete", role = "destructive", onActivate = deleteDraft },
        },
    },
}
```

## Filter a large list

```luau
local query = Compose.cell("")
local visible = Compose.formula(function(use)
    local term = string.lower(use(query))
    local result = {}
    for _, item in use(items) do
        if string.find(string.lower(item.title), term, 1, true) then
            table.insert(result, item)
        end
    end
    return result
end)
local list = UI.VirtualList {
    from = visible,
    key = function(item) return item.id end,
    itemSize = 48,
    render = function(current)
        return UI.Button {
            label = function(use) return use(current).title end,
            onActivate = function() openItem(current:peek().id) end,
        }
    end,
}
```

Mount `list` beside a TextInput bound to `query` using native layout. Keep selected ids and row drafts in the shared model. Let Compose preserve the collection anchor after filtering and sorting.

## Retain a drill-down path

```luau
local path = Compose.cell({})
return UI.NavigationStack {
    path = path,
    root = { title = "Catalog", content = Catalog },
    destinations = {
        item = {
            title = "Details",
            content = function(entry) return ItemDetails(entry.value) end,
        },
    },
}
```

Push `{ id = "item", value = itemId }` into `path` from the catalog action. The control uses Compose LayerStack and owns Back behavior. Do not keep a separate presenter stack.
