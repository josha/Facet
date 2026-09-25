--!strict
--!nolint DeprecatedApi

export type Connection = {
	Disconnect: (self: Connection) -> (),
}

export type Destroyable = {
	Destroy: (self: Destroyable) -> (),
}

export type Signal = {
	Connect: (self: Signal, handler: (...any) -> ()) -> Connection,
}

export type Engine = {
	new: (className: string) -> any,
	heartbeat: Signal,
	clock: () -> number,
	typeName: (value: any) -> string,
	destroy: (object: any) -> (),
	propertyChanged: (object: any, property: string) -> Signal,

	datatypes: {
		Vector2: ((x: number, y: number) -> any)?,
		Vector3: ((x: number, y: number, z: number) -> any)?,
		Color3: ((r: number, g: number, b: number) -> any)?,
		UDim: ((scale: number, offset: number) -> any)?,
		UDim2: ((xScale: number, xOffset: number, yScale: number, yOffset: number) -> any)?,
		CFrame: ((position: any, rotation: { number }) -> any)?,
	},
	readCFrame: ((value: any) -> (number, number, number, { number }))?,
}

type Library<F> = { new: F }

type Globals = {
	Instance: Library<(className: string) -> any>?,
	game: any,
	typeof: (value: any) -> string,
	Vector2: Library<(x: number, y: number) -> any>?,
	Vector3: Library<(x: number, y: number, z: number) -> any>?,
	Color3: Library<(r: number, g: number, b: number) -> any>?,
	UDim: Library<(scale: number, offset: number) -> any>?,
	UDim2: Library<(xScale: number, xOffset: number, yScale: number, yOffset: number) -> any>?,
	CFrame: Library<(...number) -> any>?,
	task: { cancel: unknown }?,
	os: typeof(os),
}

local function environment(): Globals
	return (getfenv and getfenv(0) or {}) :: any
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
		new = function(className: string): any
			return instances.new(className)
		end,
		heartbeat = runService.Heartbeat,
		clock = globals.os.clock,
		typeName = typeName,
		destroy = function(object: any)
			object:Destroy()
		end,
		propertyChanged = function(object: any, property: string): Signal
			return object:GetPropertyChangedSignal(property)
		end,
		datatypes = {
			Vector2 = if vector2 ~= nil then vector2.new else nil,
			Vector3 = if vector3 ~= nil then vector3.new else nil,
			Color3 = if color3 ~= nil then color3.new else nil,
			UDim = if udim ~= nil then udim.new else nil,
			UDim2 = if udim2 ~= nil then udim2.new else nil,
			CFrame = if cframe ~= nil
				then function(position: any, rotation: { number }): any
					return cframe.new(position.x, position.y, position.z, table.unpack(rotation))
				end
				else nil,
		},
		readCFrame = if cframe ~= nil
			then function(value: any): (number, number, number, { number })
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
