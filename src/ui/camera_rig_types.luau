--!strict
local Types = require("./types")

export type CameraPose = { focus: Vector3, yaw: number, pitch: number, distance: number }
export type CameraRigOptions = {
	inputRoot: PlayerGui,
	initial: CameraPose,
	focusBounds: { min: Vector3, max: Vector3 },
	yawBounds: Vector2?,
	pitchBounds: Vector2?,
	distanceBounds: Vector2,
	presets: { [string]: CameraPose }?,
	enabled: Types.Input<boolean>?,
	blocked: Types.Input<boolean>?,
	smoothing: boolean?,
	inertia: boolean?,
	orbitSensitivity: number?,
	panSensitivity: number?,
	orbitSpeed: number?,
	zoomSpeed: number?,
}
export type CameraRig = {
	camera: Types.ReadOnlyValue<CFrame>,
	state: Types.ReadOnlyValue<CameraPose>,
	focus: Types.Value<Vector3>,
	preset: Types.Value<string?>,
	reset: () -> (),
}
return {}
