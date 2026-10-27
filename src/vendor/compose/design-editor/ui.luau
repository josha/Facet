--!strict

local Compose = require "../core"
local Environment = require "./environment"

export type Point = { X: number, Y: number }
export type Vector = { X: number, Y: number, Z: number }
export type Connection = { Disconnect: (self: Connection) -> () }

local MODIFIER_KEYS: { [string]: { string } } = {
	Shift = { "LeftShift", "RightShift" },
	Ctrl = { "LeftControl", "RightControl" },
	Meta = { "LeftMeta", "RightMeta", "LeftSuper", "RightSuper" },
	Alt = { "LeftAlt", "RightAlt" },
}

local function create(runtime: Compose.Runtime, environment: Environment.Environment, library: boolean?)
	local owner = Compose.createOwner(runtime.reactor)
	local owners: { [Compose.Node]: Compose.Owner } = {}
	local parents: { [Compose.Node]: Compose.Node } = {}
	local observation = assert(runtime.host.observation, "Design editor requires host observation")
	local render = runtime.host.render
	local disposed = false
	local function get(node: Compose.Node, key: string): unknown
		return observation.readProperty(node, key)
	end
	local function number(node: Compose.Node, key: string): number
		local value = get(node, key)
		return if type(value) == "number" then value else 0
	end
	local function text(node: Compose.Node, key: string): string
		local value = get(node, key)
		return if type(value) == "string" then value else ""
	end
	local function call(node: Compose.Node, method: string, ...: unknown): ...unknown
		return environment.invoke(node, method, ...)
	end
	local function destroy(node: Compose.Node)
		local owned = owners[node]
		if owned == nil then
			return
		end
		for child, parent in table.clone(parents) do
			if parent == node then
				destroy(child)
			end
		end
		parents[node] = nil
		owners[node] = nil
		Compose.owner.dispose(owned)
	end
	local function set(node: Compose.Node, key: string, value: unknown)
		if key == "Parent" then
			local previous = if library then get(node, "Parent") else parents[node]
			if previous == value then
				return
			end
			if previous ~= nil then
				render.removeChild(previous, node)
			end
			if not library then
				parents[node] = value
			end
			if value ~= nil then
				render.insertChild(value, node)
			end
		else
			render.setProperty(node, key, value)
		end
	end
	local function new(kind: string): Compose.Node
		if library then
			return runtime.constructors[kind] {}
		end
		local scope = Compose.owner.createChild(owner)
		local node = Compose.withOwner(scope, function(): Compose.Node
			return runtime.constructors[kind] {}
		end)
		owners[node] = scope
		return node
	end
	local function connect<A...>(node: Compose.Node, event: string, handler: (A...) -> ()): Connection
		local function subscribe(): () -> ()
			return runtime.connect(node, event, handler)
		end
		local stop = if library then subscribe() else Compose.withOwner(owner, subscribe)
		return {
			Disconnect = function(_self: Connection)
				stop()
			end,
		}
	end
	local values = environment.values
	local function point(value: unknown): Point
		return { X = number(value, "X"), Y = number(value, "Y") }
	end
	local function vector(value: unknown): Vector
		return { X = number(value, "X"), Y = number(value, "Y"), Z = number(value, "Z") }
	end
	local function isA(node: Compose.Node, kind: string): boolean
		return node ~= nil and call(node, "IsA", kind) == true
	end
	local function changed(node: Compose.Node, property: string, listener: () -> ()): Connection
		local stop = observation.observeProperty(node, property, listener)
		return {
			Disconnect = function(_self: Connection)
				stop()
			end,
		}
	end
	if library then
		Compose.owner.dispose(owner)
	end
	return {
		runtime = runtime,
		owner = owner,
		values = values,
		rgb = function(r: number, g: number, b: number): unknown
			return values.color(r / 255, g / 255, b / 255)
		end,
		hex = function(hex: string): unknown
			local r = tonumber(string.sub(hex, 2, 3), 16) or 0
			local g = tonumber(string.sub(hex, 4, 5), 16) or 0
			local b = tonumber(string.sub(hex, 6, 7), 16) or 0
			return values.color(r / 255, g / 255, b / 255)
		end,
		service = environment.service,
		modified = function(input: Compose.Node?, kinds: { string }): boolean
			for _, kind in kinds do
				if input ~= nil then
					if call(input, "IsModifierKeyDown", values.enum("ModifierKey", kind)) == true then
						return true
					end
				else
					local keys: { string } = MODIFIER_KEYS[kind] or {}
					for _, key in keys do
						if
							call(environment.service "UserInputService", "IsKeyDown", values.enum("KeyCode", key))
							== true
						then
							return true
						end
					end
				end
			end
			return false
		end,
		keyDown = function(keys: { string }): boolean
			for _, key in keys do
				if call(environment.service "UserInputService", "IsKeyDown", values.enum("KeyCode", key)) == true then
					return true
				end
			end
			return false
		end,
		descendants = environment.descendants,
		new = new,
		get = get,
		set = set,
		number = number,
		text = text,
		call = call,
		components = function(frame: unknown): { number }
			local found = { call(frame, "GetComponents") }
			local result: { number } = {}
			for _, value in found do
				assert(type(value) == "number", "CFrame component must be a number")
				table.insert(result, value)
			end
			return result
		end,
		isA = isA,
		destroy = destroy,
		connect = connect,
		changed = changed,
		point = point,
		vector = vector,
		xy = function(node: Compose.Node, property: string): Point
			return point(get(node, property))
		end,
		xyz = function(node: Compose.Node, property: string): Vector
			return vector(get(node, property))
		end,
		dispose = function()
			if disposed then
				return
			end
			disposed = true
			local failures: { string } = {}
			for node in table.clone(owners) do
				local ok, failure: unknown = pcall(destroy, node)
				if not ok then
					table.insert(failures, tostring(failure))
				end
			end
			local ok, failure: unknown = pcall(function()
				Compose.owner.dispose(owner)
			end)
			if not ok then
				table.insert(failures, tostring(failure))
			end
			if #failures > 0 then
				error(table.concat(failures, "\n"), 0)
			end
		end,
	}
end

export type UI = typeof(create(...))

return { create = create }
