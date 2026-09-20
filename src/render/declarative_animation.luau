--!strict
-- Per-property motion contributes values to the existing presentation channel.
-- It never writes an adapter, dirties layout, or owns a second frame driver.
local policy = require("../motion/policy")
local observeChange = require("../core/on_change")
local declarative = {}
local fields: { [string]: number } = { opacity = 1, scale = 1, rotation = 0, offsetX = 0, offsetY = 0 }
local function keyOf(field: string): string
	return if field == "offsetX" or field == "offsetY" then "offset" else field
end
function declarative.new(core: any, clock: any, repaint: (string) -> ())
	local specs: { [string]: any } = {}
	local motions: { [string]: { [string]: any } } = {}
	local count = 0
	local api = {}
	function api.register(node: any)
		if node.props.animation and not specs[node.path] then
			assert(clock, "Facet animation requires a presenter or renderer clock")
			specs[node.path] = node.props.animation
			count += 1
		end
	end
	function api.spec(path: string): any
		return specs[path]
	end
	function api.count(): number
		return count
	end
	local function clear(path: string, field: string)
		local row = motions[path]
		local entry = row and row[field]
		if entry then
			row[field] = nil
			entry.stop()
			entry.value:dispose()
			if next(row) == nil then
				motions[path] = nil
			end
		end
	end
	function api.react(path: string, before: any, after: any, suppressed: boolean)
		local spec = specs[path]
		if not spec then
			return
		end
		for field, identity in fields do
			local preset = spec[keyOf(field)]
			if type(preset) == "string" then
				local target = if after and after[field] ~= nil then after[field] else identity
				local initial = if before and before[field] ~= nil then before[field] else identity
				if suppressed or clock:isReduced() then
					clear(path, field)
				elseif target ~= initial then
					local row = motions[path]
					local entry = row and row[field]
					if not entry then
						row = row or {}
						motions[path] = row
						local value = policy.value(clock, initial, preset)
						entry = {
							value = value,
							stop = observeChange(core.owner, value, function()
								repaint(path)
							end),
						}
						row[field] = entry
						value:onSettle(function()
							clear(path, field)
						end)
					end
					entry.value:setTarget(target)
				end
			end
		end
	end
	function api.effective(path: string, o: number?, s: number?, r: number?, x: number?, y: number?)
		local row = motions[path]
		if not row then
			return o, s, r, x, y
		end
		return if row.opacity then row.opacity.value:peek() else o,
			if row.scale then row.scale.value:peek() else s,
			if row.rotation then row.rotation.value:peek() else r,
			if row.offsetX then row.offsetX.value:peek() else x,
			if row.offsetY then row.offsetY.value:peek() else y
	end
	function api.forget(path: string)
		for field in fields do
			clear(path, field)
		end
		if specs[path] then
			specs[path] = nil
			count -= 1
		end
	end
	function api.settle()
		local pending = table.clone(motions)
		for path in pending do
			for field in fields do
				clear(path, field)
			end
			repaint(path)
		end
	end
	return api
end
return declarative
