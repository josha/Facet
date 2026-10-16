### adjustable

`UI.adjustable(node, options)` gives a game control the keyboard and gamepad
adjustment of the Slider and the Stepper. `UI.adjustable` makes `node` the
selection stop; give it no selectable descendants. While the selection is on
`node`, Comma and Period and L1 and R1 call `onAdjust(-1)` and `onAdjust(1)`,
and the arrows and the left stick on `axis` do too. The other axis keeps
moving the selection. Call it inside a component or a Compose owner; it stops
when the owner ends.

| Option | Effect |
|---|---|
| `onAdjust(direction)` | Required. `direction` is -1 or 1. |
| `axis` | `"horizontal"` (the default) takes Left and Right, `"vertical"` takes Up and Down, `"none"` takes no arrows and leaves only the shoulders. |
| `repeats` | `true`: a held key or button adjusts again after 0.4 seconds, then every 0.1 seconds, like the built-in value controls. The default is `false`: one step for each press. |
| `canAdjust(direction, use?)` | Optional. `false` makes a press of that arrow do nothing, for example at a limit; the arrow still belongs to the node while it is selected. |
| `enabled`, `disabled`, `busy` | Values or readables. A disabled control takes no keys. |

The actions have the priority of the built-in value controls, so a higher
priority gameplay context still wins, and a held repeat stops when it does.
An unknown `axis` causes an error.

```luau
local angle = Compose.cell(0)
local function turn(direction: number)
	angle:set(angle:peek() + direction * 15)
end
local row = UI.HStack "Turn" {
	UI.Button "Left" { label = "Turn left", onActivate = function() turn(-1) end },
	UI.Button "Right" { label = "Turn right", onActivate = function() turn(1) end },
}
UI.adjustable(row, { onAdjust = turn, axis = "none", repeats = true })
```
