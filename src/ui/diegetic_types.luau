--!strict
local Types = require("./types")
export type DiegeticScreenProps = {
	layers: { ScreenGui },
	isPresented: Types.Cell<boolean>,
	scene: () -> Instance,
	surface: Types.Value<CFrame>,
	bounds: Types.Value<Vector2>,
	camera: Types.Value<CFrame>,
	fieldOfView: number?,
	motion: string?,
	onUnavailable: ((string) -> ())?,
}
return {}
