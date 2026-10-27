--!strict
local Shared = require("./types")

return function(ctx: Shared.Context): ((Instance) -> ()) -> ()
	local Compose = ctx.Compose
	local building: string? = nil
	local track: ((Instance) -> ())? = nil
	local metatableOf = (getmetatable :: unknown) :: (unknown) -> unknown
	local native: { [unknown]: boolean } = {}
	native[metatableOf(Compose.cell(nil))] = true
	native[metatableOf(Compose.sharedCell(nil))] = true
	local probe = Compose.formula(function()
		return nil
	end)
	native[metatableOf(probe)] = true
	probe:dispose()
	local function reject(key: string?)
		local option = if key then ` option '{key}'` else " a value"
		error(
			`Facet UI.{building or "control"}:{option} is a readable from another Compose instance. `
				.. "Facet cannot track it. Bind Facet to that Compose with Facet.bind(Compose, Roblox).",
			0
		)
	end
	local function distance(a: string, b: string): number
		local previous: { number } = {}
		for j = 0, #b do
			previous[j] = j
		end
		for i = 1, #a do
			local current: { number } = { [0] = i }
			for j = 1, #b do
				local cost = if string.byte(a, i) == string.byte(b, j) then 0 else 1
				current[j] = math.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
			end
			previous = current
		end
		return previous[#b]
	end
	local function unknownOption(key: string, known: { [string]: boolean }): string
		if key == "width" or key == "height" then
			return `Facet UI.{building or "control"}: unknown option '{key}'. `
				.. "Use native Size and AutomaticSize on this control, or size its layout container. "
				.. "Read Layout-options for leaf sizing."
		end
		local best: string? = nil
		local bestDistance = 3
		for name in known do
			if name ~= "ref" then
				local d = distance(key, name)
				if d < bestDistance or (d == bestDistance and best ~= nil and name < best) then
					best, bestDistance = name, d
				end
			end
		end
		local suggestion = if best then ` Did you mean '{best}'?` else ""
		return `Facet UI.{building or "control"}: unknown option '{key}'.{suggestion}`
	end
	local consumedSets = (
		setmetatable({} :: { [unknown]: { [string]: boolean } }, { __mode = "k" }) :: unknown
	) :: { [unknown]: { [string]: boolean } }
	local function consumedFor(behavioralKeys: { string } | { [string]: boolean }?): { [string]: boolean }
		local frozen = behavioralKeys ~= nil and table.isfrozen(behavioralKeys)
		local cached = if frozen then consumedSets[behavioralKeys] else nil
		if cached then
			return cached
		end
		local consumed: { [string]: boolean } = { ref = true }
		for key, value in ((behavioralKeys or {}) :: unknown) :: { [unknown]: unknown } do
			if type(key) == "number" then
				assert(type(value) == "string")
				consumed[value] = true
			elseif type(key) == "string" then
				consumed[key] = true
			end
		end
		if frozen then
			consumedSets[behavioralKeys] = consumed
		end
		return consumed
	end
	function ctx.props<P>(spec: P, behavioralKeys: { string } | { [string]: boolean }?, defaults: unknown?): P
		local result: { [unknown]: unknown } = if type(defaults) == "table"
			then table.clone(defaults :: { [unknown]: unknown })
			else {}
		local consumed = consumedFor(behavioralKeys)
		for key, value in (spec :: unknown) :: { [unknown]: unknown } do
			if type(key) == "number" then
				result[#result + 1] = value
			elseif type(key) ~= "string" or not consumed[key] then
				if type(key) == "string" and string.match(key, "^[a-z]") then
					error(unknownOption(key, consumed), 0)
				end
				result[key] = value
			end
		end
		return (result :: unknown) :: P
	end
	function ctx.construct<F>(control: string, build: F): F & ((string) -> F)
		assert(type(build) == "function", "Facet constructor requires a builder")
		local apply = (build :: unknown) :: ({ [unknown]: unknown }) -> unknown
		local function construct(fields: { [unknown]: unknown }, name: string?): unknown
			if type(fields) ~= "table" then
				error(`Facet UI.{control}: expected a property table, got {typeof(fields)}`, 0)
			end
			if name then
				fields = table.clone(fields)
				assert(fields.Name == nil, "Facet: supply either a constructor name or Name")
				fields.Name = name
			end
			local outer = building
			building = control
			if Compose.currentOwner() == nil then
				building = outer
				error(
					`Facet UI.{control}: no owner from Facet's Compose is active. Build controls inside app.mount or runtime.mount. `
						.. "If the runtime comes from another Compose instance, "
						.. "bind Facet to that instance with Facet.bind(Compose, Roblox).",
					0
				)
			end
			for key, value in fields do
				if type(key) == "string" then
					if Compose.isValue(value) then
						if not native[metatableOf(value)] then
							reject(key)
						end
					elseif type(value) == "table" and metatableOf(value) == nil then
						for _, entry in value :: { [unknown]: unknown } do
							if type(entry) == "table" and not Compose.isValue(entry) then
								for field, inner in entry :: { [unknown]: unknown } do
									if Compose.isValue(inner) and not native[metatableOf(inner)] then
										reject(`{key}.{tostring(field)}`)
									end
								end
							elseif Compose.isValue(entry) and not native[metatableOf(entry)] then
								reject(key)
							end
						end
					end
				end
			end
			local node = apply(fields)
			building = outer
			if track and (type(node) == "userdata" or type(node) == "table") then
				track(node :: Instance)
			end
			if fields.ref then
				assert(type(fields.ref) == "function")
				local ref = fields.ref :: (unknown) -> ()
				ref(node)
			end
			return node
		end
		local function overloaded(first: { [unknown]: unknown } | string?): unknown
			if type(first) == "string" then
				return function(fields: { [unknown]: unknown }): unknown
					return construct(fields, first)
				end
			end
			return construct(first or {}, nil)
		end
		return (overloaded :: unknown) :: F & ((string) -> F)
	end
	local function styled<N>(node: N & Instance, role: string): N & Instance
		node:AddTag("facet-" .. string.lower(role))
		return node
	end
	ctx.styled = (styled :: unknown) :: typeof(ctx.styled)
	return function(tracker: (Instance) -> ())
		track = tracker
	end
end
