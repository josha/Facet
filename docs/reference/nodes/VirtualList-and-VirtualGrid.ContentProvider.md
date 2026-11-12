# VirtualList-and-VirtualGrid.ContentProvider

A collection Image preloads its native ImageLabel with `ContentProvider:PreloadAsync`.
A successful fetch or native `IsLoaded` permits reveal. A Stage waits for its scene to be built
and for its media rectangle to be stable. Media fades in over a placeholder
of the surface colour with `reveal.enter` and `easing.fade`. Keep a fixed
media size or use UIAspectRatioConstraint to reserve its slot. Scene creation
does not report when the GPU has completed its first ViewportFrame render.

Facet remembers the image ids that became ready. The memo is for each
ContentProvider, or for each runtime when the config has no ContentProvider.
It keeps the most recently used ids and drops the oldest ids when it is full.
When a recycled row or a new mount shows a remembered id, the image shows
immediately, without the fade. The same applies when
`ContentProvider:GetAssetFetchStatus` reports `Success`. Only a successful
fetch or a change of `IsLoaded` to `true` for the current id adds an id. A
failed or timed-out fetch removes the id. A remembered image still preloads,
and a failure then hides it again. A Stage has no image id, so it always
waits for its scene.

For a bounded tile, set `contentOverflow = "clip"`. Give rendered content
`Size = UDim2.fromScale(1, 1)` and `AutomaticSize = Enum.AutomaticSize.None`.
A larger child keeps its authored size but native clipping limits its paint
and pointer area. Use the default `visible` for lifted Card art.

The returned root is a ScrollingFrame. Compose `OrderedCollection` owns
indexing, window selection, anchor preservation and placement. The control
applies its desired offset to `CanvasPosition`. Sorting keeps the native anchor.
It does not force the first item to the top.

Use a fixed `CanvasPosition` for the initial offset. A reactive binding can
restore an offset when the presentation changes. Do not bind each scroll
observation back to `CanvasPosition`: this can compete with anchor retention.
For VirtualList, VirtualGrid and Outline, `scrollReset` is a string source. Change
its value to return to the top after a sort or filter change. The initial value
does not reset a restored offset. The native root and retained rows stay mounted.
Without `scrollReset`, the collection keeps its visible anchor.

`snap = "item"` settles scrolling to the Compose placement boundaries. The
default is `none`. With `follow = "end"`, the list follows appended rows while
the viewport stays at the end. When a readable `follow` changes, the control
replaces its Compose `OrderedCollection` and mounts the rows again. Keep durable
row state in the model. Other values cause an error.

Optional collection focus uses `focus`, `initialFocus`, `autoFocus`,
`wrapFocus`, `focusPolicy`, `restoreFocus` and `disabled(item)`. A selection
anywhere inside a row, including inside a list nested in that row, moves the
collection's focus to that row. When rows mount or the list scrolls, the
collection selects the focused row again; `restoreFocus = false` leaves the
engine selection alone. `focusPolicy = "key"` (the
default) keeps focus on the item when the order changes. `"index"` keeps it on
the slot, so a live standings list does not walk the gamepad focus up and down.
It moves focus to the item that now holds the slot, or the last slot when the
list shrank, and leaves focus alone while a row is being dragged. With `wrapFocus = true`, `focus.next()`,
`focus.previous()` and the arrow and D-pad actions wrap at the two ends of the
collection. A list wraps only along its scrolling axis. A grid wraps in its row
and its column, with the column count that its layout uses.

Read the full [FocusControls method contract](Collections.focus-controls.md) for returns and lifetime.
