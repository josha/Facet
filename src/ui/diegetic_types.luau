--!strict
local Types = require("./types")
export type DiegeticScreenProps = {
	layers: { ScreenGui },
	isPresented: Types.Value<boolean>,
	scene: () -> Instance,
	surface: Types.Input<CFrame>,
	bounds: Types.Input<Vector2>,
	camera: Types.Input<CFrame>,
	fieldOfView: number?,
	motion: string?,
	onUnavailable: ((string) -> ())?,
}
return {}
