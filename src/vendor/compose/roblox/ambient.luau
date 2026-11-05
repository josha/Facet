--!strict

local Dynamic = require "../core/dynamic"
local EngineTypes = require "./types"
type Connection = EngineTypes.Connection
type Destroyable = EngineTypes.Destroyable
type Vector2 = EngineTypes.Vector2
type Vector3 = EngineTypes.Vector3
type Color3 = EngineTypes.Color3
type UDim = EngineTypes.UDim
type UDim2 = EngineTypes.UDim2
type CFrame = EngineTypes.CFrame
type Instance = EngineTypes.Instance
type DataModel = EngineTypes.DataModel
type Datatypes = EngineTypes.Datatypes
type Engine = EngineTypes.Engine
type Codecs = EngineTypes.Codecs
type Source = EngineTypes.Source
type Signal<A... = ...unknown> = EngineTypes.Signal<A...>

type Library<F> = { new: F }

type Scheduler = { cancel: ((thread: thread) -> ())? }

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
	local dataModel: DataModel? = game
	return assert(dataModel, "Roblox is absent; inject the requested service"):GetService(name)
end

local function ambient(): Engine
	local instances: Library<(className: string) -> Instance>? = Instance
	local dataModel: DataModel? = game

	if instances == nil or dataModel == nil then
		error(
			"ComposeRoblox: the Roblox engine is not present. This adapter only runs inside Roblox; "
				.. "pass an engine explicitly to ComposeRoblox.createHost(engine) to run it anywhere else.",
			0
		)
	end

	local runService = dataModel:GetService "RunService"
	local client = invoke(readMember, runService, "IsClient")
	assert(type(client) == "boolean", "RunService.IsClient did not return a boolean")
	local typeName = typeof
	local vector2: Library<(x: number, y: number) -> Vector2>? = Vector2
	local vector3: Library<(x: number, y: number, z: number) -> Vector3>? = Vector3
	local color3: Library<(r: number, g: number, b: number) -> Color3>? = Color3
	local udim: Library<(scale: number, offset: number) -> UDim>? = UDim
	local udim2: Library<(xScale: number, xOffset: number, yScale: number, yOffset: number) -> UDim2>? = UDim2
	local cframe: Library<(...number) -> CFrame>? = CFrame

	return {
		new = function(className: string): Instance
			return instances.new(className)
		end,
		heartbeat = frameSignal(readMember(runService, if client then "PreRender" else "Heartbeat")),
		clock = os.clock,
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
	local model: DataModel? = game
	local dataModel = assert(model, "Roblox is absent; inject a design environment")
	local vector2: Library<(number, number) -> Vector2>? = Vector2
	local vector3: Library<(number, number, number) -> Vector3>? = Vector3
	local color3: Library<(number, number, number) -> Color3>? = Color3
	local udim: Library<(number, number) -> UDim>? = UDim
	local udim2: Library<(number, number, number, number) -> UDim2>? = UDim2
	local cframe: Library<(...number) -> CFrame>? = CFrame
	local font: Library<(string, unknown) -> unknown> = Font
	local enums: { [string]: { [string]: unknown } } = Enum
	local raycast: Library<() -> { FilterType: unknown, FilterDescendantsInstances: { unknown } }> = RaycastParams
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
				return font.new(family, enums.FontWeight[weight])
			end,
			enum = function(name: string, item: string): unknown
				return enums[name][item]
			end,
			cframe = function(components: { number }): unknown
				return assert(cframe).new(table.unpack(components))
			end,
			raycastParams = function(include: boolean, nodes: { unknown }): unknown
				local params = raycast.new()
				params.FilterType = enums.RaycastFilterType[if include then "Include" else "Exclude"]
				params.FilterDescendantsInstances = nodes
				return params
			end,
		},
	}
end

local function cancelThread(thread: thread): boolean
	local scheduler: Scheduler? = task
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
