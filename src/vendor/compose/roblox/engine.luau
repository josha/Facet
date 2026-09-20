--!strict
--!nolint DeprecatedApi

export type Connection = {
	Disconnect: (self: Connection) -> (),
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

local function ambient(): Engine
	local globals = (getfenv and getfenv(0) or {}) :: { [string]: any }
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
	local typeName = globals.typeof :: (any) -> string

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
			Vector2 = if globals.Vector2 ~= nil then globals.Vector2.new else nil,
			Vector3 = if globals.Vector3 ~= nil then globals.Vector3.new else nil,
			Color3 = if globals.Color3 ~= nil then globals.Color3.new else nil,
			UDim = if globals.UDim ~= nil then globals.UDim.new else nil,
			UDim2 = if globals.UDim2 ~= nil then globals.UDim2.new else nil,
			CFrame = if globals.CFrame ~= nil
				then function(position: any, rotation: { number }): any
					return globals.CFrame.new(position.x, position.y, position.z, table.unpack(rotation))
				end
				else nil,
		},
		readCFrame = if globals.CFrame ~= nil
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
	local globals = (getfenv and getfenv(0) or {}) :: { [string]: any }
	local scheduler = globals.task
	if scheduler == nil or type(scheduler.cancel) ~= "function" then
		return false
	end
	return (pcall(scheduler.cancel, thread))
end

return {
	ambient = ambient,
	cancelThread = cancelThread,
}
