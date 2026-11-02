--!strict
local Types = require("./types")
export type DiegeticScreenProps = {
	read layers: { ScreenGui },
	read isPresented: Types.Value<boolean>,
	read scene: () -> Instance,
	read retainScene: boolean?,
	read surface: Types.Input<CFrame>,
	read bounds: Types.Input<Vector2>,
	read camera: Types.Input<CFrame>,
	read fieldOfView: number?,
	read motion: string?,
	read interactive: boolean?,
	read onUnavailable: ((string) -> ())?,
}
return {}
