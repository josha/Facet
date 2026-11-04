--!strict

local Compose = require("../vendor/compose/core")
local Design = require("../vendor/compose/design")
local Types = require("./types")
local controls = require("./controls")
local derived = require("./fields")
local icons = require("../ui/icons")
local Motion = require("./motion")
local Roblox3D = require("../vendor/compose/design-editor/roblox-3d-library")
local robloxTypes = require("../ui/roblox_types")

type Literal = Design.Literal
type Resolved = Design.Resolved
type Record = { [unknown]: unknown }
type Construct = (props: Record, name: string?) -> unknown

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
	for key, item in value do
		result[key] = copy(item)
	end
	return result
end

local function record(value: unknown): Record?
	return if type(value) == "table" then value :: Record else nil
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

local CHOICE: Design.FieldType = "choice"

local function iconic(key: string, kind: Design.FieldType): boolean
	return kind == "string" and string.match(key, "[iI]con$") ~= nil
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

local SLICE_CENTER: Design.Row = { x0 = 0, y0 = 0, x1 = 1, y1 = 1 }

local FIELD_DEFAULTS: { [string]: { [string]: Literal } } = {
	NavigationSplitView = { maxSidebarWidth = 480 },
	ProgressView = { min = 0, sweep = 240 },
	Image = { sliceCenter = SLICE_CENTER },
}

local ON_BY_DEFAULT: { [string]: true } = { Visible = true, Interactable = true, AutoLocalize = true, enabled = true }

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
		elseif field.default == nil and field.type == "boolean" and ON_BY_DEFAULT[key] then
			field.default = true
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
		local icon = iconic(key, field.type)
		fields[key] = {
			type = if icon then CHOICE else field.type,
			options = if icon then ICONS else field.options,
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
	local typed = derivedFields(name)
	for key, field in typed do
		if
			spec.fields[string.lower(string.sub(key, 1, 1)) .. string.sub(key, 2)] ~= nil and string.match(key, "^%u")
		then
			continue
		end
		order += 1
		local icon = iconic(key, field.type)
		fields[key] = {
			type = if icon then CHOICE else field.type,
			options = if icon then ICONS else field.options,
			datatype = if field.type == "color" then "Color3" else field.datatype,
			also = field.also,
			group = "More",
			order = order,
			advanced = true,
		}
	end
	for key, field in spec.fields do
		local also: { string }? = if field.format == "padding"
			then { "number", "table" }
			elseif field.format == "spacing" then { "number" }
			else nil
		local runtime = typed[key]
		local kind = if runtime ~= nil then LITERAL_KINDS[runtime.type] else nil
		local own = LITERAL_KINDS[field.type]
		if kind ~= nil and kind ~= own and (also == nil or table.find(also, kind) == nil) then
			local list = also or {}
			table.insert(list, kind)
			also = list
		end
		local icon = iconic(key, field.type)
		local result: Design.Field = {
			type = if icon then CHOICE else field.type,
			options = if icon then ICONS else field.options,
			order = field.order,
			label = field.label,
			default = field.default,
			datatype = if field.type == "color" then "Color3" else nil,
			also = also,
			tokens = field.tokens,
		}
		if field.perRow ~= nil then
			result.perRow = field.perRow
		end
		local luauType = if field.format == "padding"
			then "Facet.Sides"
			elseif key == "options" and OPTION_LISTS[name] then "{ Facet.PickerOption<string> }"
			elseif key == "columns" and name == "Table" then "{ Facet.TableColumn<$Item, $Key> }"
			elseif key == "rowActions" then "Facet.RowActionsOptions?"
			elseif name == "Sheet" and key == "detents" then "{ Facet.SheetDetent }"
			elseif key == "actions" then "{ Facet." .. (if name == "Dialog"
				then "DialogAction"
				elseif name == "Alert" then "AlertAction"
				else "OverlayAction") .. " }"
			elseif name == "RowActions" and (key == "leading" or key == "trailing") then "{ Facet.RowAction }"
			else nil
		if luauType then
			result.luauType = luauType
		end
		fields[key] = result
	end
	if spec.content then
		fields[spec.content] = { type = "content", label = "Content", group = "Control" }
	end
	return fields
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
	if spec.container ~= true and spec.content == nil then
		return {}
	end
	local props: { [string]: Types.Literal } = { text = "Make this content yours" }
	local placeholder: Types.Seed = { kind = "Text", props = props }
	return { placeholder }
end

local function color(types: Types.RobloxTypes, value: unknown): unknown
	if type(value) == "string" and string.match(value, "^#%x%x%x%x%x%x$") then
		return types.Color3.fromHex(value)
	end
	return value
end

local function enumItem(types: Types.RobloxTypes, enumName: string, item: string): unknown
	for _, enum in types.Enum:GetEnums() do
		if tostring(enum) == enumName then
			return enum:FromName(item)
		end
	end
	return nil
end

local function native3dKinds(): { [string]: Types.DerivedKind }
	local schema = Roblox3D.schema()
	local mappings: { [string]: { [string]: string } } = {
		Model = {},
		Part = {
			Size = "size",
			Color = "color",
			Material = "material",
			Transparency = "transparency",
			CanCollide = "canCollide",
		},
		PointLight = { Brightness = "brightness", Range = "range", Color = "color" },
	}
	local result: { [string]: Types.DerivedKind } = {}
	for name, mapping in mappings do
		local kind = schema.kinds[name]
		local fields: { [string]: Types.DerivedField } = {}
		for property, key in mapping do
			local field = kind.fields[key]
			fields[property] = {
				type = if property == "Material" or property == "Size" then "datatype" else field.type,
				options = field.options,
				datatype = if property == "Material"
					then "Enum.Material"
					elseif property == "Size" then "Vector3"
					else nil,
			}
		end
		result[name] = { children = kind.children == "list", fields = fields }
	end
	result.Part.fields.CFrame = { type = "datatype", datatype = "CFrame" }
	result.Part.fields.Anchored = { type = "boolean" }
	return result
end

local function create(context: Context): Design.Library
	local UI = context.UI :: { [string]: Construct }
	local types = context.types or robloxTypes()

	local function convert(datatype: string, literal: Literal): unknown
		if datatype == "Color3" then
			return color(types, literal)
		end
		local enumName = string.match(datatype, "^Enum%.(.+)$")
		if enumName ~= nil then
			return if type(literal) == "string" then enumItem(types, enumName, literal) else literal
		end
		if type(literal) ~= "table" then
			return literal
		end
		if datatype == "CFrame" then
			local components: { number } = {}
			for _, component in literal do
				assert(type(component) == "number", "CFrame components must be numbers")
				table.insert(components, component)
			end
			if #components == 0 then
				return types.CFrame.new()
			elseif #components == 3 then
				return types.CFrame.new(components[1], components[2], components[3])
			elseif #components == 7 then
				return types.CFrame.new(
					components[1],
					components[2],
					components[3],
					components[4],
					components[5],
					components[6],
					components[7]
				)
			end
			assert(#components == 12, "CFrame needs zero, three, seven or twelve components")
			return types.CFrame.new(
				components[1],
				components[2],
				components[3],
				components[4],
				components[5],
				components[6],
				components[7],
				components[8],
				components[9],
				components[10],
				components[11],
				components[12]
			)
		end
		local a, b, c, d = 0, 0, 0, 0
		local count = 0
		for _, component in literal do
			if type(component) == "number" then
				count += 1
				if count == 1 then
					a = component
				elseif count == 2 then
					b = component
				elseif count == 3 then
					c = component
				elseif count == 4 then
					d = component
				end
			end
		end
		if datatype == "UDim2" then
			return types.UDim2.new(a, b, c, d)
		elseif datatype == "UDim" then
			return types.UDim.new(a, b)
		elseif datatype == "Vector2" then
			return types.Vector2.new(a, b)
		elseif datatype == "Vector3" then
			return types.Vector3.new(a, b, c)
		elseif datatype == "Rect" then
			return types.Rect.new(a, b, c, d)
		elseif datatype == "NumberRange" then
			return types.NumberRange.new(a, b)
		end
		return nil
	end

	local function binding(resolved: Resolved, datatype: string?): unknown
		local source = resolved.readable
		if source ~= nil and datatype ~= nil then
			return function(use: Compose.Use): unknown
				local current = use(source)
				return if current ~= nil then convert(datatype, current) else nil
			end
		end
		return source or resolved.callback or resolved.node or resolved.slot
	end

	local function stack(children: { unknown }): unknown
		local props: Record = { gap = "s", width = "fill" }
		for _, child in children do
			props[#props + 1] = child
		end
		return UI.VStack(props, "Content")
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
		local bound = templated or name == "Table"
		local kindFields = refine(name, fieldsOf(name, spec))
		kinds[name] = {
			fields = kindFields,
			defaults = spec.defaults,
			seeds = if spec.seeds ~= nil or contentKey ~= nil then seeds(name) else nil,
			children = if bound
				then "template"
				elseif contentKey ~= nil then "slot"
				elseif spec.container then "list"
				else "none",
			slot = contentKey,
			leaf = if spec.container and spec.category ~= "Layout" then true else nil,
			category = spec.category,
			source = if bound then "from" else nil,
			template = if templated then "render" else nil,
			key = if bound then "key" else nil,
			call = "UI." .. name,
			build = function(props: { [string]: Resolved }, children: { unknown }, nodeName: string): unknown
				local values: Record = {}
				local live: Record = {}
				local entry = derived.controls[name]
				local typed = if entry then entry.fields else nil
				for key, value in spec.defaults do
					local declared = if typed then typed[key] else nil
					local datatype = if declared and spec.fields[key] == nil then declared.datatype else nil
					values[key] = if datatype ~= nil then convert(datatype, value) else copy(value)
				end
				for key, resolved in props do
					local field = kindFields[key]
					local datatype = if field then field.datatype else nil
					local literal = resolved.literal
					if resolved.value ~= nil then
						values[key] = resolved.value
					elseif literal ~= nil then
						values[key] = if datatype then convert(datatype, literal) else copy(literal)
					else
						live[key] = binding(resolved, datatype)
					end
				end
				local states: { [string]: Compose.Value<unknown> } = {}
				local stateKey = spec.state
				for _, key in spec.states or (if stateKey ~= nil then { stateKey } else {}) do
					local initial = values[key]
					if name == "ColorPicker" and key == "value" then
						initial = color(types, initial)
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
						values[key] = color(types, values[key])
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
				local mixedState = states.value
				if name == "Toggle" and values.mixed ~= nil and mixedState ~= nil then
					values.onChange = function(value: unknown)
						mixedState:set(value)
					end
				end
				if name == "NumberInput" then
					values.value = Compose.cell(tostring(values.numericValue or 0))
				end
				if name == "Image" or (spec.nativeSize and (values.width ~= nil or values.height ~= nil)) then
					local width, height = values.width, values.height
					local tall = if type(height) == "number" then height else 140
					values.Size = if width == "fill"
						then types.UDim2.new(1, 0, 0, tall)
						else types.UDim2.fromOffset(if type(width) == "number" then width else 240, tall)
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
				local rows = props.from
				if bound and rows ~= nil and rows.rows ~= nil then
					values.from = rows.rows
					if rows.key ~= nil then
						values.key = rows.key
					end
				end
				if templated then
					local row = props.render
					local template = if row ~= nil then row.template else nil
					if template ~= nil then
						values.render = template
					else
						values.render = function(current: Compose.ReadOnlyValue<Record>): unknown
							return UI.Text({
								text = function(use: Compose.Use): string
									local item = use(current)
									return tostring(item.label or item.name or item.id or "Item")
								end,
								TextWrapped = true,
							}, "RowLabel")
						end
					end
				end
				if
					name == "Menu"
					and (values.trigger ~= nil or live.trigger ~= nil)
					and values.label == spec.defaults.label
				then
					values.label = nil
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
						values[#values + 1] = child
					end
				elseif contentKey == nil and spec.container and not OWN_CHILDREN[name] then
					for _, child in children do
						values[#values + 1] = child
					end
				end
				local anchorKey = spec.anchor
				if anchorKey ~= nil then
					local presented = states.isPresented
					local trigger = UI.Button({
						label = values.anchorLabel or spec.defaults.anchorLabel or "Open",
						onActivate = function()
							if presented ~= nil then
								presented:set(true)
							end
						end,
					}, name .. "Anchor")
					values[anchorKey] = trigger
					values.anchorLabel = nil
					return UI.VStack({ gap = "s", trigger, UI[name](values, nodeName) }, nodeName .. "Host")
				end
				return UI[name](values, nodeName)
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
				local field = source[key]
				local datatype = if field and field.type == "color"
					then "Color3"
					elseif field then field.datatype
					else nil
				local literal = resolved.literal
				if resolved.value ~= nil then
					values[key] = resolved.value
				elseif literal ~= nil then
					values[key] = if datatype then convert(datatype, literal) else copy(literal)
				else
					values[key] = binding(resolved, datatype)
				end
			end
			for _, child in children do
				values[#values + 1] = child
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
					return UI[name](values, nodeName)
				end),
			}
		end
	end

	local host = context.host
	if host ~= nil then
		local hostKinds = table.clone(derived.host)
		for className, entry in native3dKinds() do
			hostKinds[className] = entry
		end
		for className, entry in hostKinds do
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

	local tokens = context.tokens
	if tokens ~= nil then
		for _, kind in kinds do
			for key, field in kind.fields do
				if
					field.type == "color"
					or field.type == "number"
					or field.type == "datatype"
					or key == "width"
					or key == "height"
					or string.match(key, "[Gg]ap$")
					or string.match(key, "[Pp]adding")
				then
					field.tokens = true
				end
			end
		end
	end
	local prelude = { 'local Facet = require(game:GetService("ReplicatedStorage").Facet)' }
	if tokens ~= nil then
		table.insert(prelude, tokens.require)
	end
	local library: Design.Library = {
		name = "Facet",
		parameter = "UI",
		parameterType = "Facet.Controls",
		prelude = prelude,
		token = if tokens ~= nil then tokens.path else nil,
		returnType = if context.space == "3d" then "Instance" else "GuiObject",
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
		motion = {
			call = "UI.follow",
			roles = Motion.roles,
			animate = if context.motion then context.motion.animate else nil,
		},
		sequence = {
			call = "UI.sequence",
			toward = "UI.toward",
			build = if context.motion then context.motion.sequence else nil,
		},
		space = context.space or "2d",
		containerKind = if context.space == "3d" then "Model" else nil,
		provide = context.provide,
		contentKind = "HStack",
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
	return if context.extension ~= nil then Design.extend(library, context.extension) else library
end

return {
	create = create,
	controls = controls,
	seeds = seeds,
}
