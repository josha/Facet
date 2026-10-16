# CellEditor.CellEditor

Use `UI.CellEditor` in a custom table column, list row or grid item. Each call
returns a new Frame; share the render function and model binding between views.
Do not mount one Instance in two parents.

```luau
local drafts = {}
local function nameDraft(key)
    if not drafts[key] then drafts[key] = Compose.cell(nil) end
    return drafts[key]
end
local function nameCell(current, placement, key)
    return UI.CellEditor {
        editor = "text",
        value = function(use) return use(current).name end,
        draft = nameDraft(key),
        validate = function(value)
            return if value == "" then "Enter a name." else nil
        end,
        onChange = function(value) model.rename(key, value) end,
    }
end
```

Required options are `editor`, `value`, and `onChange(value)`. `editor` accepts
`text`, `number`, `toggle`, or `menu`. Use `options = { { value, label } }` for a
menu and `min`, `max`, `step` for a number. `label` names a text field or toggle.
`enabled = false` or `busy = true` prevents proposals. Set `busy` while the model
validates an asynchronous request, then update `value` on acceptance. The model
remains authoritative; Facet does not mutate a record.

Text and number cells begin as labels. With a mouse, click once to select a
row, then click its value to edit it. Modifier-click keeps the collection's
selection behavior. F2 edits one selected or focused item. Touch and gamepad
show an item-actions button. Gamepad X opens the same menu. These actions are
provided by Facet in lists, grids, tables and outlines, including nested rows.
Use `editLabel` to set the action text (default `Edit value`; built-in table columns use `Edit` and the
column label). A row with several editable fields should give each action a
distinct name. Checkboxes and pickers change their values directly when enabled.

`enabled` is the field permission and `busy` blocks edits while a request is
pending. Neither depends on collection `editing`. For text and number cells,
optional `editing = Compose.cell(false)` controls whether that individual field
is open for input. Keep it outside a virtual row if that state must survive
recycling. It does not grant permission. Without it, the cell owns this state.
Idle labels participate in row selection and do not add a text-field focus stop.
During an edit, Roblox owns text input, the on-screen keyboard and selection.
Return or blur commits; Escape or B cancels. The row remains the navigation
context after the field closes. Active fields keep validation errors available.
