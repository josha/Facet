# draggable-and-dropTarget.operation

- `operation`: `"move"` by default; also accepts `"copy"`, `"apply"`, or a
  readable value. An explicit source operation list must include it.
- `accepts(payload, info) -> (legal, reason?)`: checked during hover and at
  release. Rejection calls `onReject(payload, reason)` without calling `onDrop`.
- `onDrop(payload, info)`: required. Return `true` or nothing after a synchronous
  command, `false` on rejection, or `"pending"` for an asynchronous command.
  For pending work, call `info.complete(true)` **before** changing the model.
  Change the model only if it returns true. It revalidates and succeeds once.
  Call `info.complete(false, reason)` for rejection. Cancelled or late replies
  return false. Keep server authority and durable requests in the game model.
- `onEnter(payload)`, `onLeave(payload)`, and
  `onUpdate(payload, info, accepted, reason)` report target feedback.
- `focusTarget`: a GuiObject that chooses this destination with Return/A or a
  tap. This gives world objects the same non-pointer drop command.
- `passThrough(payload)`: explicitly routes unmatched payloads past this target
  to an enclosing target. A rejected target otherwise blocks the drop.

`info` contains `source`, `target`, `mode`, `operation`, `position`, `hit`,
`insertion`, and `complete`. `mode` is `"pointer"` or `"armed"`; `hit` is the
native world raycast result. Collection insertion includes `collection`,
`beforeKey`, `afterKey`, and a zero-based `slot` among the remaining items.
Pending insertions resolve their neighbor keys again before completion.

Screen targets use `PlayerGui:GetGuiObjectsAtPosition` in native visual order.
Ghosts are excluded. Visible blocking UI prevents world drops, including rejected
UI targets. A decorative background can explicitly set `FacetDropPassThrough`.
World targeting uses `CurrentCamera:ScreenPointToRay` and `Workspace:Raycast`;
the first hit must belong to a registered target. Camera motion refreshes the
ray. A part in front of a target blocks it. Native `Highlight` shows a world
candidate; UI candidates get an outline. `FacetDropState` is `accepted`,
`rejected`, or `pending`; `FacetDropReason` exposes the rejection reason.
PluginGui has no native GUI hit query; its registered UI targets use clipped
bounds and native ZIndex. Verify overlapping plugin surfaces in Studio.
