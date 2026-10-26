--!strict

local library = require("./library")
local adapter = require("./adapter")
local document = require("./document")

export type Literal = string | number | boolean | { [string | number]: Literal }

export type FieldType = "string" | "number" | "boolean" | "choice" | "color" | "vector3" | "value" | "event" | "content"

export type Field = {
	type: FieldType,
	options: { string }?,
	tokens: boolean?,
	group: string?,
	order: number?,
	default: Literal?,
}

export type Resolved = {
	literal: Literal?,
	readable: unknown?,
	callback: ((...Literal) -> ())?,
	template: ((row: unknown) -> unknown)?,
	slot: (() -> unknown)?,
	rows: unknown?,
	key: string?,
}

export type Kind = {
	fields: { [string]: Field },
	defaults: { [string]: Literal }?,
	children: "none" | "list" | "template" | "slot",
	template: string?,
	slot: string?,
	category: string?,
	source: string?,
	key: string?,
	call: string,
	build: (props: { [string]: Resolved }, children: { unknown }) -> unknown,
}

export type Library = {
	name: string,
	parameter: string,
	parameterType: string,
	prelude: { string },
	returnType: string,
	readable: string,
	cell: string,
	token: string?,
	space: ("2d" | "3d")?,
	kinds: { [string]: Kind },
}

export type Context = {
	Facet: unknown,
	Compose: unknown,
	runtime: unknown,
	Host: unknown,
	UI: unknown,
	types: unknown?,
}

local SPACING = { "xs", "s", "m", "l", "xl" }

local FIELD_TYPES: { [string]: FieldType } = {
	string = "string",
	number = "number",
	boolean = "boolean",
	choice = "choice",
	color = "color",
	spacing = "choice",
	padding = "choice",
}

local TEMPLATE_KINDS: { [string]: true } = {
	VirtualList = true,
	VirtualGrid = true,
	Outline = true,
}

local CONTENT_KINDS: { [string]: true } = {
	ErrorBoundary = true,
	TabView = true,
	PageView = true,
	NavigationStack = true,
	NavigationSplitView = true,
	Table = true,
	VirtualList = true,
	VirtualGrid = true,
	Outline = true,
}

local function fieldsOf(definition: { [string]: unknown }): { [string]: Field }
	local fields: { [string]: Field } = {}
	local descriptors = definition.fields
	if type(descriptors) ~= "table" then
		return fields
	end
	for order, descriptor in descriptors :: { { [string]: unknown } } do
		local key, kind, options = descriptor.key, descriptor.kind, descriptor.options
		if type(key) ~= "string" or type(kind) ~= "string" then
			continue
		end
		local fieldType = FIELD_TYPES[kind] or "value"
		local field: Field = { type = fieldType, order = order }
		if fieldType == "choice" then
			if kind == "spacing" or kind == "padding" then
				field.options = SPACING
			elseif type(options) == "table" then
				local choices: { string } = {}
				for _, option in options :: { unknown } do
					if type(option) == "string" then
						table.insert(choices, option)
					end
				end
				field.options = choices
			end
		end
		fields[key] = field
	end
	return fields
end

local function literalOf(value: unknown): Literal?
	local kind = type(value)
	if kind == "string" or kind == "number" or kind == "boolean" then
		return value :: Literal
	elseif kind == "table" then
		local copy: { [string | number]: Literal } = {}
		for key, item in value :: { [unknown]: unknown } do
			local converted = literalOf(item)
			if converted ~= nil and (type(key) == "string" or type(key) == "number") then
				copy[key :: string | number] = converted
			end
		end
		return copy
	end
	return nil
end

local function defaultsOf(definition: { [string]: unknown }): { [string]: Literal }
	local defaults: { [string]: Literal } = {}
	local source = definition.defaults
	if type(source) == "table" then
		for key, value in source :: { [unknown]: unknown } do
			local converted = literalOf(value)
			if type(key) == "string" and converted ~= nil then
				defaults[key] = converted
			end
		end
	end
	return defaults
end

local function create(ctx: Context): Library
	local UI = ctx.UI :: { [string]: (name: string) -> ({ [unknown]: unknown }) -> unknown }
	local counter = 0
	local kinds: { [string]: Kind } = {}
	for _, name in library.names() do
		local definition = library.definitions[name] :: { [string]: unknown }
		local isContainer = definition.container == true
		local content = if type(definition.content) == "string" then definition.content :: string else nil
		kinds[name] = {
			fields = fieldsOf(definition),
			defaults = defaultsOf(definition),
			children = if TEMPLATE_KINDS[name] then "template" elseif content then "slot" elseif isContainer then "list" else "none",
			slot = content,
			category = if type(definition.category) == "string" then definition.category :: string else nil,
			source = if TEMPLATE_KINDS[name] then "from" else nil,
			template = if TEMPLATE_KINDS[name] then "render" else nil,
			key = if TEMPLATE_KINDS[name] then "key" else nil,
			call = "UI." .. name,
			build = function(props: { [string]: Resolved }, children: { unknown }): unknown
				counter += 1
				local literals: { [string]: unknown } = {}
				local live: { [string]: unknown } = {}
				for key, resolved in props do
					if resolved.literal ~= nil then
						literals[key] = resolved.literal
					elseif resolved.readable ~= nil then
						live[key] = resolved.readable
					elseif resolved.callback ~= nil then
						live[key] = resolved.callback
					elseif resolved.slot ~= nil then
						live[key] = resolved.slot
					end
				end
				local placeholders: { document.Node } = {}
				for index, child in children do
					table.insert(placeholders, {
						id = `{counter}_{index}`,
						kind = "Text",
						name = `Child{index}`,
						props = {},
						children = {},
						built = child,
					} :: any)
				end
				local node: document.Node = {
					id = tostring(counter),
					kind = name,
					name = name,
					props = literals,
					children = placeholders,
				} :: any
				local evaluation = {
					Facet = ctx.Facet,
					Compose = ctx.Compose,
					runtime = ctx.runtime,
					Host = ctx.Host,
					UI = ctx.UI,
					types = ctx.types,
					render = function(child: { built: unknown })
						return child.built
					end,
				}
				local resolved = adapter.evaluate(adapter.properties(node), evaluation, {}) :: { [unknown]: unknown }
				for key, value in live do
					resolved[key] = value
				end
				local rows = props.from
				if TEMPLATE_KINDS[name] and rows and rows.rows ~= nil then
					resolved.from = rows.rows
					if rows.key ~= nil then
						resolved.key = rows.key
					end
				end
				local row = props.render
				if TEMPLATE_KINDS[name] and row and row.template ~= nil then
					local template = row.template
					resolved.render = function(current: unknown)
						return template(current)
					end
				end
				local slot = if content then props[content] else nil
				if slot and slot.slot then
					local builder = slot.slot
					resolved[content] = function()
						return builder()
					end
				end
				if not definition.content and not CONTENT_KINDS[name] then
					for _, child in children do
						table.insert(resolved :: { unknown }, child)
					end
				end
				return UI[name](name)(resolved)
			end,
		}
	end
	return {
		name = "Facet",
		parameter = "UI",
		parameterType = "Facet.Controls",
		prelude = { "local Facet = require(game:GetService(\"ReplicatedStorage\").Facet)" },
		returnType = "GuiObject",
		readable = "Facet.Compose.ReadOnlyValue",
		cell = "Facet.Compose.Value",
		space = "2d",
		kinds = kinds,
	}
end

return { create = create }
