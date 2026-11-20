--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local Layout = require("./layout_types")
local parts = require("./overlay_parts")
local decoration = require("./native_decoration")

local EDGES: { [Layout.StackTailSide]: string } = { bottom = "top", top = "bottom", left = "right", right = "left" }

local function side(value: Layout.StackTail?): (Layout.StackTailSide?, number)
	if value == nil then
		return nil, 0.5
	end
	if type(value) == "string" then
		return value, 0.5
	end
	return value.side, value.at or 0.5
end

local function validate(value: unknown)
	if value == nil then
		return
	end
	local named = if type(value) == "table" then (value :: { side: unknown }).side else value
	assert(
		type(named) == "string" and EDGES[named :: Layout.StackTailSide] ~= nil,
		"Facet stack: tail must be top, bottom, left or right, or a table with side and at"
	)
	if type(value) == "table" then
		local at = (value :: { at: unknown }).at
		assert(
			at == nil or (type(at) == "number" and at >= 0 and at <= 1),
			"Facet stack: tail.at must be a number from 0 to 1"
		)
	end
end

return function(
	ctx: Types.Context,
	frame: Frame,
	tail: Types.Input<Layout.StackTail?>,
	radius: (ComposeTypes.Use, Vector2) -> number
)
	local Compose, Host, runtime, read = ctx.Compose, ctx.Host, ctx.runtime, ctx.read
	local D2, V2 = ctx.types.UDim2, ctx.types.Vector2
	if not Compose.isValue(tail) and type(tail) ~= "function" then
		validate(tail)
	end
	local size = ctx.layoutSize(frame, ctx.layoutUnit(frame, "TailUnit"))
	local warned: unknown = nil
	local placement = Compose.formula(function(use: ComposeTypes.Use): { side: Layout.StackTailSide?, at: number }
		local value = read<<Layout.StackTail?>>(tail, use)
		local valid, problem = pcall(validate, value)
		if not valid then
			if warned ~= value then
				warned = value
				warn(problem)
			end
			return { side = nil, at = 0.5 }
		end
		local named, at = side(value)
		return { side = named, at = at }
	end)
	local function current(use: ComposeTypes.Use): (Layout.StackTailSide?, number)
		local chosen = use(placement)
		return chosen.side, chosen.at
	end
	local layer = Host.Frame "TailLayer" {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 0,
		Size = D2.fromScale(1, 1),
		table.unpack(parts.tail(ctx, "Tail", function(use: ComposeTypes.Use): (Vector2?, string)
			local named, at = current(use)
			if named == nil then
				return nil, "top"
			end
			local box = use(size)
			local point = if named == "bottom"
				then V2.new(box.X * at, box.Y)
				elseif named == "top" then V2.new(box.X * at, 0)
				elseif named == "left" then V2.new(0, box.Y * at)
				else V2.new(box.X, box.Y * at)
			return point, EDGES[named]
		end, function(): number
			return 1
		end, function(): number
			return 1
		end, {
			node = frame,
			scale = function(): number
				return 1
			end,
			corner = function(): Vector2
				return V2.zero
			end,
			size = size,
			radius = function(use: ComposeTypes.Use): number
				return radius(use, use(size))
			end,
			role = "panel",
		})),
	}
	runtime.mount(function()
		return Host.Folder "TailBounds" { decoration(Compose, runtime, ctx.types, frame, layer) }
	end, frame)
end
