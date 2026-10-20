--!strict
local Types = require("./types")
local Env = require("./environment_types")

export type Placement = Env.DropPlacement
export type Options<V, K> = {
	from: Types.Value<{ V }>,
	key: (V) -> K,
	placement: (V) -> Placement,
	columns: number,
	rows: number,
	cellSize: Types.ValueNumber?,
	gap: Types.ValueNumber?,
	render: (Types.Readable<V>, K) -> GuiObject,
	drag: ((Types.Readable<V>, K) -> Env.DraggableSpec)?,
	drop: Env.DropTargetSpec?,
	footprint: ((unknown) -> Vector2?)?,
}
return {}
