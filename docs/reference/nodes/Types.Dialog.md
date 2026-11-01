# Types.Dialog

Facet uses the current Luau type solver. In Studio, set Workspace's
`UseNewLuauTypeSolver` property to `Enabled`. Type action arrays and generic
control specs on locals when their item or binding type is ambiguous.

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
the union, with an optional name argument. The root module also exports
the type of each shape, for example `ToggleCellProps` and
`ToggleRequestProps`. Give a spec the type for its binding shape. Native
properties, such as `Parent`, keep their Roblox property types.

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
