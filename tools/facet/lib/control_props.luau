--!strict
local Files = require("./files")
local Run = require("./run")
local Luau = require("./luau")
local DesignFields = require("./design_fields")

type Variant = { name: string, parts: { string } }
type Recipe = {
	name: string,
	params: string?,
	native: string?,
	parts: { string }?,
	variants: { Variant }?,
	alias: string?,
	overrides: { [string]: string }?,
}
export type Family = { output: string, modules: { [string]: string }, recipes: { Recipe } }

local BUTTON = { "Inputs.EnabledOptions", "Inputs.ButtonVisualOptions", "Inputs.ButtonInputOptions" }
local FIELD = { "Inputs.FieldChrome", "Inputs.TextInputOptions", "Inputs.NumberOptions" }

local function with(base: { string }, ...: string): { string }
	local result = table.clone(base)
	for _, part in { ... } do
		table.insert(result, part)
	end
	return result
end

local FAMILIES: { Family } = {
	{
		output = "src/ui/spatial_grid_props.luau",
		modules = { Spatial = "./spatial_grid_types" },
		recipes = {
			{ name = "SpatialGridSpec", params = "V, K", native = "FrameProps", parts = { "Spatial.Options<V, K>" } },
		},
	},
	{
		output = "src/ui/hud_props.luau",
		modules = { Hud = "./hud_types", Media = "./media_types" },
		recipes = {
			{ name = "TimerProps", native = "TextLabelNativeProps", parts = { "Hud.TimerOptions" } },
			{ name = "WorldMarkerProps", native = "FrameProps", parts = { "Hud.WorldMarkerOptions" } },
			{
				name = "TypewriterProps",
				native = "TextLabelNativeProps",
				parts = { "Media.TextOptions", "Hud.TypewriterOptions" },
			},
		},
	},
	{
		output = "src/ui/layout_props.luau",
		modules = { Layout = "./layout_types" },
		recipes = {
			{ name = "StackProps", native = "FrameProps", parts = { "Layout.StackOptions" } },
			{ name = "ScreenProps", native = "FrameProps", parts = { "Layout.ScreenOptions" } },
			{ name = "ZStackProps", native = "FrameProps", parts = { "Layout.ZStackOptions" } },
			{ name = "ScrollViewProps", native = "ScrollingFrameProps", parts = { "Layout.ScrollViewOptions" } },
			{ name = "GridProps", native = "FrameProps", parts = { "Layout.GridOptions" } },
			{ name = "AdaptiveStackProps", native = "FrameProps", parts = { "Layout.AdaptiveStackOptions" } },
			{ name = "ViewThatFitsProps", native = "FrameProps", parts = { "Layout.ViewThatFitsOptions" } },
			{ name = "ErrorBoundaryProps", native = "FrameProps", parts = { "Layout.ErrorBoundaryOptions" } },
			{ name = "DividerProps", native = "FrameProps", parts = { "Layout.DividerOptions" } },
			{ name = "SpacerProps", native = "FrameProps", parts = { "Layout.SpacerOptions" } },
			{ name = "RegionProps", native = "FrameProps", parts = { "Layout.RegionOptions" } },
			{ name = "CompositionProps", native = "FrameProps", parts = { "Layout.CompositionOptions" } },
		},
	},
	{
		output = "src/ui/media_props.luau",
		modules = { Media = "./media_types" },
		recipes = {
			{ name = "TextProps", native = "TextLabelNativeProps", parts = { "Media.TextOptions" } },
			{ name = "LabelProps", native = "FrameNativeProps", parts = { "Media.LabelOptions" } },
			{ name = "ImageProps", native = "ImageLabelNativeProps", parts = { "Media.ImageOptions" } },
			{ name = "BadgeProps", native = "TextLabelProps", parts = { "Media.BadgeOptions" } },
			{ name = "StatusIndicatorProps", native = "TextLabelProps", parts = { "Media.StatusIndicatorOptions" } },
			{ name = "PathProps", native = "FrameProps", parts = { "Media.PathOptions" } },
			{ name = "ProgressViewProps", native = "FrameProps", parts = { "Media.ProgressViewOptions" } },
			{ name = "SkeletonProps", native = "FrameProps", parts = { "Media.SkeletonOptions" } },
			{ name = "AsyncImageProps", native = "FrameProps", parts = { "Media.AsyncImageOptions" } },
			{ name = "AvatarProps", native = "TextButtonProps", parts = { "Media.AvatarOptions" } },
			{ name = "AvatarGroupProps", native = "FrameProps", parts = { "Media.AvatarGroupOptions" } },
			{ name = "StageProps", native = "ViewportFrameProps", parts = { "Media.StageOptions" } },
		},
	},
	{
		output = "src/ui/input_props.luau",
		modules = {
			Inputs = "./input_types",
			Dates = "./date_time_picker_types",
			Colors = "./color_picker_types",
		},
		recipes = {
			{
				name = "ButtonProps",
				native = "TextButtonProps",
				parts = with(BUTTON, "Inputs.ButtonOptions", "Inputs.TextButtonOptions"),
			},
			{
				name = "ToggleProps",
				native = "TextButtonProps",
				parts = with(BUTTON, "Inputs.ToggleOptions", "Inputs.TextButtonOptions"),
				variants = {
					{ name = "ToggleCellProps", parts = { "Inputs.CellBinding<boolean>" } },
					{ name = "ToggleRequestProps", parts = { "Inputs.RequestBinding<boolean>" } },
				},
			},
			{
				name = "TextInputProps",
				native = "TextBoxProps",
				parts = FIELD,
				variants = {
					{
						name = "TextInputCellProps",
						parts = { "Inputs.CellBinding<string>", "Inputs.TextPresentation" },
					},
					{
						name = "TextInputRequestProps",
						parts = { "Inputs.RequestBinding<string>", "Inputs.TextPresentation" },
					},
					{
						name = "TextInputNumberCellProps",
						parts = { "Inputs.CellBinding<string>", "Inputs.NumberPresentation" },
					},
					{
						name = "TextInputNumberRequestProps",
						parts = { "Inputs.RequestBinding<string>", "Inputs.NumberPresentation" },
					},
				},
			},
			{
				name = "NumberInputProps",
				native = "TextBoxProps",
				parts = with(FIELD, "Inputs.NumberInputModel"),
				variants = {
					{ name = "NumberInputCellProps", parts = { "Inputs.CellBinding<string>" } },
					{ name = "NumberInputRequestProps", parts = { "Inputs.RequestBinding<string>" } },
				},
			},
			{
				name = "StepperProps",
				native = "FrameProps",
				parts = { "Inputs.ValueOptions", "Inputs.StepperOptions" },
				variants = {
					{ name = "StepperCellProps", parts = { "Inputs.CellBinding<number>" } },
					{ name = "StepperRequestProps", parts = { "Inputs.RequestBinding<number>" } },
				},
			},
			{
				name = "SliderProps",
				native = "FrameProps",
				parts = { "Inputs.ValueOptions", "Inputs.SliderOptions" },
				variants = {
					{ name = "SliderCellProps", parts = { "Inputs.SliderCellBinding" } },
					{ name = "SliderRequestProps", parts = { "Inputs.SliderRequestBinding" } },
					{ name = "SliderRangeProps", parts = { "Inputs.SliderRangeBinding" } },
				},
			},
			{
				name = "RatingProps",
				native = "TextButtonProps",
				parts = { "Inputs.RatingOptions" },
				variants = {
					{ name = "RatingCellProps", parts = { "Inputs.LevelCellBinding" } },
					{ name = "RatingRequestProps", parts = { "Inputs.LevelRequestBinding" } },
					{ name = "RatingReadOnlyProps", parts = { "Inputs.LevelReadOnlyBinding" } },
				},
			},
			{
				name = "LevelPickerProps",
				native = "TextButtonProps",
				parts = { "Inputs.LevelPickerOptions" },
				variants = {
					{ name = "LevelPickerCellProps", parts = { "Inputs.LevelCellBinding" } },
					{ name = "LevelPickerRequestProps", parts = { "Inputs.LevelRequestBinding" } },
					{ name = "LevelPickerReadOnlyProps", parts = { "Inputs.LevelReadOnlyBinding" } },
				},
			},
			{
				name = "ChipProps",
				native = "TextButtonNativeProps",
				parts = with(BUTTON, "Inputs.ChipOptions", "Inputs.TextButtonOptions"),
				variants = {
					{ name = "ChipCellProps", parts = { "Inputs.ChipCellSelection" } },
					{ name = "ChipRequestProps", parts = { "Inputs.ChipRequestSelection" } },
					{ name = "ChipRemovableProps", parts = { "Inputs.ChipRemoval" } },
				},
			},
			{
				name = "ShortcutHintProps",
				native = "TextLabelNativeProps",
				parts = { "Inputs.ShortcutHintOptions" },
				variants = {
					{ name = "ShortcutHintKeysProps", parts = { "Inputs.ShortcutKeys" } },
					{ name = "ShortcutHintActionProps", parts = { "Inputs.ShortcutAction" } },
				},
			},
			{ name = "ButtonGuideProps", native = "FrameNativeProps", parts = { "Inputs.ButtonGuideOptions" } },
			{ name = "DateTimePickerProps", native = "FrameProps", parts = { "Dates.DateTimePickerOptions" } },
			{ name = "ColorPickerProps", native = "FrameProps", parts = { "Colors.ColorPickerOptions" } },
		},
	},
	{
		output = "src/ui/navigation_props.luau",
		modules = { Nav = "./navigation_types", Inputs = "./input_types" },
		recipes = {
			{ name = "MenuSpec", params = "V = string", native = "FrameProps", parts = { "Nav.MenuOptions<V>" } },
			{
				name = "PickerSpec",
				params = "V = string",
				native = "GuiObjectProps",
				parts = { "Nav.PickerCommon<V>" },
				variants = {
					{ name = "SinglePickerSpec", parts = { "Nav.SingleSelection<V>" } },
					{ name = "MultiplePickerSpec", parts = { "Nav.MultipleSelection<V>" } },
				},
			},
			{
				name = "SplitButtonSpec",
				params = "V = string",
				native = "FrameProps",
				parts = { "Nav.SplitButtonOptions<V>" },
			},
			{ name = "ComboBoxSpec", native = "FrameProps", parts = { "Nav.ComboBoxOptions" } },
			{ name = "DisclosureGroupSpec", native = "FrameProps", parts = { "Nav.DisclosureGroupOptions" } },
			{
				name = "CollapsibleViewSpec",
				native = "TextButtonProps",
				parts = with(BUTTON, "Nav.CollapsibleViewOptions"),
			},
			{ name = "AlertSpec", params = "P = unknown", native = "FrameProps", parts = { "Nav.AlertOptions<P>" } },
			{ name = "SheetSpec", native = "FrameProps", parts = { "Nav.SheetOptions" } },
			{ name = "CalloutSpec", native = "FrameProps", parts = { "Nav.CalloutOptions" } },
			{ name = "TabViewSpec", native = "FrameProps", parts = { "Nav.TabViewOptions" } },
			{
				name = "NavigationStackSpec",
				params = "P = unknown",
				native = "FrameProps",
				parts = { "Nav.NavigationStackOptions<P>" },
			},
			{ name = "PageViewSpec", native = "FrameProps", parts = { "Nav.PageViewOptions" } },
			{
				name = "NavigationSplitViewProps",
				native = "FrameProps",
				parts = { "Nav.NavigationSplitViewOptions" },
			},
		},
	},
	{
		output = "src/ui/radial_props.luau",
		modules = { Radial = "./radial_types" },
		recipes = {
			{
				name = "RadialMenuSpec",
				params = "V = string",
				native = "FrameProps",
				parts = { "Radial.RadialMenuOptions<V>" },
			},
		},
	},
	{
		output = "src/ui/overlay_props.luau",
		modules = { Overlay = "./overlay_types" },
		recipes = {
			{ name = "DialogSpec", native = "FrameProps", parts = { "Overlay.DialogOptions" } },
			{ name = "PopoverSpec", native = "FrameProps", parts = { "Overlay.PopoverOptions" } },
			{ name = "NoticeSpec", native = "FrameProps", parts = { "Overlay.NoticeOptions" } },
			{ name = "NavBarSpec", native = "FrameProps", parts = { "Overlay.NavBarOptions" } },
			{ name = "ToastSpec", native = "FrameProps", parts = { "Overlay.ToastOptions" } },
		},
	},
	{
		output = "src/ui/collection_props.luau",
		modules = { Collections = "./collection_types" },
		recipes = {
			{
				name = "KeyedCollectionSpec",
				params = "V, K",
				overrides = { rowActions = "((current: Compose.ReadOnlyValue<V>, key: K) -> RowActionsOptions?)?" },
				native = "ScrollingFrameProps",
				parts = {
					"Collections.SelectionOptions<V, K>",
					"Collections.ReorderOptions<V, K>",
					"Collections.HierarchyOptions<V, K>",
					"Collections.CollectionOptions<V, K>",
					"Collections.OptionalChildren<V>",
					"Collections.Keyed<V, K>",
				},
			},
			{
				name = "IdentityCollectionSpec",
				params = "V",
				overrides = { rowActions = "((current: Compose.ReadOnlyValue<V>, key: V) -> RowActionsOptions?)?" },
				native = "ScrollingFrameProps",
				parts = {
					"Collections.SelectionOptions<V, V>",
					"Collections.ReorderOptions<V, V>",
					"Collections.HierarchyOptions<V, V>",
					"Collections.CollectionOptions<V, V>",
					"Collections.OptionalChildren<V>",
					"Collections.Identity",
				},
			},
			{
				name = "KeyedOutlineSpec",
				params = "V, K",
				overrides = { rowActions = "((current: Compose.ReadOnlyValue<V>, key: K) -> RowActionsOptions?)?" },
				native = "ScrollingFrameProps",
				parts = {
					"Collections.SelectionOptions<V, K>",
					"Collections.ReorderOptions<V, K>",
					"Collections.HierarchyOptions<V, K>",
					"Collections.CollectionOptions<V, K>",
					"Collections.RequiredChildren<V>",
					"Collections.Keyed<V, K>",
				},
			},
			{
				name = "IdentityOutlineSpec",
				params = "V",
				overrides = { rowActions = "((current: Compose.ReadOnlyValue<V>, key: V) -> RowActionsOptions?)?" },
				native = "ScrollingFrameProps",
				parts = {
					"Collections.SelectionOptions<V, V>",
					"Collections.ReorderOptions<V, V>",
					"Collections.HierarchyOptions<V, V>",
					"Collections.CollectionOptions<V, V>",
					"Collections.RequiredChildren<V>",
					"Collections.Identity",
				},
			},
			{ name = "RowActionsOptions", native = "FrameProps", parts = { "Collections.RowActionsFields" } },
			{
				name = "RowActionsSpec",
				native = "FrameProps",
				parts = { "Collections.RowActionsFields", "Collections.RowActionsContent" },
			},
			{ name = "CellEditorSpec", native = "FrameProps", parts = { "Collections.CellEditorOptions" } },
			{
				name = "KeyedTableSpec",
				params = "V, K",
				overrides = { rowActions = "((current: Compose.ReadOnlyValue<V>, key: K) -> RowActionsOptions?)?" },
				native = "FrameProps",
				parts = {
					"Collections.SelectionOptions<V, K>",
					"Collections.ReorderOptions<V, K>",
					"Collections.HierarchyOptions<V, K>",
					"Collections.TableOptions<V, K>",
					"Collections.OptionalChildren<V>",
					"Collections.Keyed<V, K>",
				},
			},
			{
				name = "IdentityTableSpec",
				params = "V",
				overrides = { rowActions = "((current: Compose.ReadOnlyValue<V>, key: V) -> RowActionsOptions?)?" },
				native = "FrameProps",
				parts = {
					"Collections.SelectionOptions<V, V>",
					"Collections.ReorderOptions<V, V>",
					"Collections.HierarchyOptions<V, V>",
					"Collections.TableOptions<V, V>",
					"Collections.OptionalChildren<V>",
					"Collections.Identity",
				},
			},
			{
				name = "CollectionSpec",
				params = "V, K",
				alias = "KeyedCollectionSpec<V, K> | IdentityCollectionSpec<V>",
			},
			{ name = "OutlineSpec", params = "V, K", alias = "KeyedOutlineSpec<V, K> | IdentityOutlineSpec<V>" },
			{ name = "TableSpec", params = "V, K", alias = "KeyedTableSpec<V, K> | IdentityTableSpec<V>" },
		},
	},
	{
		output = "src/ui/content_props.luau",
		modules = { Content = "./content_types" },
		recipes = {
			{ name = "PaginationSpec", native = "FrameProps", parts = { "Content.PaginationOptions" } },
			{ name = "StepIndicatorSpec", native = "FrameProps", parts = { "Content.StepIndicatorOptions" } },
			{ name = "VoteSpec", native = "FrameProps", parts = { "Content.VoteOptions" } },
			{ name = "CardSpec", native = "FrameProps", parts = { "Content.CardOptions" } },
		},
	},
	{
		output = "src/ui/effect_props.luau",
		modules = { Effects = "./effect_types" },
		recipes = {
			{ name = "FlashProps", native = "FrameProps", parts = { "Effects.FlashOptions" } },
		},
	},
	{
		output = "src/ui/zoom_travel_props.luau",
		modules = { ZoomTravel = "./zoom_travel_types" },
		recipes = {
			{ name = "ZoomViewProps", native = "ScrollingFrameProps", parts = { "ZoomTravel.ZoomViewOptions" } },
			{ name = "TravelProps", native = "FrameProps", parts = { "ZoomTravel.TravelOptions" } },
		},
	},
}

local ENGINE = "src/ui/engine_types.luau"

type FieldReader = (string, string) -> { string }

local function tableFields(): FieldReader
	local modules: { [string]: { [string]: Luau.Node } } = {}
	return function(path: string, name: string): { string }
		local types = modules[path]
		if types == nil then
			local parsed, problem = Luau.parse(Files.text(path))
			assert(parsed, `control_props: cannot parse {path}: {problem}`)
			types = {}
			for _, statement in Luau.items(parsed.root, "statements") do
				if Luau.tag(statement) == "typealias" and statement.export ~= nil then
					local key, value = Luau.tokenText(statement, "name"), Luau.child(statement, "type")
					if key and value then
						types[key] = value
					end
				end
			end
			modules[path] = types
		end
		local node = types[name]
		assert(node, `control_props: {path} has no exported type {name}`)
		assert(Luau.tag(node) == "table", `control_props: {name} in {path} must be one table type`)
		local fields: { string } = {}
		for _, entry in Luau.items(node, "entries") do
			local key = Luau.tokenText(entry, "key")
			if key then
				table.insert(fields, key)
			end
		end
		return fields
	end
end

export type Imports = { aliasOf: { [string]: string }, pathOf: { [string]: string }, lines: { string } }

local function splitArguments(text: string?): { string }
	if text == nil then
		return {}
	end
	local inner = assert(string.match(text, "^%s*<(.*)>%s*$"), `control_props: malformed type arguments {text}`)
	local result: { string } = {}
	local depth, start = 0, 1
	for index = 1, #inner do
		local character = string.sub(inner, index, index)
		if character == "<" or character == "{" or character == "(" then
			depth += 1
		elseif character == ">" or character == "}" or character == ")" then
			depth -= 1
		elseif character == "," and depth == 0 then
			table.insert(result, (string.gsub(string.sub(inner, start, index - 1), "^%s*(.-)%s*$", "%1")))
			start = index + 1
		end
	end
	table.insert(result, (string.gsub(string.sub(inner, start), "^%s*(.-)%s*$", "%1")))
	return result
end

type Declared = {
	parsed: Luau.Parsed,
	source: string,
	types: { [string]: Luau.Node },
	exported: { [string]: boolean },
	requires: { [string]: string },
}

local function declaredFields(): (string, string, string?, string, Imports) -> { [string]: string }
	local modules: { [string]: Declared } = {}
	local function load(path: string): Declared
		local found = modules[path]
		if found then
			return found
		end
		local source = Files.text(path)
		local parsed, problem = Luau.parse(source)
		assert(parsed, `control_props: cannot parse {path}: {problem}`)
		local declared: Declared = { parsed = parsed, source = source, types = {}, exported = {}, requires = {} }
		for _, statement in Luau.items(parsed.root, "statements") do
			if Luau.tag(statement) == "typealias" then
				local key = Luau.tokenText(statement, "name")
				if key then
					declared.types[key] = statement
					declared.exported[key] = statement.export ~= nil
				end
			end
		end
		for name, target in string.gmatch(source, '\nlocal ([%a_][%w_]*) = require%("([^"]+)"%)') do
			if name and target then
				declared.requires[name] = target
			end
		end
		modules[path] = declared
		return declared
	end
	local function slice(declared: Declared, node: Luau.Node): (number, number)
		local location = Luau.location(node)
		return Luau.offset(declared.parsed, location.beginLine, location.beginColumn),
			Luau.offset(declared.parsed, location.endLine, location.endColumn) - 1
	end
	return function(
		path: string,
		name: string,
		arguments: string?,
		alias: string,
		imports: Imports
	): { [string]: string }
		local declared = load(path)
		local statement = assert(declared.types[name], `control_props: {path} has no type {name}`)
		local generics: { [string]: string } = {}
		local values = splitArguments(arguments)
		for index, generic in Luau.items(statement, "generics") do
			local key = assert(Luau.tokenText(generic, "name"), `control_props: {name} has an unnamed generic`)
			generics[key] = values[index] or key
		end
		local function importAlias(prefix: string): string
			local target = declared.requires[prefix]
			if target == nil then
				return prefix
			end
			local existing = imports.aliasOf[target]
			if existing then
				return existing
			end
			assert(imports.pathOf[prefix] == nil, `control_props: alias {prefix} names two modules`)
			imports.aliasOf[target], imports.pathOf[prefix] = prefix, target
			table.insert(imports.lines, `local {prefix} = require("{target}")`)
			return prefix
		end
		local result: { [string]: string } = {}
		for _, entry in Luau.items(assert(Luau.child(statement, "type")), "entries") do
			local key = Luau.tokenText(entry, "key")
			local value = Luau.child(entry, "value")
			if key == nil or value == nil then
				continue
			end
			local first, last = slice(declared, value)
			local edits: { { first: number, last: number, text: string } } = {}
			Luau.walk(value, function(node: Luau.Node): boolean
				local tag = Luau.tag(node)
				assert(tag ~= "typeof", `control_props: {name}.{key} uses typeof`)
				if tag ~= "reference" then
					return true
				end
				local nameToken = assert(Luau.child(node, "name"))
				local prefixToken = Luau.child(node, "prefix")
				local text = assert(Luau.text(nameToken))
				local replacement: string? = nil
				if prefixToken then
					replacement = importAlias(assert(Luau.text(prefixToken))) .. "." .. text
				elseif generics[text] then
					replacement = generics[text]
				elseif declared.types[text] then
					assert(declared.exported[text], `control_props: {path} must export {text} for {name}.{key}`)
					replacement = alias .. "." .. text
				end
				if replacement then
					local from = slice(declared, prefixToken or nameToken)
					local _, to = slice(declared, nameToken)
					table.insert(edits, { first = from, last = to, text = replacement })
				end
				return true
			end)
			table.sort(edits, function(a, b)
				return a.first > b.first
			end)
			local text = string.sub(declared.source, first, last)
			for _, edit in edits do
				text = string.sub(text, 1, edit.first - first) .. edit.text .. string.sub(text, edit.last - first + 2)
			end
			result[key] = text
		end
		return result
	end
end

local function camel(name: string): string
	return string.lower(string.sub(name, 1, 1)) .. string.sub(name, 2)
end

type Part = { alias: string, name: string, arguments: string?, text: string }

local function parsePart(text: string): Part
	local alias, name, arguments = string.match(text, "^([%a_][%w_]*)%.([%a_][%w_]*)(.*)$")
	assert(alias and name, `control_props: malformed part {text}`)
	return { alias = alias, name = name, arguments = if arguments == "" then nil else arguments, text = text }
end

local function generate(family: Family): string
	local readFields = tableFields()
	local readDeclared = declaredFields()
	local lines =
		{ "--!strict", 'local Compose = require("../vendor/compose/core")', 'local Engine = require("./engine_types")' }
	local imports: Imports = {
		aliasOf = { ["../vendor/compose/core"] = "Compose", ["./engine_types"] = "Engine" },
		pathOf = { Compose = "../vendor/compose/core", Engine = "./engine_types" },
		lines = {},
	}
	for alias, path in family.modules do
		imports.aliasOf[path], imports.pathOf[alias] = alias, path
	end
	local aliases = {}
	for alias in family.modules do
		table.insert(aliases, alias)
	end
	table.sort(aliases)
	for _, alias in aliases do
		table.insert(lines, `local {alias} = require("{family.modules[alias]}")`)
	end
	table.insert(lines, "")
	local blocks = {}
	local function body(recipe: Recipe, extra: { string }, tail: { string }?): { string }
		local out = {}
		local seen: { [string]: string } = {}
		local native = assert(recipe.native, `control_props: {recipe.name} has no native root props`)
		local nativeTypes = readDeclared(ENGINE, native, nil, "Engine", imports)
		for _, field in readFields(ENGINE, native) do
			seen[field] = native
			table.insert(out, `\t{field}: {nativeTypes[field]},`)
		end
		local parts = table.clone(recipe.parts or {})
		for _, part in extra do
			table.insert(parts, part)
		end
		for _, text in parts do
			local part = parsePart(text)
			local path = family.modules[part.alias]
			assert(path, `control_props: {family.output} has no module alias {part.alias}`)
			local file = "src/ui/" .. string.sub(path, 3) .. ".luau"
			local declared = readDeclared(file, part.name, part.arguments, part.alias, imports)
			for _, field in readFields(file, part.name) do
				assert(
					seen[field] == nil,
					`control_props: {recipe.name} receives {field} from {seen[field]} and {text}`
				)
				seen[field] = text
				local override = recipe.overrides and recipe.overrides[field]
				table.insert(out, `\t{field}: {override or declared[field]},`)
			end
		end
		if tail then
			table.move(tail, 1, #tail, #out + 1, out)
		end
		table.insert(out, "\t[number | Engine.EventKey]: Compose.Child,")
		return out
	end
	local function shapeBlocks(recipe: Recipe, variants: { Variant }, params: string, arguments: string)
		local order: { string } = {}
		local types: { { [string]: string } } = {}
		for index, variant in variants do
			local fields: { [string]: string } = {}
			for _, text in variant.parts do
				local part = parsePart(text)
				local path = family.modules[part.alias]
				assert(path, `control_props: {family.output} has no module alias {part.alias}`)
				local file = "src/ui/" .. string.sub(path, 3) .. ".luau"
				local declared = readDeclared(file, part.name, part.arguments, part.alias, imports)
				for _, field in readFields(file, part.name) do
					assert(fields[field] == nil, `control_props: {variant.name} receives {field} twice`)
					if not table.find(order, field) then
						table.insert(order, field)
					end
					fields[field] = declared[field]
				end
			end
			types[index] = fields
		end
		local shape = string.gsub(string.gsub(recipe.name, "Props$", ""), "Spec$", "") .. "Shape"
		local leading = if recipe.params then string.sub(arguments, 2, -2) .. ", " else ""
		local generics: { string } = {}
		local tail: { string } = {}
		for _, field in order do
			local generic = string.upper(string.sub(field, 1, 1)) .. string.sub(field, 2) .. "Field"
			table.insert(generics, generic)
			table.insert(tail, `\t{field}: {generic},`)
		end
		table.insert(blocks, `type {shape}<{leading}{table.concat(generics, ", ")}> = \{`)
		for _, line in body(recipe, {}, tail) do
			table.insert(blocks, line)
		end
		table.insert(blocks, "}")
		local names: { string } = {}
		for index, variant in variants do
			local values: { string } = {}
			for _, field in order do
				table.insert(values, types[index][field] or "nil")
			end
			table.insert(blocks, `export type {variant.name}{params} = {shape}<{leading}{table.concat(values, ", ")}>`)
			table.insert(names, variant.name .. arguments)
		end
		table.insert(blocks, `export type {recipe.name}{params} = {table.concat(names, " | ")}`)
	end
	for _, recipe in family.recipes do
		local params = if recipe.params then `<{recipe.params}>` else ""
		local arguments = if recipe.params
			then "<" .. string.gsub(string.gsub(recipe.params, "%s*=%s*[^,]+", ""), "%s+", " ") .. ">"
			else ""
		if recipe.alias then
			table.insert(blocks, `export type {recipe.name}{params} = {recipe.alias}`)
		elseif recipe.variants then
			shapeBlocks(recipe, recipe.variants, params, arguments)
		else
			table.insert(blocks, `export type {recipe.name}{params} = \{`)
			for _, line in body(recipe, {}) do
				table.insert(blocks, line)
			end
			table.insert(blocks, "}")
		end
	end
	table.sort(imports.lines)
	for _, line in imports.lines do
		table.insert(lines, line)
	end
	table.insert(lines, "")
	for _, line in blocks do
		table.insert(lines, line)
	end
	table.insert(lines, "")
	table.insert(lines, "return {}")
	table.insert(lines, "")
	return table.concat(lines, "\n")
end

local function format(text: string, scratch: string): string
	local formatted = text
	for _ = 1, 2 do
		Files.write(scratch, formatted)
		local result = Run.capture({ "stylua", scratch }, { timeout = 120 })
		if not result.ok then
			error(("stylua could not format the generated control props: %s%s"):format(result.stdout, result.stderr), 0)
		end
		formatted = Files.text(scratch)
	end
	Files.remove(scratch)
	return formatted
end

local ControlProps = {}

ControlProps.FAMILIES = FAMILIES

function ControlProps.optionOrigins(root: string): { [string]: { [string]: string } }
	local readFields = tableFields()
	local origins: { [string]: { [string]: string } } = {}
	for _, family in FAMILIES do
		local function fields(parts: { string }): { [string]: string }
			local found: { [string]: string } = {}
			for _, text in parts do
				local part = parsePart(text)
				local module = assert(family.modules[part.alias])
				local file = Files.join(root, "src/ui", string.sub(module, 3) .. ".luau")
				for _, field in readFields(file, part.name) do
					if string.match(field, "^[a-z]") then
						found[field] = part.name
					end
				end
			end
			return found
		end
		for _, recipe in family.recipes do
			local base = fields(recipe.parts or {})
			if recipe.native then
				for _, field in readFields(Files.join(root, ENGINE), recipe.native) do
					if string.match(field, "^[a-z]") then
						base[field] = recipe.native
					end
				end
			end
			for field in recipe.overrides or {} :: { [string]: string } do
				base[field] = nil
			end
			if recipe.variants then
				local common = table.clone(base)
				for _, variant in recipe.variants do
					local variantFields = table.clone(common)
					for field, origin in fields(variant.parts) do
						variantFields[field] = origin
						base[field] = origin
					end
					origins[variant.name] = variantFields
				end
			end
			if recipe.alias then
				for name in string.gmatch(recipe.alias, "([%w_]+)[<| ]") do
					for field, origin in origins[name] or {} :: { [string]: string } do
						base[field] = base[field] or origin
					end
				end
			end
			origins[recipe.name] = base
		end
	end
	return origins
end

function ControlProps.generate(family: Family, scratchDirectory: string): string
	local name = assert(string.match(family.output, "[^/]+$"), "control_props: output has no file name")
	return format(generate(family), Files.join(scratchDirectory, name))
end

function ControlProps.stale(scratchDirectory: string): ({ string }, { [string]: string })
	local stale: { string } = {}
	local texts: { [string]: string } = {}
	for _, family in FAMILIES do
		local text = ControlProps.generate(family, scratchDirectory)
		local current = if Files.isFile(family.output) then Files.text(family.output) else nil
		if current ~= text then
			table.insert(stale, family.output)
			texts[family.output] = text
		end
	end
	local fieldsText = format(DesignFields.generate("."), Files.join(scratchDirectory, "fields.luau"))
	local current = if Files.isFile(DesignFields.OUTPUT) then Files.text(DesignFields.OUTPUT) else nil
	if current ~= fieldsText then
		table.insert(stale, DesignFields.OUTPUT)
		texts[DesignFields.OUTPUT] = fieldsText
	end
	return stale, texts
end

return ControlProps
