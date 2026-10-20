--!strict
local Files = require("./files")
local Run = require("./run")

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
			{ name = "ButtonProps", native = "TextButtonProps", parts = with(BUTTON, "Inputs.ButtonOptions") },
			{
				name = "ToggleProps",
				native = "TextButtonProps",
				parts = with(BUTTON, "Inputs.ToggleOptions"),
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
				parts = with(BUTTON, "Inputs.ChipOptions"),
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
				overrides = { rowActions = "((current: Compose.Readable<V>, key: K) -> RowActionsOptions?)?" },
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
				overrides = { rowActions = "((current: Compose.Readable<V>, key: V) -> RowActionsOptions?)?" },
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
				overrides = { rowActions = "((current: Compose.Readable<V>, key: K) -> RowActionsOptions?)?" },
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
				overrides = { rowActions = "((current: Compose.Readable<V>, key: V) -> RowActionsOptions?)?" },
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
				overrides = { rowActions = "((current: Compose.Readable<V>, key: K) -> RowActionsOptions?)?" },
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
				overrides = { rowActions = "((current: Compose.Readable<V>, key: V) -> RowActionsOptions?)?" },
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
local sources: { [string]: string } = {}

local function source(path: string): string
	local cached = sources[path]
	if cached == nil then
		cached = Files.text(path)
		sources[path] = cached
	end
	return cached
end

local function nativeFields(native: string, root: string?): { string }
	local text = source(if root then Files.join(root, ENGINE) else ENGINE)
	local start = string.find(text, `\nexport type {native} = \{\n`, 1, true)
	assert(start, `control_props: {ENGINE} has no table type {native}`)
	local body = string.match(text, "^(.-)\n}", start + #native + 17)
	assert(body, `control_props: {native} has no closing brace`)
	local fields = {}
	for name in string.gmatch(body, "\n\t([%a_][%w_]*):") do
		table.insert(fields, name)
	end
	return fields
end

local function skipString(text: string, index: number): number
	local quote = string.sub(text, index, index)
	local cursor = index + 1
	while cursor <= #text do
		local char = string.sub(text, cursor, cursor)
		if char == "\\" then
			cursor += 2
		elseif char == quote then
			return cursor + 1
		else
			cursor += 1
		end
	end
	error("control_props: unterminated string in a type")
end

local function optionFields(path: string, name: string): { string }
	local text = source(path)
	local header = string.find(text, `\nexport type {name}[%s<=]`)
	assert(header, `control_props: {path} has no exported type {name}`)
	local after = header + #name + 13
	if string.sub(text, after, after) == "<" then
		after = assert(string.find(text, ">", after, true), `control_props: {name} has unclosed type parameters`)
	end
	local equals = string.find(text, "=", after, true)
	assert(equals, `control_props: {name} has no definition`)
	local open = string.find(text, "%S", equals + 1)
	assert(open and string.sub(text, open, open) == "{", `control_props: {name} in {path} must be one table type`)
	local fields = {}
	local depth = 0
	local angle = 0
	local expecting = true
	local cursor = open
	while cursor <= #text do
		local char = string.sub(text, cursor, cursor)
		if char == '"' or char == "'" then
			cursor = skipString(text, cursor)
			expecting = false
			continue
		end
		if char == "<" then
			angle += 1
		elseif char == ">" and string.sub(text, cursor - 1, cursor - 1) ~= "-" then
			angle -= 1
		elseif angle > 0 then
			expecting = false
		elseif char == "{" or char == "(" or char == "[" then
			depth += 1
			if depth == 1 then
				expecting = true
			end
		elseif char == "}" or char == ")" or char == "]" then
			depth -= 1
			if depth == 0 then
				local after = string.match(text, "^%s*(%S)", cursor + 1)
				assert(after ~= "|" and after ~= "&", `control_props: {name} in {path} must be one table type`)
				return fields
			end
		elseif depth == 1 and char == "," then
			expecting = true
		elseif depth == 1 and expecting and string.match(char, "[%a_]") then
			local field = string.match(text, "^([%a_][%w_]*)%s*:", cursor)
			assert(field, `control_props: {name} in {path} has a malformed field near {cursor}`)
			table.insert(fields, field)
			cursor += #field
			expecting = false
			continue
		elseif depth == 1 and expecting and not string.match(char, "%s") then
			expecting = false
		end
		cursor += 1
	end
	error(`control_props: {name} in {path} has no closing brace`)
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
	local lines =
		{ "--!strict", 'local Compose = require("../vendor/compose/core")', 'local Engine = require("./engine_types")' }
	local aliases = {}
	for alias in family.modules do
		table.insert(aliases, alias)
	end
	table.sort(aliases)
	for _, alias in aliases do
		table.insert(lines, `local {alias} = require("{family.modules[alias]}")`)
	end
	table.insert(lines, "")
	local witnesses: { [string]: string } = {}
	local taken: { [string]: boolean } = {}
	local witnessLines = {}
	local function witness(key: string, typeText: string, short: string): string
		local existing = witnesses[key]
		if existing then
			return existing
		end
		local local_ = camel(short)
		if taken[local_] then
			local_ = camel(key)
		end
		taken[local_] = true
		witnesses[key] = local_
		table.insert(witnessLines, `local {local_} = (nil :: unknown) :: {typeText}`)
		return local_
	end
	local blocks = {}
	local function body(recipe: Recipe, extra: { string }, tail: { string }?): { string }
		local out = {}
		local seen: { [string]: string } = {}
		local native = assert(recipe.native, `control_props: {recipe.name} has no native root props`)
		local nativeWitness = witness(native, `Engine.{native}`, (string.gsub(native, "Props$", "")))
		for _, field in nativeFields(native) do
			seen[field] = native
			table.insert(out, `\t{field}: typeof({nativeWitness}.{field}),`)
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
			local access = if part.arguments
				then `((nil :: unknown) :: {part.text})`
				else witness(part.alias .. part.name, part.text, (string.gsub(part.name, "Options$", "")))
			for _, field in optionFields(file, part.name) do
				assert(
					seen[field] == nil,
					`control_props: {recipe.name} receives {field} from {seen[field]} and {text}`
				)
				seen[field] = text
				local override = recipe.overrides and recipe.overrides[field]
				table.insert(out, if override then `\t{field}: {override},` else `\t{field}: typeof({access}.{field}),`)
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
				local argument = if part.arguments then string.gsub(part.arguments, "[^%w]", "") else ""
				local access = if part.arguments and recipe.params
					then `((nil :: unknown) :: {part.text})`
					else witness(
						part.alias .. part.name .. argument,
						part.text,
						string.gsub(part.name, "Options$", "")
							.. string.upper(string.sub(argument, 1, 1))
							.. string.sub(argument, 2)
					)
				for _, field in optionFields(file, part.name) do
					assert(fields[field] == nil, `control_props: {variant.name} receives {field} twice`)
					if not table.find(order, field) then
						table.insert(order, field)
					end
					fields[field] = `typeof({access}.{field})`
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
	for _, line in witnessLines do
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
	local origins: { [string]: { [string]: string } } = {}
	for _, family in FAMILIES do
		local function fields(parts: { string }): { [string]: string }
			local found: { [string]: string } = {}
			for _, text in parts do
				local part = parsePart(text)
				local module = assert(family.modules[part.alias])
				local file = Files.join(root, "src/ui", string.sub(module, 3) .. ".luau")
				for _, field in optionFields(file, part.name) do
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
				for _, field in nativeFields(recipe.native, root) do
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
	return stale, texts
end

return ControlProps
