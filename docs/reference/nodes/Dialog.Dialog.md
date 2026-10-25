# Dialog.Dialog

`UI.Dialog` returns an empty anchor Frame. The panel is a modal surface.

```luau
local open = Compose.cell(false)
runtime.mount(function()
    return Host.ScreenGui {
        UI.Dialog "Leave" {
            isPresented = open,
            onPresentedChange = function(nextValue) open:set(nextValue) end,
            onDismiss = function(reason) print(reason) end,
            title = "Leave the race?",
            content = function() return UI.Text { text = "Your lap will not count." } end,
            actions = {
                { id = "Retry", label = "Retry", keepOpen = true, onActivate = function() print("retry") end },
                { id = "Leave", label = "Leave", role = "destructive", onActivate = function() print("left") end },
            },
        },
    }
end, playerGui)
```

The caller owns `isPresented`. The dialog reads it and never writes it. The
close button, Cancel and a tap on the backdrop call `onPresentedChange(false)`.
The dialog closes only when the fact changes. A refused proposal keeps the same
panel and selection. A dialog with `actions` has no close button: ButtonB
and Escape run its `cancel` action. A dialog without actions shows one;
`closeButton = true` or `false` decides either way. A dialog that shows a
close button needs `onPresentedChange`. Without `onPresentedChange`, the
backdrop and Cancel do nothing.

An action press closes the dialog by default. It runs its `onActivate`, and
then proposes `onPresentedChange(false)`, as the close button does, so a
refused proposal keeps the dialog open. An accepted close reports `action`, and
so does a false that the caller accepts in the callback. An action with
`keepOpen = true` runs its `onActivate` and proposes nothing. Use it for Apply
or Next. An action that raises an error proposes nothing. Sheet, Notice
and Callout actions refuse `keepOpen`. Cancel runs an enabled `role = "cancel"`
action first. Otherwise Cancel proposes false. The one
`role = "default"` action answers Return and has the `emphasis` appearance.
A `destructive` action keeps the danger color. Cancel and the other actions
keep the `standard` appearance. A disabled or busy action does not run.
`onDismiss(reason)` reports each closure once, after its cleanup:
`close`, `outside`, `cancel` or `action`. The caller's own false and owner
disposal report `cancel`. A failing callback is raised after the dialog state
is consistent.

The panel hugs its content. When the content cannot leave `space.xl` clear
above and below, as on a phone in landscape, the panel fills the safe area and
keeps its content at the dialog width, so page controls behind it cannot read
as its own.

Other options:
