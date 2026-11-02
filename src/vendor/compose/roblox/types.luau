--!strict

local Codec = require "../core/animation/codec"

export type Viewport = { width: number, height: number }

export type ViewportOptions = {
	minimumSide: number?,
	fallback: Viewport?,
}

export type PreferredInputClass = "Touch" | "KeyboardAndMouse" | "Gamepad"

export type PreferredInputSpec = {
	class: PreferredInputClass,
	token: string,
}

export type Connection = {
	Disconnect: (self: Connection) -> (),
}

export type Destroyable = {
	Destroy: (self: Destroyable) -> (),
}

export type Signal<Args... = ...unknown> = {
	Connect: (self: Signal<Args...>, handler: (Args...) -> ()) -> Connection,
}

export type Vector2 = { read X: number, read Y: number }
export type Vector3 = { read X: number, read Y: number, read Z: number }
export type Color3 = { read R: number, read G: number, read B: number }
export type UDim = { read Scale: number, read Offset: number }
export type UDim2 = { read X: UDim, read Y: UDim }
export type CFrame = { GetComponents: (self: CFrame) -> ...number }
export type Instance = {
	ClassName: string,
	Name: string,
	Parent: unknown,
	Destroy: (self: Instance) -> (),
	SetAttribute: (self: Instance, name: string, value: unknown) -> (),
	GetPropertyChangedSignal: (self: Instance, name: string) -> Signal<()>,
}
export type DataModel = {
	GetService: (self: DataModel, name: string) -> unknown,
}

export type Datatypes = {
	read Vector2: ((x: number, y: number) -> Vector2)?,
	read Vector3: ((x: number, y: number, z: number) -> Vector3)?,
	read Color3: ((r: number, g: number, b: number) -> Color3)?,
	read UDim: ((scale: number, offset: number) -> UDim)?,
	read UDim2: ((xScale: number, xOffset: number, yScale: number, yOffset: number) -> UDim2)?,
	read CFrame: ((position: { X: number, Y: number, Z: number }, rotation: { number }) -> CFrame)?,
}

export type Engine = {
	read new: (className: string) -> Instance,
	read readProperty: ((object: unknown, key: string) -> unknown)?,
	read writeProperty: ((object: unknown, key: string, value: unknown) -> ())?,
	read heartbeat: Signal<number>,
	read clock: () -> number,
	read typeName: (value: unknown) -> string,
	read destroy: (object: unknown) -> (),
	read propertyChanged: (object: unknown, property: string) -> Signal<()>,

	read datatypes: Datatypes,
	read readCFrame: ((value: CFrame) -> (number, number, number, { number }))?,
}

export type Codecs = {
	Vector2: Codec.Codec<Vector2>?,
	Vector3: Codec.Codec<Vector3>?,
	Color3: Codec.Codec<Color3>?,
	UDim: Codec.Codec<UDim>?,
	UDim2: Codec.Codec<UDim2>?,
	CFrame: Codec.Codec<CFrame>?,
}

export type Source = {
	read datatypes: Datatypes,
	read readCFrame: ((value: CFrame) -> (number, number, number, { number }))?,
}

return {}
