# Types.Dialog

The new solver gives a type to the literal items of `Dialog` and `Sheet`
action arrays without a local. It does not select a member of a union
item type, such as `MenuItem` and `RadialItem`, for a literal item. It also
does not infer the value type of a generic constructor, such as `Menu`,
`Picker`, `RadialMenu` and `Alert`, through a reactive option. These calls
need the old solver for a check without casts.

```luau
local open = Compose.cell(true)
local function close()
    open:set(false)
end
local actions: { Facet.DialogAction } = {
    { id = "stay", label = "Stay", role = "cancel", onActivate = close },
    { id = "leave", label = "Leave", role = "destructive", onActivate = close },
}
local stop = runtime.mount(function()
    return UI.Dialog { isPresented = open, title = "Leave the race?", actions = actions }
end, playerGui)
stop()
```

A cell of an optional or literal type takes its type from a typed initial
value: `local initial: string? = nil` and then `Compose.cell(initial)`.

`Toggle`, `TextInput`, `NumberInput`, `Stepper`, `Slider`, `Rating`,
`LevelPicker`, `Chip`, `ShortcutHint` and `Picker` accept one of several
binding shapes. Their constructors have one overload for each shape and one for
the union, in the direct and in the named form. The root module also exports
the type of each shape, for example `ToggleCellProps` and
`ToggleRequestProps`. In the old solver, a native Instance property of these controls,
such as `Parent`, takes only a value of that exact class. The new solver checks
the first shape (a writable cell) without casts. It does not check the other
shapes or the items of union typed arrays without casts.

Drag callbacks receive an `unknown` payload. This includes
`DraggableSpec.onStart` and the payload argument of every `DropTargetSpec`
callback. Check the payload type before you read its fields. A game must check
its own payload schema and server rules.

`SliderOptions.onCommit` accepts a number callback or a `SliderRange` callback.
The range callback also receives `SliderChange`. `SliderImplementationProps`
uses the same two value types for `onChange`. `TextInputImplementationProps`
uses a string callback with `TextCommitReason`, or a number callback with
`CommitReason`. The public `TextInputProps` and `SliderProps` retain their
presentation and range bindings.

The native `Host` type includes `Highlight`. Its props use the pinned Roblox
property types, including `Adornee`, `Enabled`, `DepthMode`, fill and outline
colors, and transparency. This adds a type for the existing native constructor.
