--!strict
local Types = require("./types")
local Inputs = require("./input_types")
local placement = require("./overlay_placement")
local freeze = require("./freeze")

export type Plate = { name: string?, gate: Types.Value<boolean>?, shown: Types.Cell<boolean>? }
type Show = (GuiObject, Inputs.Help, Plate?) -> ()

local registry = setmetatable({} :: { [Types.Context]: Show }, { __mode = "k" })
local pressed = setmetatable({} :: { [Instance]: boolean }, { __mode = "k" })

local help = {}

local KEYS: { [string]: boolean } = freeze({ title = true, body = true, shortcut = true, edge = true, align = true })

function help.check(ctx: Types.Context, value: unknown)
	if type(value) ~= "table" or ctx.Compose.isReadable(value) then
		return
	end
	local fields = value :: { [string]: unknown }
	for key in fields do
		if type(key) ~= "string" or not KEYS[key] then
			error(`Facet UI.Button: unknown help option '{tostring(key)}'`, 0)
		end
	end
	local function text(field: unknown): boolean
		return type(field) == "string" or type(field) == "function" or ctx.Compose.isReadable(field)
	end
	if not text(fields.body) then
		error("Facet UI.Button: help.body must be a string or a bound string", 0)
	end
	if fields.title ~= nil and not text(fields.title) then
		error("Facet UI.Button: help.title must be a string or a bound string", 0)
	end
	if fields.body == "" and (type(fields.title) ~= "string" or fields.title == "") then
		error("Facet UI.Button: help.body may be empty only when help.title carries the words", 0)
	end
	if fields.shortcut ~= nil then
		local chords = fields.shortcut
		local valid = type(chords) == "table" and #(chords :: { unknown }) > 0
		if valid then
			for _, chord in chords :: { unknown } do
				if type(chord) ~= "table" or #(chord :: { unknown }) == 0 then
					valid = false
					break
				end
				for _, key in chord :: { unknown } do
					if type(key) ~= "string" or key == "" then
						valid = false
					end
				end
			end
		end
		if not valid then
			error('Facet UI.Button: help.shortcut must be a list of key chords such as { { "Ctrl", "K" } }', 0)
		end
	end
	placement.assertEdge(fields.edge, "UI.Button help")
	placement.assertAlign(fields.align, "UI.Button help")
end

function help.register(ctx: Types.Context, show: Show)
	registry[ctx] = show
end

function help.attach(ctx: Types.Context, anchor: GuiObject, value: Inputs.Help, plate: Plate?)
	help.check(ctx, value)
	local show = registry[ctx]
	if show then
		show(anchor, value, plate)
	end
end

function help.hold(node: Instance, held: boolean)
	if held then
		pressed[node] = true
	else
		pressed[node] = nil
	end
end

function help.consume(node: Instance): boolean
	local held = pressed[node] == true
	pressed[node] = nil
	return held
end

return help
