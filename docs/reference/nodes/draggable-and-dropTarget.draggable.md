# draggable-and-dropTarget.draggable

`UI.draggable(source, spec)` lets a player pick up a GuiObject, BasePart, or Model.

`UI.dropTarget(target, spec)` lets a GuiObject, BasePart, or Model receive it. Call both
inside a component or a Compose owner; they stop when the owner ends.
World sources use [world drag options](draggable-and-dropTarget.world.md).
For a GuiObject, every input ends in the same drop:

- Pointer: a native `UIDragDetector` with `CustomOffset` recognizes the drag.
  Press the source and move it 6 pixels. A release before that is a
  click, and the source's own activation still happens.
- Touch: a finger that moves first scrolls. Hold the finger still until the
  engine's long press (`TouchLongPress`) to pick the source up; the
  ScrollingFrame under it stops scrolling until the finger lifts.
- While the source is held, an inert copy of it (`DragGhost`) follows the
  pointer at the root of its screen, and the target under the pointer is the
  aim. Release to drop there. The press that became a drag never activates a
  Facet Button, so a drag of a card never opens it.
- Keyboard and gamepad: select the source and press Return or A to pick it up.
  Move the selection into a target and press Return or A to drop. Escape or B
  puts the source back. On a Facet Button source or target this is the
  Button's activation is consumed. Its ordinary `onActivate` does not run.
- `armOnTap = true`: a touch tap on the source picks it up, the list under it
  still scrolls, and a tap on a target drops it. Collection `drag` callbacks
  can return this option to enable the same pickup on a row or grid cell.

While the source is held it has the `facet-drag-held` tag and the
`FacetDragHeld` attribute. Every theme hides its text and icons, so its plate
stays as the empty slot until the drop lands or the source goes back.
With `previewScale`, press feedback starts before pickup. See
the [payload options](draggable-and-dropTarget.payload.md) for its timing and release.

```lua
local sponsors: { [unknown]: number } = {}
local sponsor = { kind = "sponsor", id = 7 }
sponsors[sponsor] = sponsor.id
UI.draggable(card, { payload = sponsor })
UI.dropTarget(slot, {
	accepts = function(payload: unknown)
		if sponsors[payload] == nil then
			return false, "WRONG_KIND"
		end
		return true
	end,
	onDrop = function(payload, info)
		place(payload, info.target)
	end,
})
```

`draggable` spec:
