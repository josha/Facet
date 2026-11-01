--!strict
--!nolint DeprecatedApi
local Dynamic = require "../core/dynamic"

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

type Library<F> = { new: F }

type Globals = {
	Enum: { [string]: { [string]: unknown } },
	Font: Library<(family: string, weight: unknown) -> unknown>,
	RaycastParams: Library<() -> { FilterType: unknown, FilterDescendantsInstances: { unknown } }>,
	Instance: Library<(className: string) -> Instance>?,
	game: DataModel?,
	typeof: (value: unknown) -> string,
	Vector2: Library<(x: number, y: number) -> Vector2>?,
	Vector3: Library<(x: number, y: number, z: number) -> Vector3>?,
	Color3: Library<(r: number, g: number, b: number) -> Color3>?,
	UDim: Library<(scale: number, offset: number) -> UDim>?,
	UDim2: Library<(xScale: number, xOffset: number, yScale: number, yOffset: number) -> UDim2>?,
	CFrame: Library<(...number) -> CFrame>?,
	task: { cancel: ((thread: thread) -> ())? }?,
	os: typeof(os),
}

local function environment(): Globals?
	return if getfenv ~= nil then getfenv(0) else nil
end

local readMember = Dynamic.read
local writeMember = Dynamic.write

local function invoke(read: (unknown, string) -> unknown, object: unknown, method: string, ...: unknown): ...unknown
	return Dynamic.invoke(read(object, method), object, ...)
end

local function descendants(object: unknown): { unknown }
	local value = invoke(readMember, object, "GetDescendants")
	assert(type(value) == "table", "GetDescendants did not return an array")
	local result: { unknown } = {}
	for _, child in value do
		table.insert(result, child)
	end
	return result
end

local function propertyChanged(object: unknown, property: string): Signal<()>
	local signal = invoke(readMember, object, "GetPropertyChangedSignal", property)
	return {
		Connect = function(_self, handler: () -> ()): Connection
			local connection = invoke(readMember, signal, "Connect", handler)
			return {
				Disconnect = function(_connection)
					invoke(readMember, connection, "Disconnect")
				end,
			}
		end,
	}
end

local function frameSignal(signal: unknown): Signal<number>
	return {
		Connect = function(_self, handler: (number) -> ()): Connection
			local connection = invoke(readMember, signal, "Connect", function(delta: unknown)
				assert(type(delta) == "number", "frame signal did not supply a numeric delta")
				handler(delta)
			end)
			return {
				Disconnect = function(_connection)
					invoke(readMember, connection, "Disconnect")
				end,
			}
		end,
	}
end

local function service(name: string): unknown
	local globals = assert(environment(), "Roblox is absent; inject the requested service")
	return assert(globals.game, "Roblox is absent; inject the requested service"):GetService(name)
end

local function ambient(): Engine
	local globals = environment()
	local instances = if globals then globals.Instance else nil
	local dataModel = if globals then globals.game else nil

	if globals == nil or instances == nil or dataModel == nil then
		error(
			"ComposeRoblox: the Roblox engine is not present. This adapter only runs inside Roblox; "
				.. "pass an engine explicitly to ComposeRoblox.createHost(engine) to run it anywhere else.",
			0
		)
	end

	local runService = dataModel:GetService "RunService"
	local client = invoke(readMember, runService, "IsClient")
	assert(type(client) == "boolean", "RunService.IsClient did not return a boolean")
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
		heartbeat = frameSignal(readMember(runService, if client then "PreRender" else "Heartbeat")),
		clock = globals.os.clock,
		typeName = typeName,
		destroy = function(object: unknown)
			invoke(readMember, object, "Destroy")
		end,
		propertyChanged = propertyChanged,
		datatypes = {
			Vector2 = if vector2 ~= nil then vector2.new else nil,
			Vector3 = if vector3 ~= nil then vector3.new else nil,
			Color3 = if color3 ~= nil then color3.new else nil,
			UDim = if udim ~= nil then udim.new else nil,
			UDim2 = if udim2 ~= nil then udim2.new else nil,
			CFrame = if cframe ~= nil
				then function(position: Vector3, rotation: { number }): CFrame
					local coordinates = position
					return cframe.new(coordinates.X, coordinates.Y, coordinates.Z, table.unpack(rotation))
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

local function designEnvironment(read: (unknown, string) -> unknown)
	local globals = assert(environment(), "Roblox is absent; inject a design environment")
	local dataModel = assert(globals.game, "Roblox is absent; inject a design environment")
	local vector2, vector3, color3, udim, udim2, cframe =
		globals.Vector2, globals.Vector3, globals.Color3, globals.UDim, globals.UDim2, globals.CFrame
	return {
		read = read,
		descendants = descendants,
		invoke = function(object: unknown, method: string, ...: unknown): ...unknown
			return invoke(read, object, method, ...)
		end,
		service = function(name: string): unknown
			return dataModel:GetService(name)
		end,
		values = {
			vector2 = function(x: number, y: number): unknown
				return assert(vector2).new(x, y)
			end,
			vector3 = function(x: number, y: number, z: number): unknown
				return assert(vector3).new(x, y, z)
			end,
			udim = function(scale: number, offset: number): unknown
				return assert(udim).new(scale, offset)
			end,
			udim2 = function(xs: number, xo: number, ys: number, yo: number): unknown
				return assert(udim2).new(xs, xo, ys, yo)
			end,
			color = function(r: number, g: number, b: number): unknown
				return assert(color3).new(r, g, b)
			end,
			font = function(family: string, weight: string): unknown
				return globals.Font.new(family, globals.Enum.FontWeight[weight])
			end,
			enum = function(name: string, item: string): unknown
				return globals.Enum[name][item]
			end,
			cframe = function(components: { number }): unknown
				return assert(cframe).new(table.unpack(components))
			end,
			raycastParams = function(include: boolean, nodes: { unknown }): unknown
				local params = globals.RaycastParams.new()
				params.FilterType = globals.Enum.RaycastFilterType[if include then "Include" else "Exclude"]
				params.FilterDescendantsInstances = nodes
				return params
			end,
		},
	}
end

local function cancelThread(thread: thread): boolean
	local globals = environment()
	local scheduler = if globals then globals.task else nil
	if scheduler == nil or type(scheduler.cancel) ~= "function" then
		return false
	end
	return (pcall(scheduler.cancel, thread))
end

return {
	ambient = ambient,
	designEnvironment = designEnvironment,
	descendants = descendants,
	invoke = invoke,
	readMember = readMember,
	writeMember = writeMember,
	service = service,
	cancelThread = cancelThread,
}
