### adjustable

<!-- aliases: adjustable | adjustable -->

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
| `canAdjust(direction, use?)` | Optional. `false` prevents adjustment in that direction, for example at a limit, and leaves that direction free for native selection navigation. |
| `enabled`, `disabled`, `busy` | Values or readables. A disabled control takes no keys. |

The actions have the priority of the built-in value controls, so a higher
priority gameplay context still wins, and a held repeat stops when it does.
An unknown `axis` causes an error.

```luau
local angle = Compose.cell(0)
local function canTurn(direction: number, use: Facet.Use?): boolean
	local value = if use then use(angle) else angle:peek()
	return if direction < 0 then value > 0 else value < 90
end
local function turn(direction: number)
	angle:set(math.clamp(angle:peek() + direction * 15, 0, 90))
end
local readout = UI.VStack "Angle" {
	UI.Text { text = function(use: Facet.Use) return `Angle {use(angle)}°` end },
}
UI.adjustable(readout, { onAdjust = turn, canAdjust = canTurn, repeats = true })
return UI.HStack "Turn" {
	UI.Button "Left" {
		label = "Turn left", onActivate = function() turn(-1) end,
		enabled = function(use: Facet.Use) return canTurn(-1, use) end,
	},
	readout :: unknown,
	UI.Button "Right" {
		label = "Turn right", onActivate = function() turn(1) end,
		enabled = function(use: Facet.Use) return canTurn(1, use) end,
	},
}
```
