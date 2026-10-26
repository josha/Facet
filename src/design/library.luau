--!strict

local Compose = require("../vendor/compose/core")
local Design = require("../vendor/compose/design")
local Types = require("./types")
local controls = require("./controls")
local derived = require("./fields")
local icons = require("../ui/icons")

type Literal = Design.Literal
type Resolved = Design.Resolved
type Record = { [unknown]: unknown }
type Construct = (props: Record) -> unknown
type Named = (name: string) -> Construct

export type Context = Types.Context

local LEVEL_IMAGES: Record = {
	filled = "rbxassetid://108245103349446",
	empty = "rbxassetid://73716910467356",
}

local TEMPLATE_KINDS: { [string]: true } = { VirtualList = true, VirtualGrid = true, Outline = true }

local PAGED_KINDS: { [string]: string } = { TabView = "tabs", PageView = "pages" }

local OWN_CHILDREN: { [string]: true } = {
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

local SETTERS: { [string]: { key: string, property: string, constant: boolean? } } = {
	CellEditor = { key = "value", property = "onChange" },
	DateTimePicker = { key = "value", property = "onChange" },
	Pagination = { key = "page", property = "onChange" },
	Vote = { key = "value", property = "onChange" },
	StepIndicator = { key = "current", property = "onSelect" },
	Dialog = { key = "isPresented", property = "onPresentedChange" },
	Popover = { key = "isPresented", property = "onPresentedChange" },
	Toast = { key = "isPresented", property = "onPresentedChange" },
	Callout = { key = "isPresented", property = "onRetire", constant = false },
}

local ACTIONS: { [string]: { { list: string, handler: string } } } = {
	Menu = { { list = "items", handler = "onSelect" } },
	SplitButton = { { list = "items", handler = "onSelect" } },
	RadialMenu = { { list = "items", handler = "onSelect" } },
	Dialog = { { list = "actions", handler = "onActivate" } },
	Notice = { { list = "actions", handler = "onActivate" } },
	Sheet = { { list = "actions", handler = "onActivate" } },
	Callout = { { list = "actions", handler = "onActivate" } },
	Alert = { { list = "actions", handler = "onActivate" } },
	RowActions = { { list = "leading", handler = "onActivate" }, { list = "trailing", handler = "onActivate" } },
}

local function noop() end

local function copy(value: unknown): unknown
	if type(value) ~= "table" then
		return value
	end
	local result: Record = {}
	for key, item in value :: Record do
		result[key] = copy(item)
	end
	return result
end

local function record(value: unknown): Record?
	return if type(value) == "table" then value :: Record else nil
end

local function stateKeys(spec: Types.ControlSpec): { string }
	local states = spec.states
	if states ~= nil then
		return states
	end
	local state = spec.state
	return if state ~= nil then { state } else {}
end

local OPTION_LISTS: { [string]: true } = { Picker = true, ComboBox = true }

local LITERAL_KINDS: { [string]: string } = {
	string = "string",
	choice = "string",
	color = "string",
	number = "number",
	boolean = "boolean",
}

local function derivedFields(name: string): { [string]: Types.DerivedField }
	local found = derived.controls[name]
	return if found ~= nil then found.fields else {}
end

local ICONS: { string } = {}
for _, set in { icons.BUILTIN, icons.ART } do
	for iconName in set do
		table.insert(ICONS, iconName)
	end
end
table.sort(ICONS)

local function picked(key: string, kind: Design.FieldType, options: { string }?): (Design.FieldType, { string }?)
	if kind == "string" and string.match(key, "[iI]con$") then
		return "choice", ICONS
	end
	return kind, options
end

local REQUIRES: { [string]: { [string]: { Literal } } } = {
	corners = { surface = {} },
	sliceCenter = { scaleMode = { "slice" } },
	sliceScale = { scaleMode = { "slice" }, sliceCenter = {} },
	visibleLines = { multiline = { true } },
	hug = { mode = { "all" } },
	indicatorPosition = { style = { "radioGroup" } },
	needle = { presentation = { "gauge" } },
	sweep = { presentation = { "gauge" } },
	segments = { presentation = { "bar" } },
	leading = { zone = { "topbar" } },
	trailing = { zone = { "topbar" } },
	edge = { placement = { "side", "adaptive" } },
	alpha = { onAlphaChange = {} },
}

local KIND_REQUIRES: { [string]: { [string]: { [string]: { Literal } } } } = {
	Picker = { maxHeight = { style = { "automatic", "menu", "navigationLink" } } },
	ProgressView = { diameter = { presentation = { "circular", "gauge", "spinner" } } },
	Toggle = { mixed = { presentation = { "checkbox" } } },
}

local FIELD_DEFAULTS: { [string]: { [string]: Literal } } = {
	NavigationSplitView = { maxSidebarWidth = 480 },
	ProgressView = { min = 0, sweep = 240 },
	Image = { sliceCenter = { x0 = 0, y0 = 0, x1 = 1, y1 = 1 } },
}

local function refine(name: string, fields: { [string]: Design.Field }): { [string]: Design.Field }
	local own = KIND_REQUIRES[name] or {}
	local defaults = FIELD_DEFAULTS[name] or {}
	for key, field in fields do
		local requires = own[key] or REQUIRES[key]
		if requires ~= nil then
			local known = true
			for other in requires do
				known = known and fields[other] ~= nil
			end
			if known then
				field.requires = requires
			end
		end
		if defaults[key] ~= nil then
			field.default = defaults[key]
		end
	end
	return fields
end

local function plainFields(source: { [string]: Types.DerivedField }): { [string]: Design.Field }
	local fields: { [string]: Design.Field } = {}
	local keys: { string } = {}
	for key in source do
		table.insert(keys, key)
	end
	table.sort(keys)
	for order, key in keys do
		local field = source[key]
		local lower = string.match(key, "^%l") ~= nil
		local kind, options = picked(key, field.type, field.options)
		fields[key] = {
			type = kind,
			options = options,
			datatype = if field.type == "color" then "Color3" else field.datatype,
			also = field.also,
			group = if lower then "Control" else "Roblox",
			order = order,
		}
	end
	return fields
end

local function fieldsOf(name: string, spec: Types.ControlSpec): { [string]: Design.Field }
	local fields: { [string]: Design.Field } = {}
	local order = 1000
	for key, field in derivedFields(name) do
		if
			spec.fields[string.lower(string.sub(key, 1, 1)) .. string.sub(key, 2)] ~= nil and string.match(key, "^%u")
		then
			continue
		end
		order += 1
		local kind, options = picked(key, field.type, field.options)
		fields[key] = {
			type = kind,
			options = options,
			datatype = if field.type == "color" then "Color3" else field.datatype,
			also = field.also,
			group = "More",
			order = order,
			advanced = true,
		}
	end
	local typed = derivedFields(name)
	for key, field in spec.fields do
		local also: { string } = {}
		if field.format == "spacing" then
			table.insert(also, "number")
		elseif field.format == "padding" then
			table.insert(also, "number")
			table.insert(also, "table")
		end
		local runtime = typed[key]
		local kind = if runtime ~= nil then LITERAL_KINDS[runtime.type] else nil
		local own = LITERAL_KINDS[field.type]
		if kind ~= nil and kind ~= own and table.find(also, kind) == nil then
			table.insert(also, kind)
		end
		local kind, options = picked(key, field.type, field.options)
		fields[key] = {
			type = kind,
			options = options,
			order = field.order,
			label = field.label,
			default = field.default,
			datatype = if field.type == "color" then "Color3" else nil,
			also = if #also > 0 then also else nil,
			luauType = if field.format == "padding"
				then "Facet.Sides"
				elseif key == "options" and OPTION_LISTS[name] then "{ Facet.PickerOption<string> }"
				else nil,
		}
	end
	return fields
end

local function seedChildren(spec: Types.ControlSpec): boolean
	return spec.container == true or spec.content ~= nil
end

local function seeds(name: string): { Types.Seed }
	local spec = controls[name]
	if spec == nil then
		return {}
	end
	local declared = spec.seeds
	if declared ~= nil then
		return declared
	end
	if not seedChildren(spec) then
		return {}
	end
	local props: { [string]: Types.Literal } = { text = "Make this content yours" }
	local placeholder: Types.Seed = { kind = "Text", props = props }
	return { placeholder }
end

local function create(context: Context): Design.Library
	local UI = context.UI :: { [string]: Named }
	local rgb, udim2, offset = context.rgb, context.udim2, context.offset

	local function color(value: unknown): unknown
		if type(value) == "string" and string.match(value, "^#%x%x%x%x%x%x$") then
			return rgb(
				tonumber(string.sub(value, 2, 3), 16) or 0,
				tonumber(string.sub(value, 4, 5), 16) or 0,
				tonumber(string.sub(value, 6, 7), 16) or 0
			)
		end
		return value
	end

	local function convert(datatype: string, literal: Literal): unknown
		if datatype == "Color3" then
			return color(literal)
		end
		local enumName = string.match(datatype, "^Enum%.(.+)$")
		if enumName ~= nil then
			local lookup = context.enumItem
			return if lookup ~= nil and type(literal) == "string" then lookup(enumName, literal) else literal
		end
		local construct = context.datatype
		if construct == nil or type(literal) ~= "table" then
			return literal
		end
		local components: { number } = {}
		for _, component in literal do
			if type(component) == "number" then
				table.insert(components, component)
			end
		end
		return construct(datatype, components)
	end

	local function stack(children: { unknown }): unknown
		local props: Record = { gap = "s", width = "fill" }
		for _, child in children do
			table.insert(props :: { unknown }, child)
		end
		return UI.VStack("Content")(props)
	end

	local function content(children: { unknown }): () -> unknown
		return function(): unknown
			return if #children == 1 then children[1] else stack(children)
		end
	end

	local function actions(items: unknown, handler: string)
		local list = record(items)
		if list == nil then
			return
		end
		for _, item in list do
			local entry = record(item)
			if entry ~= nil then
				if entry.children ~= nil then
					actions(entry.children, handler)
				elseif not entry.divider and entry[handler] == nil then
					entry[handler] = noop
				end
			end
		end
	end

	local kinds: { [string]: Design.Kind } = {}
	for name, spec in controls do
		local contentKey = spec.content
		local templated = TEMPLATE_KINDS[name] == true
		local kindFields = refine(name, fieldsOf(name, spec))
		kinds[name] = {
			fields = kindFields,
			defaults = spec.defaults,
			seeds = if spec.seeds ~= nil or contentKey ~= nil then seeds(name) else nil,
			children = if templated
				then "template"
				elseif contentKey ~= nil then "slot"
				elseif spec.container then "list"
				else "none",
			slot = contentKey,
			category = spec.category,
			source = if templated then "from" else nil,
			template = if templated then "render" else nil,
			key = if templated then "key" else nil,
			call = "UI." .. name,
			build = function(props: { [string]: Resolved }, children: { unknown }, nodeName: string): unknown
				local values: Record = {}
				for key, value in spec.defaults do
					values[key] = copy(value)
				end
				local live: Record = {}
				local typed = derived[name]
				for key, resolved in props do
					local literal = resolved.literal
					local datatype = if typed
							and typed[key]
							and spec.fields[key] == nil
						then typed[key].datatype
						else nil
					local field = kindFields[key]
					if resolved.value ~= nil then
						values[key] = resolved.value
					elseif literal ~= nil and field ~= nil and field.type == "color" then
						values[key] = color(literal)
					elseif literal ~= nil and datatype ~= nil then
						values[key] = convert(datatype, literal)
					elseif literal ~= nil then
						values[key] = copy(literal)
					elseif resolved.readable ~= nil then
						live[key] = resolved.readable
					elseif resolved.callback ~= nil then
						live[key] = resolved.callback
					elseif resolved.node ~= nil then
						live[key] = resolved.node
					elseif resolved.slot ~= nil then
						live[key] = resolved.slot
					end
				end
				local states: { [string]: Compose.Value<unknown> } = {}
				for _, key in stateKeys(spec) do
					local initial = values[key]
					if name == "ColorPicker" and key == "value" then
						initial = color(initial)
					elseif name == "DateTimePicker" and key == "value" and values.time == true then
						local moment = record(initial)
						if moment ~= nil then
							moment.hour = moment.hour or 0
							moment.minute = moment.minute or 0
						end
					end
					local state = Compose.cell(initial)
					states[key] = state
					values[key] = state
				end
				for key, field in spec.fields do
					if field.format == "color" and states[key] == nil and values[key] ~= nil then
						values[key] = color(values[key])
					end
				end
				local setter = SETTERS[name]
				if setter ~= nil then
					local state = states[setter.key]
					if state ~= nil then
						local constant = setter.constant
						values[setter.property] = function(value: unknown)
							state:set(if constant ~= nil then constant else value)
						end
					end
				end
				if name == "Toggle" and values.mixed ~= nil and states.value ~= nil then
					local state = states.value
					values.onChange = function(value: unknown)
						state:set(value)
					end
				end
				if name == "NumberInput" then
					values.value = Compose.cell(tostring(values.numericValue or 0))
				end
				if name == "Image" or spec.nativeSize then
					local width, height = values.width, values.height
					local tall = if type(height) == "number" then height else 140
					values.Size = if width == "fill"
						then udim2(1, 0, 0, tall)
						else offset(if type(width) == "number" then width else 240, tall)
					values.width, values.height = nil, nil
				end
				local handled = ACTIONS[name]
				if handled ~= nil then
					for _, entry in handled do
						actions(values[entry.list], entry.handler)
					end
				end
				if name == "ComboBox" then
					values.acceptCustom = function(value: unknown): (boolean, unknown)
						return true, value
					end
				end
				if name == "NavBar" then
					values.onBack = noop
				end
				if name == "Skeleton" and values.form ~= "line" then
					values.lines = nil
				end
				if name == "LevelPicker" then
					values.images = if values.segment == "image" then values.images or copy(LEVEL_IMAGES) else nil
					if values.segment ~= "glyph" then
						values.glyphs = nil
					end
				end
				if name == "Toast" then
					if props.position ~= nil or props.width ~= nil or props.fade ~= nil then
						values.action, values.closeButton = nil, nil
					end
					local action = record(values.action)
					local presented = states.isPresented
					if action ~= nil and presented ~= nil then
						action.onActivate = function()
							presented:set(false)
						end
					end
				end
				if name == "Card" then
					local primary = record(values.primaryAction)
					if primary ~= nil then
						primary.onActivate = noop
					end
					local menu = record(values.menu)
					if menu ~= nil then
						actions(menu.items, "onSelect")
					end
				end
				if contentKey ~= nil then
					local slot = props[contentKey]
					local builder = if slot ~= nil then slot.slot else nil
					if builder ~= nil then
						local build = builder
						values[contentKey] = build
						if name == "Card" then
							values.image = nil
						end
					elseif name ~= "Card" then
						values[contentKey] = content({})
					end
				end
				if name == "ErrorBoundary" then
					values.view, values.fallback = content(children), content({})
				end
				local paged = PAGED_KINDS[name]
				if paged ~= nil then
					local pages = record(values[paged])
					if pages ~= nil then
						for index, page in pages do
							local entry = record(page)
							local child = if type(index) == "number" then children[index] else nil
							if entry ~= nil then
								entry.content = content(if child ~= nil then { child } else {})
							end
						end
					end
				end
				if name == "NavigationSplitView" then
					values.sidebar = content(if children[1] ~= nil then { children[1] } else {})
					values.detail = content(if children[2] ~= nil then { children[2] } else {})
				end
				if name == "NavigationStack" then
					local root = record(values.root)
					if root ~= nil then
						root.content = content(if children[1] ~= nil then { children[1] } else {})
					end
					local destinations = record(values.destinations)
					if destinations ~= nil then
						local keys: { string } = {}
						for key in destinations do
							if type(key) == "string" then
								table.insert(keys, key)
							end
						end
						table.sort(keys)
						for index, key in keys do
							local destination = record(destinations[key])
							local child = children[index + 1]
							if destination ~= nil then
								destination.content = content(if child ~= nil then { child } else {})
							end
						end
					end
				end
				if templated then
					local rows = props.from
					if rows ~= nil and rows.rows ~= nil then
						values.from = rows.rows
						if rows.key ~= nil then
							values.key = rows.key
						end
					end
					local row = props.render
					local template = if row ~= nil then row.template else nil
					if template ~= nil then
						values.render = template
					else
						values.render = function(current: Compose.ReadOnlyValue<Record>): unknown
							return UI.Text("RowLabel")({
								text = function(use: Compose.Use): string
									local item = use(current)
									return tostring(item.label or item.name or item.id or "Item")
								end,
								TextWrapped = true,
							})
						end
					end
				end
				if name == "Table" then
					local columns = record(values.columns)
					if columns ~= nil then
						for _, column in columns do
							local entry = record(column)
							if entry ~= nil then
								local field = entry.field or entry.id
								entry.value = function(item: Record): unknown
									return item[field]
								end
								entry.field = nil
							end
						end
					end
				end
				for key, value in live do
					values[key] = value
				end
				if TEMPLATE_KINDS[name] then
					for _, child in children do
						table.insert(values :: { unknown }, child)
					end
				elseif contentKey == nil and spec.container and not OWN_CHILDREN[name] then
					for _, child in children do
						table.insert(values :: { unknown }, child)
					end
				end
				local anchorKey = spec.anchor
				if anchorKey ~= nil then
					local presented = states.isPresented
					local trigger = UI.Button(name .. "Anchor")({
						label = values.anchorLabel or spec.defaults.anchorLabel or "Open",
						onActivate = function()
							if presented ~= nil then
								presented:set(true)
							end
						end,
					})
					values[anchorKey] = trigger
					values.anchorLabel = nil
					return UI.VStack(nodeName .. "Host")({ gap = "s", trigger, UI[name](nodeName)(values) })
				end
				return UI[name](nodeName)(values)
			end,
		}
	end
	local function generic(
		source: { [string]: Types.DerivedField },
		build: (nodeName: string, props: Record) -> unknown
	): (props: { [string]: Resolved }, children: { unknown }, nodeName: string) -> unknown
		return function(props: { [string]: Resolved }, children: { unknown }, nodeName: string): unknown
			local values: Record = {}
			for key, resolved in props do
				local literal = resolved.literal
				local field = source[key]
				local datatype = if field then field.datatype else nil
				if resolved.value ~= nil then
					values[key] = resolved.value
				elseif literal ~= nil and field ~= nil and field.type == "color" then
					values[key] = color(literal)
				elseif literal ~= nil and datatype ~= nil then
					values[key] = convert(datatype, literal)
				elseif literal ~= nil then
					values[key] = copy(literal)
				elseif resolved.readable ~= nil then
					values[key] = resolved.readable
				elseif resolved.callback ~= nil then
					values[key] = resolved.callback
				elseif resolved.node ~= nil then
					values[key] = resolved.node
				elseif resolved.slot ~= nil then
					values[key] = resolved.slot
				end
			end
			for _, child in children do
				table.insert(values :: { unknown }, child)
			end
			return build(nodeName, values)
		end
	end

	for name, entry in derived.controls do
		if kinds[name] == nil then
			kinds[name] = {
				fields = refine(name, plainFields(entry.fields)),
				children = if entry.children then "list" else "none",
				category = "More",
				call = "UI." .. name,
				build = generic(entry.fields, function(nodeName: string, values: Record): unknown
					return UI[name](nodeName)(values)
				end),
			}
		end
	end

	local host = context.host
	if host ~= nil then
		for className, entry in derived.host do
			if kinds[className] == nil then
				kinds[className] = {
					fields = plainFields(entry.fields),
					children = if entry.children then "list" else "none",
					category = "Roblox",
					call = "Host." .. className,
					build = generic(entry.fields, function(nodeName: string, values: Record): unknown
						return host(className, nodeName, values)
					end),
				}
			end
		end
	end

	return {
		name = "Facet",
		parameter = "UI",
		parameterType = "Facet.Controls",
		prelude = { 'local Facet = require(game:GetService("ReplicatedStorage").Facet)' },
		returnType = "GuiObject",
		readable = "Facet.ReadOnlyValue",
		cell = "Facet.Value",
		newCell = "Facet.Compose.cell",
		show = "Facet.Compose.show",
		tags = {
			call = "Facet.tag",
			apply = function(built: unknown, tags: { string })
				if typeof(built) == "Instance" then
					for _, name in tags do
						built:AddTag(name)
					end
				end
			end,
		},
		keyed = "Facet.Compose.keyed",
		space = "2d",
		provide = context.provide,
		categories = {
			"Layout",
			"Content",
			"Input",
			"Collections",
			"Navigation",
			"Overlays",
			"Status",
			"More",
			"Roblox",
		},
		kinds = kinds,
	}
end

return {
	create = create,
	controls = controls,
	seeds = seeds,
}
