--!strict
--!nolint DeprecatedApi

export type Connection = {
	Disconnect: (self: Connection) -> (),
}

export type Destroyable = {
	Destroy: (self: Destroyable) -> (),
}

export type Signal<Args... = ...unknown> = {
	Connect: (self: Signal<Args...>, handler: (Args...) -> ()) -> Connection,
}

export type Vector2 = { X: number, Y: number }
export type Vector3 = { X: number, Y: number, Z: number }
export type Color3 = { R: number, G: number, B: number }
export type UDim = { Scale: number, Offset: number }
export type UDim2 = { X: UDim, Y: UDim }
export type CFrame = { GetComponents: (self: CFrame) -> ...number }
export type Instance = {
	ClassName: string,
	Name: string,
	Parent: unknown,
	Destroy: (self: Instance) -> (),
	SetAttribute: (self: Instance, name: string, value: unknown) -> (),
	GetPropertyChangedSignal: (self: Instance, name: string) -> Signal<()>,
}
export type PropertyObservable = { GetPropertyChangedSignal: (self: PropertyObservable, name: string) -> Signal<()> }
export type DataModel = { GetService: (self: DataModel, name: string) -> { Heartbeat: Signal<number> } }

export type Engine = {
	new: (className: string) -> Instance,
	heartbeat: Signal<number>,
	clock: () -> number,
	typeName: (value: unknown) -> string,
	destroy: (object: unknown) -> (),
	propertyChanged: (object: unknown, property: string) -> Signal<()>,

	datatypes: {
		Vector2: ((x: number, y: number) -> Vector2)?,
		Vector3: ((x: number, y: number, z: number) -> Vector3)?,
		Color3: ((r: number, g: number, b: number) -> Color3)?,
		UDim: ((scale: number, offset: number) -> UDim)?,
		UDim2: ((xScale: number, xOffset: number, yScale: number, yOffset: number) -> UDim2)?,
		CFrame: ((position: Vector3, rotation: { number }) -> CFrame)?,
	},
	readCFrame: ((value: CFrame) -> (number, number, number, { number }))?,
}

type Library<F> = { new: F }

type Globals = {
	Instance: Library<(className: string) -> Instance>?,
	game: DataModel?,
	typeof: (value: unknown) -> string,
	Vector2: Library<(x: number, y: number) -> Vector2>?,
	Vector3: Library<(x: number, y: number, z: number) -> Vector3>?,
	Color3: Library<(r: number, g: number, b: number) -> Color3>?,
	UDim: Library<(scale: number, offset: number) -> UDim>?,
	UDim2: Library<(xScale: number, xOffset: number, yScale: number, yOffset: number) -> UDim2>?,
	CFrame: Library<(...number) -> CFrame>?,
	task: { cancel: unknown }?,
	os: typeof(os),
}

local function environment(): Globals
	return ((getfenv and getfenv(0) or {}) :: unknown) :: Globals
end

local function ambient(): Engine
	local globals = environment()
	local instances = globals.Instance
	local dataModel = globals.game

	if instances == nil or dataModel == nil then
		error(
			"ComposeRoblox: the Roblox engine is not present. This adapter only runs inside Roblox; "
				.. "pass an engine explicitly to ComposeRoblox.createHost(engine) to run it anywhere else.",
			0
		)
	end

	local runService = dataModel:GetService "RunService"
	local typeName = globals.typeof
	local vector2 = globals.Vector2
	local vector3 = globals.Vector3
	local color3 = globals.Color3
	local udim = globals.UDim
	local udim2 = globals.UDim2
	local cframe = globals.CFrame

	return {
		new = function(className: string): Instance
			return instances.new(className)
		end,
		heartbeat = runService.Heartbeat,
		clock = globals.os.clock,
		typeName = typeName,
		destroy = function(object: unknown)
			(object :: Destroyable):Destroy()
		end,
		propertyChanged = function(object: unknown, property: string): Signal<()>
			return (object :: PropertyObservable):GetPropertyChangedSignal(property)
		end,
		datatypes = {
			Vector2 = if vector2 ~= nil then vector2.new else nil,
			Vector3 = if vector3 ~= nil then vector3.new else nil,
			Color3 = if color3 ~= nil then color3.new else nil,
			UDim = if udim ~= nil then udim.new else nil,
			UDim2 = if udim2 ~= nil then udim2.new else nil,
			CFrame = if cframe ~= nil
				then function(position: Vector3, rotation: { number }): CFrame
					local coordinates = (position :: unknown) :: { x: number, y: number, z: number }
					return cframe.new(coordinates.x, coordinates.y, coordinates.z, table.unpack(rotation))
				end
				else nil,
		},
		readCFrame = if cframe ~= nil
			then function(value: CFrame): (number, number, number, { number })
				local components = { value:GetComponents() }
				return components[1],
					components[2],
					components[3],
					{
						components[4],
						components[5],
						components[6],
						components[7],
						components[8],
						components[9],
						components[10],
						components[11],
						components[12],
					}
			end
			else nil,
	}
end

local function cancelThread(thread: thread): boolean
	local scheduler = environment().task
	if scheduler == nil or type(scheduler.cancel) ~= "function" then
		return false
	end
	return (pcall(scheduler.cancel :: (thread: thread) -> (), thread))
end

return {
	ambient = ambient,
	cancelThread = cancelThread,
}
