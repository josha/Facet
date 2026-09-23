--!strict
local decoration = require("./native_decoration")
local Compose = require("../vendor/compose/core")
local icons = require("./icons")
local ThemeTypes = require("./theme_types")
local Engine = require("./engine_types")
export type ThemePackage = ThemeTypes.ThemePackage
export type ThemeDefinition = ThemeTypes.ThemeDefinition
export type ThemeOptions = ThemeTypes.ThemeOptions
export type SkinOptions = ThemeTypes.SkinOptions
export type Themes = ThemeTypes.Themes

local themes = {}
themes.SCHEMA = "facet-theme/2"
themes.TYPE_ROLES = table.freeze({ "caption", "label", "body", "heading", "title", "control", "strong", "numeral" })
themes.REQUIRED_TYPE_ROLES = themes.TYPE_ROLES

local function copy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local out: { [unknown]: unknown } = {}
	for key, child in (value :: unknown) :: { [unknown]: unknown } do
		out[key] = copy(child)
	end
	return (out :: unknown) :: T
end

local function merge<T>(base: T, overrides: unknown): T
	local out = (copy(base) :: unknown) :: { [unknown]: unknown }
	for key, value in (overrides or {}) :: { [unknown]: unknown } do
		if key ~= "base" then
			out[key] = if type(value) == "table"
					and type(out[key]) == "table"
					and #(value :: { unknown }) == 0
				then merge(out[key], value)
				else copy(value)
		end
	end
	return (out :: unknown) :: T
end

local function rgb(r: number, g: number, b: number): ThemeTypes.RGB
	return { r = r / 255, g = g / 255, b = b / 255 }
end

local neutral: ThemeTypes.ThemePackage = {
	schema = themes.SCHEMA,
	identity = { id = "facet-neutral", displayName = "Facet Neutral", version = "2.0.0", schemaVersion = themes.SCHEMA },
	style = {
		defaultTheme = "Dark",
		themes = {
			{
				name = "Dark",
				colors = {
					surface = rgb(18, 20, 26),
					surfaceStrong = rgb(28, 31, 40),
					content = rgb(236, 239, 245),
					contentStrong = rgb(250, 251, 253),
					accent = rgb(44, 98, 210),
					onAccent = rgb(255, 255, 255),
					danger = rgb(176, 42, 42),
					onDanger = rgb(255, 255, 255),
					success = rgb(29, 122, 66),
					onSuccess = rgb(255, 255, 255),
					warning = rgb(212, 154, 28),
					onWarning = rgb(26, 20, 6),
				},
				extra = {
					control = rgb(41, 45, 58),
					controlHover = rgb(49, 54, 69),
					controlPressed = rgb(34, 37, 48),
					controlSelected = rgb(45, 58, 92),
					contentSecondary = rgb(158, 165, 182),
					hairline = rgb(255, 255, 255),
					hairlineOpacity = 0.92,
					disabledContentOpacity = 0.4,
					scrimOpacity = 0.45,
				},
			},
		},
	},
	metrics = {
		typography = {},
		space = { xs = 4, s = 8, m = 16, l = 24, xl = 40, tight = 6, gutter = 8 },
		radii = { control = 8, panel = 12, pill = 999 },
		strokes = { hairline = 1 },
		targetSizes = { minimum = 44 },
		controlSizes = {
			compact = { height = 36, paddingX = 8, iconSize = 16 },
			regular = { height = 44, paddingX = 12, iconSize = 20 },
			large = { height = 56, paddingX = 16, iconSize = 24 },
		},
		motion = { fast = 0.12, normal = 0.2 },
		iconSizes = { small = 16, medium = 20, large = 24 },
		controls = {
			progress = { trackHeight = 6, circularSize = 32, circularThickness = 3, spinnerDotSize = 4 },
			image = { defaultSize = 48 },
		},
	},
	chrome = {},
	assets = {},
	icons = {},
	rules = {},
}
for role, size in
	{ caption = 12, label = 14, body = 16, heading = 20, title = 24, control = 18, strong = 16, numeral = 18 } :: { [string]: number }
do
	neutral.metrics.typography[role] = {
		size = size,
		font = {
			family = "BuilderSans",
			weight = if role == "strong" or role == "heading" or role == "title" then "Bold" else "Regular",
			style = "Normal",
		},
		lineHeight = 1.2,
	}
end

local function read<T>(source: Engine.Value<T>, use: Compose.Use?): T
	if type(source) == "function" then
		return (source :: (Compose.Use) -> T)(use or function(value)
			return value:peek()
		end)
	end
	if type(source) == "table" and type(source.peek) == "function" then
		local readable = source :: Compose.Readable<T>
		return if use then use(readable) else readable:peek()
	end
	return source :: T
end

function themes.neutralPackage(): ThemeTypes.ThemePackage
	return copy(neutral)
end

local function frozen<T>(value: T): T
	if type(value) ~= "table" or table.isfrozen(value) then
		return value
	end
	for _, child in (value :: unknown) :: { [unknown]: unknown } do
		frozen(child)
	end
	return (table.freeze(value) :: unknown) :: T
end

function themes.define(definition: ThemeTypes.ThemeDefinition): (ThemeTypes.ThemePackage?, ThemeTypes.ThemeReport)
	local errors: { ThemeTypes.ThemeIssue } = {}
	local seen: { [unknown]: boolean } = {}
	local function validate(value: unknown, path: string)
		if type(value) == "number" and (value ~= value or math.abs(value) == math.huge) then
			table.insert(errors, { field = path, message = "Theme numbers must be finite" })
		elseif type(value) == "function" then
			table.insert(errors, { field = path, message = "Theme packages contain data, not callbacks" })
		elseif type(value) == "table" then
			if seen[value] then
				table.insert(errors, { field = path, message = "Theme packages cannot contain cycles" })
				return
			end
			seen[value] = true
			for key, child in value :: { [unknown]: unknown } do
				validate(child, path .. "." .. tostring(key))
			end
			seen[value] = nil
		end
	end
	if type(definition) ~= "table" then
		return nil,
			{
				ok = false,
				errors = { { field = "package", message = "Expected a package definition" } },
				missing = {},
				contrast = {},
			}
	end
	if definition.base ~= nil and type(definition.base) ~= "table" then
		table.insert(errors, { field = "base", message = "Theme base must be a package" })
	end
	validate(definition, "package")
	if #errors > 0 then
		return nil, { ok = false, errors = errors, missing = {}, contrast = {} }
	end
	local package = merge(definition.base or neutral, definition)
	if type(package.identity) ~= "table" or type(package.identity.id) ~= "string" then
		table.insert(errors, { field = "identity.id", message = "A theme package needs an identity" })
	end
	if type(package.style) ~= "table" or type(package.style.themes) ~= "table" or #package.style.themes == 0 then
		table.insert(errors, { field = "style.themes", message = "A theme package needs at least one palette" })
	end
	if #errors > 0 then
		return nil, { ok = false, errors = errors, missing = {}, contrast = {} }
	end
	package.schema = themes.SCHEMA
	local contrast: { ThemeTypes.ContrastResult } = {}
	local function luminance(value: ThemeTypes.RGB): number
		local function linear(channel: number): number
			return if channel <= 0.04045 then channel / 12.92 else ((channel + 0.055) / 1.055) ^ 2.4
		end
		return 0.2126 * linear(value.r) + 0.7152 * linear(value.g) + 0.0722 * linear(value.b)
	end
	for _, palette in package.style.themes do
		if
			type(palette) ~= "table"
			or type(palette.name) ~= "string"
			or (palette.colors ~= nil and type(palette.colors) ~= "table")
		then
			table.insert(errors, { field = "style.themes", message = "Palettes require a name and color dictionary" })
			continue
		end
		local colors = merge(neutral.style.themes[1].colors, palette.colors)
		local valid = true
		for role, value in colors do
			if
				type(value) ~= "table"
				or type(value.r) ~= "number"
				or type(value.g) ~= "number"
				or type(value.b) ~= "number"
				or value.r < 0
				or value.r ~= value.r
				or value.g ~= value.g
				or value.b ~= value.b
				or value.r > 1
				or value.g < 0
				or value.g > 1
				or value.b < 0
				or value.b > 1
			then
				valid = false
				table.insert(
					errors,
					{ field = "colors." .. role, message = "Colors require RGB components between zero and one" }
				)
			end
		end
		if valid then
			for _, pair in
				{
					{ "content", "surface" },
					{ "contentStrong", "surfaceStrong" },
					{ "onAccent", "accent" },
					{ "onDanger", "danger" },
					{ "onSuccess", "success" },
					{ "onWarning", "warning" },
				}
			do
				local first, second = luminance(colors[pair[1]]), luminance(colors[pair[2]])
				local ratio = (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05)
				table.insert(contrast, { pair = pair[1] .. "/" .. pair[2], ratio = ratio, ok = ratio >= 4.5 })
				if ratio < 4.5 then
					table.insert(
						errors,
						{ field = "style." .. palette.name, message = pair[1] .. " contrast is below 4.5:1" }
					)
				end
			end
		end
	end
	if #errors > 0 then
		return nil, { ok = false, errors = errors, missing = {}, contrast = contrast }
	end
	return frozen(package), { ok = true, errors = {}, missing = {}, contrast = contrast }
end

function themes.checkCoverage(
	package: ThemeTypes.ThemePackage,
	needs: { ThemeTypes.CoverageNeed }
): ThemeTypes.CoverageReport
	local missing: { { name: string, message: string, fix: string } }, covered: { string } = {}, {}
	for _, need in needs do
		local section: unknown = package
		for key in string.gmatch(need.section or "metrics", "[^.]+") do
			section = if type(section) == "table" then (section :: { [string]: unknown })[key] else nil
		end
		local present = true
		if need.kind == "color" then
			for _, palette in package.style.themes do
				if (palette.colors or {})[need.name] == nil and (palette.extra or {})[need.name] == nil then
					present = false
				end
			end
		else
			local value = if type(section) == "table" then (section :: { [string]: unknown })[need.name] else nil
			present = value ~= nil and (need.kind ~= "number" or type(value) == "number")
			for _, field in (need.fields or {}) :: { string } do
				if type(value) ~= "table" or type((value :: { [string]: unknown })[field]) ~= "number" then
					present = false
				end
			end
		end
		if present then
			table.insert(covered, need.name)
		else
			table.insert(missing, {
				name = need.name,
				message = "Theme has no " .. need.name,
				fix = "Declare " .. (need.section or "metrics") .. "." .. need.name,
			})
		end
	end
	return { ok = #missing == 0, missing = missing, covered = covered }
end

function themes.resolveIcon(package: ThemeTypes.IconRegistry, name: string, state: ThemeTypes.SkinState?): string?
	local assets = package.assets or {}
	local entry: ThemeTypes.IconEntry? = (package.icons or {})[name] or icons.ART[name]
	if type(entry) == "table" and ((entry :: unknown) :: { default: unknown }).default ~= nil then
		local variants = (entry :: unknown) :: { [string]: string | ThemeTypes.IconAsset }
		entry = variants[state or "default"] or variants.default
	end
	if type(entry) == "string" then
		entry = assets[entry] or { contentId = entry }
	end
	if type(entry) ~= "table" then
		return nil
	end
	local asset = entry :: ThemeTypes.IconAsset
	if asset.asset then
		asset = assets[asset.asset]
	end
	return if asset then asset.contentId or asset.content else nil
end

local function paletteFor(package: ThemeTypes.ThemePackage, requested: string?): ThemeTypes.Palette
	local name = requested or package.style.defaultTheme
	for _, palette in package.style.themes do
		if palette.name == name then
			return palette
		end
	end
	return package.style.themes[1]
end

local function typesFor(options: { types: Engine.RobloxTypes? }): Engine.RobloxTypes
	return options.types or getfenv(0)
end

local function color(types: Engine.RobloxTypes, value: ThemeTypes.RGB | Color3?): Color3?
	if type(value) == "table" and value.r ~= nil then
		return types.Color3.new(value.r, value.g, value.b)
	end
	return value :: Color3?
end

local function font(types: Engine.RobloxTypes, value: ThemeTypes.FontSpec | Font): Font
	if typeof(value) == "Font" then
		return value
	end
	local family = value.family or "BuilderSans"
	if not string.find(family, "://", 1, true) then
		family = "rbxasset://fonts/families/" .. family .. ".json"
	end
	return types.Font.new(
		family,
		((types.Enum.FontWeight :: unknown) :: { [string]: Enum.FontWeight })[value.weight or "Regular"],
		((types.Enum.FontStyle :: unknown) :: { [string]: Enum.FontStyle })[value.style or "Normal"]
	)
end

type NativeRule = { id: string, selector: string, properties: ThemeTypes.RuleProperties, priority: number }
local function rulesFor(package: ThemeTypes.ThemePackage, selected: string?, types: Engine.RobloxTypes): { NativeRule }
	local palette = paletteFor(package, selected)
	local colors = merge(neutral.style.themes[1].colors, palette.colors)
	local extra = merge(neutral.style.themes[1].extra :: ThemeTypes.PaletteExtra, palette.extra)
	local resolvedColors: { [string]: Color3? }, typefaces: { [string]: Font? } = {}, {}
	local function c(role: string): Color3?
		if resolvedColors[role] == nil then
			resolvedColors[role] = color(types, (colors[role] or extra[role]) :: ThemeTypes.RGB?)
		end
		return resolvedColors[role]
	end
	local function f(value: ThemeTypes.FontSpec | Font): Font
		if typeof(value) == "Font" then
			return value
		end
		local key = (value.family or "BuilderSans")
			.. ":"
			.. (value.weight or "Regular")
			.. ":"
			.. (value.style or "Normal")
		if typefaces[key] == nil then
			typefaces[key] = font(types, value)
		end
		return typefaces[key] :: Font
	end
	local rules: { NativeRule } = {}
	local function rule(selector: string, properties: ThemeTypes.RuleProperties)
		table.insert(rules, {
			id = selector .. ":" .. tostring(#rules + 1),
			selector = selector,
			properties = properties,
			priority = #rules * 10,
		})
		if string.sub(selector, -11) == "::UIPadding" then
			local real = string.sub(selector, 1, -12) .. " > UIPadding"
			table.insert(rules, {
				id = real .. ":" .. tostring(#rules + 1),
				selector = real,
				properties = properties,
				priority = #rules * 10,
			})
		end
	end
	rule(".facet-text", {
		TextColor3 = c("content"),
		FontFace = f(package.metrics.typography.body.font),
		TextSize = package.metrics.typography.body.size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
	for _, role in themes.TYPE_ROLES do
		local typography = package.metrics.typography[role] or neutral.metrics.typography[role]
		rule(".facet-type-" .. role, {
			FontFace = f(typography.font),
			TextSize = typography.size,
			LineHeight = typography.lineHeight or 1.2,
		})
	end
	rule(".facet-validation", { TextColor3 = c("danger"), TextSize = package.metrics.typography.caption.size })
	rule(".facet-secondary", { TextColor3 = c("contentSecondary") })
	rule(".facet-accent-text", { TextColor3 = c("accent") })
	rule(".facet-strong", { TextColor3 = c("contentStrong") })
	for _, role in
		{
			"surface",
			"panel",
			"control",
			"field",
			"button",
			"badge",
			"track",
			"skeleton",
			"avatar",
			"menu",
			"tab",
			"sheet",
		}
	do
		local paletteRole = if role == "surface"
			then "surface"
			elseif role == "panel" or role == "menu" or role == "sheet" then "surfaceStrong"
			else "control"
		rule(".facet-" .. role, { BackgroundColor3 = c(paletteRole), BackgroundTransparency = 0, BorderSizePixel = 0 })
		local radius = if role == "panel" or role == "sheet"
			then package.metrics.radii.panel
			else package.metrics.radii.control
		rule(".facet-" .. role .. "::UICorner", { CornerRadius = types.UDim.new(0, radius) })
	end
	rule(".facet-button", {
		TextColor3 = c("content"),
		FontFace = f(package.metrics.typography.control.font),
		TextSize = package.metrics.typography.control.size,
	})
	for _, role in
		{ "toggle", "toggle-indicator", "slider-rail", "slider-track", "chip", "shortcut-hint", "text-input" }
	do
		rule(".facet-" .. role, { BackgroundColor3 = c("control"), BackgroundTransparency = 0, BorderSizePixel = 0 })
	end
	for _, role in { "toggle-mark", "slider-fill", "slider-thumb", "selection-indicator" } do
		rule(".facet-" .. role, { BackgroundColor3 = c("accent"), BackgroundTransparency = 0, BorderSizePixel = 0 })
	end
	for role, slot in { button = "control", field = "field", badge = "badge", panel = "panel" } :: { [string]: string } do
		local recipe = (package.chrome or {})[slot]
		local inset: ThemeTypes.Insets = if recipe then recipe.contentInsets or {} else {}
		local horizontal = if role == "button" then 12 elseif role == "badge" then 8 else 0
		local vertical = if role == "badge" then 3 else 0
		rule(".facet-" .. role .. "::UIPadding", {
			PaddingLeft = types.UDim.new(0, math.max(horizontal, inset.left or 0)),
			PaddingRight = types.UDim.new(0, math.max(horizontal, inset.right or 0)),
			PaddingTop = types.UDim.new(0, math.max(vertical, inset.top or 0)),
			PaddingBottom = types.UDim.new(0, math.max(vertical, inset.bottom or 0)),
		})
	end
	local buttonInsets: ThemeTypes.Insets = if ((package.chrome or {}) :: { [string]: ThemeTypes.SkinLayer }).control
		then ((package.chrome or {}) :: { [string]: ThemeTypes.SkinLayer }).control.contentInsets or {}
		else {}
	rule(".facet-busy::UIPadding", { PaddingRight = types.UDim.new(0, math.max(12, buttonInsets.right or 0) + 20) })
	rule(".facet-shape-circle::UIPadding", {
		PaddingLeft = types.UDim.new(0, 0),
		PaddingRight = types.UDim.new(0, 0),
		PaddingTop = types.UDim.new(0, 0),
		PaddingBottom = types.UDim.new(0, 0),
	})
	rule(".facet-skinned", { BackgroundTransparency = 1 })
	rule(".facet-button-captioned", { TextTransparency = 1 })
	rule(".facet-button-caption", {
		TextTransparency = 0,
		TextColor3 = c("content"),
		FontFace = f(package.metrics.typography.control.font),
		TextSize = package.metrics.typography.control.size,
	})
	rule(".facet-accent >> .facet-button-caption", { TextColor3 = c("onAccent") })
	rule(".facet-disabled >> .facet-button-caption", { TextTransparency = extra.disabledContentOpacity })
	rule(".facet-skin-caption >> .facet-button-caption", { TextTransparency = 1 })
	rule(".facet-skin-caption-text", {
		TextTransparency = 0,
		TextColor3 = c("content"),
		BackgroundTransparency = 1,
		FontFace = f(package.metrics.typography.control.font),
		TextSize = package.metrics.typography.control.size,
	})
	rule(".facet-button:Hover", { BackgroundColor3 = c("controlHover") })
	rule(".facet-button:Press", { BackgroundColor3 = c("controlPressed") })
	rule(".facet-role-destructive", { BackgroundColor3 = c("danger"), TextColor3 = c("onDanger") })
	rule(".facet-role-destructive:Hover", { BackgroundColor3 = c("danger") })
	rule(".facet-role-destructive:Press", { BackgroundColor3 = c("danger") })
	rule(".facet-role-destructive >> .facet-button-caption", { TextColor3 = c("onDanger") })
	rule(".facet-role-cancel >> .facet-button-caption", { TextColor3 = c("contentSecondary") })
	rule(".facet-role-onIndicator >> .facet-button-caption", { TextColor3 = c("onAccent") })
	local onSelected = c("onSelected") or c("content")
	rule(".facet-selected", { BackgroundColor3 = c("controlSelected"), TextColor3 = onSelected })
	rule(".facet-selected >> .facet-text", { TextColor3 = onSelected })
	rule(".facet-disabled", { TextTransparency = extra.disabledContentOpacity })
	rule(".facet-accent", { BackgroundColor3 = c("accent"), TextColor3 = c("onAccent") })
	rule(".facet-fill", { BackgroundColor3 = c("accent"), BackgroundTransparency = 0, BorderSizePixel = 0 })
	rule(".facet-progress-ring-track", { Color3 = c("control") })
	rule(".facet-progress-ring-fill", { Color3 = c("accent") })
	rule(".facet-icon", { ImageColor3 = c("content"), BackgroundTransparency = 1 })
	rule(".facet-selected >> .facet-icon", { ImageColor3 = onSelected })
	rule(
		".facet-divider",
		{ BackgroundColor3 = c("hairline"), BackgroundTransparency = extra.hairlineOpacity, BorderSizePixel = 0 }
	)
	rule(".facet-scrim", {
		BackgroundColor3 = c("surface"),
		BackgroundTransparency = 1 - (extra.scrimOpacity or 0.45),
		BorderSizePixel = 0,
	})
	for status, role in
		{
			neutral = "contentSecondary",
			info = "accent",
			success = "success",
			warning = "warning",
			error = "danger",
			accent = "accent",
		} :: { [string]: string }
	do
		local partner = if status == "neutral"
			then "surface"
			elseif status == "error" then "onDanger"
			elseif status == "info" or status == "accent" then "onAccent"
			elseif status == "warning" then "onWarning"
			else "onSuccess"
		rule(".facet-status-" .. status, { BackgroundColor3 = c(role), TextColor3 = c(partner) })
	end
	rule(".facet-badge-utility", { BackgroundTransparency = 1, TextColor3 = c("contentSecondary") })
	rule(".facet-badge-status::UIPadding", { PaddingLeft = types.UDim.new(0, 20) })
	rule(".facet-cutout", { Color = c("surface") })
	for role, gradient in (extra.chromeGradient or {}) :: { [string]: ThemeTypes.Gradient } do
		local stops: { ColorSequenceKeypoint }, alpha: { NumberSequenceKeypoint } = {}, {}
		for _, stop in gradient.stops do
			table.insert(stops, types.ColorSequenceKeypoint.new(stop.t, types.Color3.new(stop.r, stop.g, stop.b)))
		end
		for _, stop in (gradient.alpha or {}) :: { { t: number, v: number } } do
			table.insert(alpha, types.NumberSequenceKeypoint.new(stop.t, stop.v))
		end
		if #stops >= 2 then
			local properties: ThemeTypes.RuleProperties =
				{ Color = types.ColorSequence.new(stops), Rotation = gradient.rotation or 90 }
			if #alpha >= 2 then
				properties.Transparency = types.NumberSequence.new(alpha)
			end
			rule(".facet-" .. role .. "::UIGradient", properties)
		end
	end
	for _, definition in (package.rules or {}) :: { ThemeTypes.Rule } do
		rule(definition.selector, table.clone(definition.properties or definition.props or {}))
	end
	return rules
end

local function sameProperties<T>(left: { [string]: T }, right: { [string]: T }): boolean
	for key, value in left do
		if right[key] ~= value then
			return false
		end
	end
	for key in right do
		if left[key] == nil then
			return false
		end
	end
	return true
end

local metatableOf = (getmetatable :: unknown) :: (unknown) -> unknown
local function deeplyFrozen(value: unknown, visited: { [unknown]: boolean }): boolean
	if type(value) ~= "table" then
		return true
	end
	if metatableOf(value) ~= nil then
		return false
	end
	local record = value :: { [unknown]: unknown }
	if not table.isfrozen(record) then
		return false
	end
	if visited[record] then
		return true
	end
	visited[record] = true
	for key, child in record do
		if not deeplyFrozen(key, visited) or not deeplyFrozen(child, visited) then
			return false
		end
	end
	return true
end

function themes.createStyleSheet(
	runtime: Compose.Runtime,
	packageOrReadable: Engine.Value<ThemeTypes.ThemePackage>?,
	options: ThemeTypes.ThemeOptions?
): StyleSheet
	local settings: ThemeTypes.ThemeOptions = options or {}
	local types = typesFor(settings)
	local Host = (runtime.constructors :: unknown) :: Engine.Host
	local reducedMotion = settings.reducedMotion
	if reducedMotion == nil then
		local globals = getfenv(0)
		local gui = globals.game and globals.game:GetService("GuiService")
		if gui then
			local source = Compose.cell(gui.ReducedMotionEnabled)
			reducedMotion = source
			local connection = gui:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
				source:set(gui.ReducedMotionEnabled)
			end)
			Compose.cleanup(function()
				connection:Disconnect()
			end)
		end
	end
	local previousSeconds: number?, defaultTiming: TweenInfo? = nil, nil
	local function timingFor(package: ThemeTypes.ThemePackage, use: Compose.Use): TweenInfo
		local explicit = read(settings.transition, use)
		local seconds
		if read(reducedMotion, use) == true or explicit == false then
			seconds = 0
		elseif explicit ~= nil then
			return explicit :: TweenInfo
		else
			seconds = ((package.metrics or {}) :: { motion: { [string]: number }? }).motion
					and package.metrics.motion.normal
				or 0.2
		end
		if seconds ~= previousSeconds then
			previousSeconds = seconds
			defaultTiming = types.TweenInfo.new(seconds, types.Enum.EasingStyle.Quad, types.Enum.EasingDirection.Out)
		end
		return defaultTiming :: TweenInfo
	end
	local definitions: { [string]: NativeRule } = {}
	type CompiledRules = {
		package: ThemeTypes.ThemePackage,
		palette: string?,
		rules: { NativeRule },
	}
	local compiled: { CompiledRules } = {}
	local function compiledRules(package: ThemeTypes.ThemePackage, palette: string?): { NativeRule }
		for index, cached in compiled do
			if cached.package == package and cached.palette == palette then
				if index > 1 then
					table.remove(compiled, index)
					table.insert(compiled, 1, cached)
				end
				return cached.rules
			end
		end
		local result = rulesFor(package, palette, types)
		if deeplyFrozen(package, {}) then
			for _, definition in result do
				local previous = definitions[definition.id]
				if previous and sameProperties(previous.properties, definition.properties) then
					definition.properties = previous.properties
				end
			end
			table.insert(compiled, 1, { package = package, palette = palette, rules = result })
			if #compiled > 2 then
				table.remove(compiled)
			end
		end
		return result
	end
	local ids = Compose.cell({} :: { string })
	local currentTiming: TweenInfo? = nil
	type MountedRule = {
		node: StyleRule,
		properties: ThemeTypes.RuleProperties?,
		transitions: { [string]: TweenInfo }?,
		timing: TweenInfo?,
	}
	local mounted: { [string]: MountedRule } = {}
	local function apply(record: MountedRule, definition: NativeRule, timing: TweenInfo)
		local properties = definition.properties
		local propertiesChanged = record.properties == nil
			or (record.properties ~= properties and not sameProperties(record.properties, properties))
		if not propertiesChanged and record.timing == timing then
			return
		end
		local transitions: { [string]: TweenInfo } = {}
		for property, value in properties do
			if typeof(value) == "Color3" or string.find(property, "Transparency$") then
				transitions[property] = timing
			end
		end
		local timingChanged = record.transitions == nil or not sameProperties(record.transitions, transitions)
		if timingChanged then
			record.node:SetPropertyTransitions(transitions)
			record.transitions = transitions
		end
		if propertiesChanged or timingChanged then
			record.node:SetProperties(properties)
			record.properties = properties
		end
		record.timing = timing
	end
	local sheet = Host.StyleSheet({
		Name = settings.name or "FacetTheme",
		Compose.keyed({
			from = ids,
			render = function(current: Compose.Readable<string>)
				local id = current:peek()
				local initial = definitions[id]
				local node = Host.StyleRule({
					Name = initial.id,
					Selector = initial.selector,
					Priority = initial.priority,
				})
				local record: MountedRule = { node = node }
				mounted[id] = record
				apply(record, initial, currentTiming :: TweenInfo)
				Compose.cleanup(function()
					if mounted[id] == record then
						mounted[id] = nil
					end
				end)
				return node
			end,
		}),
	})
	Compose.watch(function(use: Compose.Use)
		local package = read(packageOrReadable, use) or neutral
		local current = compiledRules(package, read(settings.theme, use))
		local timing = timingFor(package, use)
		currentTiming = timing
		local previousIds = ids:peek()
		local structureChanged = #previousIds ~= #current
		table.clear(definitions)
		for index, definition in current do
			definitions[definition.id] = definition
			if previousIds[index] ~= definition.id then
				structureChanged = true
			end
			local record = mounted[definition.id]
			if record then
				apply(record, definition, timing)
			end
		end
		if structureChanged then
			local nextIds = {}
			for _, definition in current do
				table.insert(nextIds, definition.id)
			end
			ids:set(nextIds)
		end
	end)
	return sheet
end

local function variantAsset(value: ThemeTypes.AssetSource?, state: ThemeTypes.SkinState): string?
	if type(value) == "string" then
		return value
	end
	if type(value) ~= "table" then
		return nil
	end
	if ((value :: unknown) :: { asset: unknown }).asset ~= nil then
		return (value :: { asset: string }).asset
	end
	local variants = value :: ThemeTypes.AssetVariants
	local selected = variants[state] or variants.default
	return if type(selected) == "table" then selected.asset else selected
end

type ImageLayer = {
	id: string,
	text: boolean?,
	textInsets: ThemeTypes.Insets?,
	Image: string,
	Size: UDim2,
	Position: UDim2,
	AnchorPoint: Vector2,
	BackgroundTransparency: number,
	BorderSizePixel: number,
	ZIndex: number,
	ScaleType: Enum.ScaleType,
	TileSize: UDim2,
	SliceCenter: Rect,
	SliceScale: number,
	ResampleMode: Enum.ResamplerMode,
}

type MountedImage = {
	node: ImageLabel,
	properties: ImageLayer,
	caption: Compose.Cell<ImageLayer>?,
	visible: boolean,
}

local shadowPresets: { [string]: ThemeTypes.Shadow } = {
	raised = { blurRadius = { offset = 14 }, transparency = 0.35, offset = { y = { offset = 3 } } },
	overlay = { blurRadius = { offset = 24 }, transparency = 0.45, offset = { y = { offset = 8 } } },
}

function themes.skin(
	runtime: Compose.Runtime,
	packageOrReadable: Engine.Value<ThemeTypes.ThemePackage>?,
	slot: string,
	options: ThemeTypes.SkinOptions?
): Frame
	local settings: ThemeTypes.SkinOptions = options or {}
	local types, Host = typesFor(settings), (runtime.constructors :: unknown) :: Engine.Host
	local D2, V2 = types.UDim2, types.Vector2
	if not Compose.isReadable(packageOrReadable) and type(packageOrReadable) ~= "function" then
		local package = read(packageOrReadable) or neutral
		local recipe = (package.chrome or {})[slot]
		if recipe == nil or recipe.kind == "native" or recipe.kind == "none" then
			local root = Host.Frame({
				Name = "Skin",
				Size = settings.Size or D2.fromScale(1, 1),
				AnchorPoint = settings.AnchorPoint or V2.new(0, 0),
				Position = settings.Position or D2.fromScale(0, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = settings.ZIndex or 0,
			})
			local declaredShadow = recipe and recipe.shadow
			local shadow: ThemeTypes.Shadow? = if type(declaredShadow) == "string"
				then (package.style.shadows or {})[declaredShadow] or shadowPresets[declaredShadow]
				else declaredShadow
			if type(declaredShadow) == "string" then
				assert(shadow ~= nil, "Facet theme unknown shadow preset")
			end
			if shadow then
				local function axis(value: ThemeTypes.ShadowAxis?): (number, number)
					local resolved: ThemeTypes.ShadowAxis = value or {}
					return resolved.scale or 0, resolved.offset or 0
				end
				local function pair(value: ThemeTypes.ShadowPair?): UDim2
					local resolved: ThemeTypes.ShadowPair = value or {}
					local x, xo = axis(resolved.x)
					local y, yo = axis(resolved.y)
					return D2.new(x, xo, y, yo)
				end
				runtime.mount(function()
					return Host.UIShadow({
						Name = "ChromeShadow",
						Color = color(types, shadow.color or { r = 0, g = 0, b = 0 }),
						Transparency = shadow.transparency or 0.5,
						ZIndex = shadow.zIndex or -1,
						Enabled = shadow.enabled ~= false,
						BlurRadius = types.UDim.new(axis(shadow.blurRadius)),
						Offset = pair(shadow.offset),
						Spread = pair(shadow.spread),
					})
				end, settings.target or root)
			end
			return decoration(runtime, types, settings.target, root) :: Frame
		end
	end
	type CompiledLayers = {
		package: ThemeTypes.ThemePackage,
		state: ThemeTypes.SkinState,
		direction: string?,
		layers: { ImageLayer },
	}
	local compiled: { CompiledLayers } = {}
	local function buildLayers(use: Compose.Use): { ImageLayer }
		local package = read(packageOrReadable, use) or neutral
		local recipe = (package.chrome or {})[slot]
		if recipe == nil or recipe.kind == "native" or recipe.kind == "none" then
			return {}
		end
		local state = (read(settings.state, use) or "default") :: ThemeTypes.SkinState
		local direction = if slot == "barCap" then read(settings.direction, use) or "ltr" else nil
		for _, cached in compiled do
			if cached.package == package and cached.state == state and cached.direction == direction then
				return cached.layers
			end
		end
		local output: { ImageLayer } = {}
		local function finish(): { ImageLayer }
			if deeplyFrozen(package, {}) then
				local snapshot: CompiledLayers =
					{ package = package, state = state :: ThemeTypes.SkinState, direction = direction, layers = output }
				table.insert(compiled, 1, snapshot)
				if #compiled > 2 then
					table.remove(compiled)
				end
			end
			return output
		end
		local function image(
			layer: ThemeTypes.SkinLayer,
			name: string,
			size: UDim2?,
			position: UDim2?,
			anchor: Vector2?,
			source: ThemeTypes.AssetSource?
		)
			local assetName = variantAsset(source or layer.asset, state :: ThemeTypes.SkinState)
			local asset = assetName and (package.assets or {})[assetName]
			if not asset then
				return
			end
			local value: ImageLayer = {
				id = name,
				text = layer.text,
				textInsets = layer.textInsets,
				Image = asset.content or asset.contentId or "",
				Size = size or D2.fromScale(1, 1),
				Position = position or D2.fromOffset(0, 0),
				AnchorPoint = anchor or V2.new(0, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = settings.ZIndex or 0,
				ScaleType = types.Enum.ScaleType.Stretch,
				TileSize = D2.fromScale(1, 1),
				SliceCenter = types.Rect.new(0, 0, 0, 0),
				SliceScale = 1,
				ResampleMode = types.Enum.ResamplerMode.Default,
			}
			if layer.kind == "tile" or layer.tile then
				local tile = layer.tileSize or { w = layer.tile or 32, h = layer.tile or 32 }
				value.ScaleType = types.Enum.ScaleType.Tile
				value.TileSize = D2.fromOffset(tile.w, tile.h)
			elseif asset.sliceCenter and layer.sliced ~= false then
				local slice = asset.sliceCenter
				value.ScaleType = types.Enum.ScaleType.Slice
				value.SliceCenter = types.Rect.new(slice.x0, slice.y0, slice.x1, slice.y1)
				value.SliceScale = asset.sliceScale or 1
			end
			if asset.resample == "pixelated" or package.identity.rendering == "pixel" then
				value.ResampleMode = types.Enum.ResamplerMode.Pixelated
			end
			table.insert(output, value)
		end
		if slot == "barCap" or slot == "barCenter" then
			local size = if type(recipe.size) == "table" then recipe.size else { w = 16, h = 16 }
			if slot == "barCenter" then
				image(recipe, "barCenter", D2.fromOffset(size.w, size.h), D2.fromScale(0.5, 0.5), V2.new(0.5, 0.5))
			else
				local vertical = direction == "ttb" or direction == "btt"
				local reverse = direction == "rtl" or direction == "btt"
				for _, endpoint in { "start", "end" } do
					local position = if (endpoint == "end") ~= reverse then 1 else 0
					image(
						recipe,
						"barCap-" .. endpoint,
						D2.fromOffset(size.w, size.h),
						D2.fromScale(if vertical then 0.5 else position, if vertical then position else 0.5),
						V2.new(0.5, 0.5),
						(if endpoint == "start" then recipe.startAsset else recipe.endAsset) or recipe.asset
					)
				end
			end
			return finish()
		end
		local definitions: { ThemeTypes.SkinLayer } = if recipe.kind == "layered"
			then recipe.layers or {}
			else { recipe }
		for index, layer in definitions do
			local name = slot .. tostring(index)
			if layer.kind == "corners" then
				local size = if type(layer.size) == "number" then layer.size else 16
				for corner, point in
					{
						topLeft = V2.new(0, 0),
						topRight = V2.new(1, 0),
						bottomLeft = V2.new(0, 1),
						bottomRight = V2.new(1, 1),
					} :: { [string]: Vector2 }
				do
					local asset = ({
						topLeft = layer.topLeft,
						topRight = layer.topRight,
						bottomLeft = layer.bottomLeft,
						bottomRight = layer.bottomRight,
					} :: { [string]: ThemeTypes.AssetSource? })[corner]
					if asset then
						image(
							layer,
							name .. corner,
							D2.fromOffset(size, size),
							D2.fromScale(point.X, point.Y),
							point,
							asset
						)
					end
				end
			elseif layer.kind == "edges" then
				local thickness, margin = layer.thickness or 8, layer.margin or 0
				for _, edge in (layer.sides or { "top", "right", "bottom", "left" }) :: { string } do
					local horizontal = edge == "top" or edge == "bottom"
					local endPoint = edge == "bottom" or edge == "right"
					local size = if horizontal
						then D2.new(1, -margin * 2, 0, thickness)
						else D2.new(0, thickness, 1, -margin * 2)
					local position = if horizontal
						then D2.new(0, margin, if endPoint then 1 else 0, 0)
						else D2.new(if endPoint then 1 else 0, 0, 0, margin)
					local anchor = if horizontal
						then V2.new(0, if endPoint then 1 else 0)
						else V2.new(if endPoint then 1 else 0, 0)
					image(layer, name .. edge, size, position, anchor)
				end
			elseif layer.kind == "plaque" then
				local size = if type(layer.size) == "table" then layer.size else { w = 120, h = 30 }
				local edge = layer.edge or "top"
				local horizontal = edge == "top" or edge == "bottom"
				local endPoint = edge == "bottom" or edge == "right"
				local overhang = layer.overhang or 0
				local position = if horizontal
					then D2.new(0.5, 0, if endPoint then 1 else 0, if endPoint then overhang else -overhang)
					else D2.new(if endPoint then 1 else 0, if endPoint then overhang else -overhang, 0.5, 0)
				local anchor = if horizontal
					then V2.new(0.5, if endPoint then 1 else 0)
					else V2.new(if endPoint then 1 else 0, 0.5)
				image(layer, name, D2.fromOffset(size.w, size.h), position, anchor)
			else
				image(layer, name)
			end
		end
		return finish()
	end
	local target = settings.target
	local function createImage(initial: ImageLayer): MountedImage
		local properties: Engine.ImageLabelNativeProps = {
			Name = initial.id,
			Visible = true,
			Image = initial.Image,
			Size = initial.Size,
			Position = initial.Position,
			AnchorPoint = initial.AnchorPoint,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = settings.ZIndex or 0,
			ScaleType = initial.ScaleType,
			TileSize = initial.TileSize,
			SliceCenter = initial.SliceCenter,
			SliceScale = initial.SliceScale,
			ResampleMode = initial.ResampleMode,
		}
		local captionSource: Compose.Cell<ImageLayer>?
		if settings.label then
			local current = Compose.cell(initial)
			captionSource = current
			table.insert(
				properties,
				Compose.show(function(use: Compose.Use)
					return use(current).text == true
				end, function()
					local padding: Engine.UIPaddingNativeProps = {
						PaddingLeft = function(use: Compose.Use)
							local inset: ThemeTypes.Insets = use(current).textInsets or {}
							return types.UDim.new(0, inset.left or 0)
						end,
						PaddingRight = function(use: Compose.Use)
							local inset: ThemeTypes.Insets = use(current).textInsets or {}
							return types.UDim.new(0, inset.right or 0)
						end,
						PaddingTop = function(use: Compose.Use)
							local inset: ThemeTypes.Insets = use(current).textInsets or {}
							return types.UDim.new(0, inset.top or 0)
						end,
						PaddingBottom = function(use: Compose.Use)
							local inset: ThemeTypes.Insets = use(current).textInsets or {}
							return types.UDim.new(0, inset.bottom or 0)
						end,
					}
					local label = Host.TextLabel({
						Name = "PlaqueCaption",
						Text = settings.label,
						Size = D2.fromScale(1, 1),
						BackgroundTransparency = 1,
						ZIndex = 1,
						TextXAlignment = types.Enum.TextXAlignment.Center,
						Host.UIPadding(padding),
					})
					label:AddTag("facet-skin-caption-text")
					return label
				end)
			)
		end
		return { node = Host.ImageLabel(properties), properties = initial, caption = captionSource, visible = true }
	end
	local function applyImage(record: MountedImage, value: ImageLayer?, visible: boolean)
		local node, previous = record.node, record.properties
		if record.visible ~= visible then
			node.Visible = visible
			record.visible = visible
		end
		if value then
			if value.id ~= previous.id then
				node.Name = value.id
			end
			if value.Image ~= previous.Image then
				node.Image = value.Image
			end
			if value.Size ~= previous.Size then
				node.Size = value.Size
			end
			if value.Position ~= previous.Position then
				node.Position = value.Position
			end
			if value.AnchorPoint ~= previous.AnchorPoint then
				node.AnchorPoint = value.AnchorPoint
			end
			if value.ScaleType ~= previous.ScaleType then
				node.ScaleType = value.ScaleType
			end
			if value.TileSize ~= previous.TileSize then
				node.TileSize = value.TileSize
			end
			if value.SliceCenter ~= previous.SliceCenter then
				node.SliceCenter = value.SliceCenter
			end
			if value.SliceScale ~= previous.SliceScale then
				node.SliceScale = value.SliceScale
			end
			if value.ResampleMode ~= previous.ResampleMode then
				node.ResampleMode = value.ResampleMode
			end
			local caption = record.caption
			if caption and (value.text ~= previous.text or value.textInsets ~= previous.textInsets) then
				caption:set(value)
			end
			record.properties = value
		end
	end
	local activeLayers: { ImageLayer } = {}
	local slots: Compose.Cell<{ number }> = Compose.cell({})
	local mounted: { [number]: MountedImage } = {}
	local root = Host.Frame({
		Name = "Skin",
		Size = settings.Size or D2.fromScale(1, 1),
		AnchorPoint = settings.AnchorPoint or V2.new(0, 0),
		Position = settings.Position or D2.fromScale(0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = settings.ZIndex or 0,
		Compose.keyed({
			from = slots,
			render = function(current: Compose.Readable<number>)
				local index = current:peek()
				local record = createImage(activeLayers[index])
				mounted[index] = record
				Compose.cleanup(function()
					mounted[index] = nil
				end)
				return record.node
			end,
		}),
	})
	Compose.watch(function(use: Compose.Use)
		local active = buildLayers(use)
		activeLayers = active
		local previousSlots = slots:peek()
		local count = math.max(#active, math.min(#previousSlots, 16))
		if count ~= #previousSlots then
			local nextSlots: { number } = {}
			for index = 1, count do
				nextSlots[index] = index
			end
			slots:set(nextSlots)
		end
		for index, record in mounted do
			applyImage(record, active[index], active[index] ~= nil)
		end
		if target then
			local plaque = false
			if #active > 0 then
				target:AddTag("facet-skinned")
			else
				target:RemoveTag("facet-skinned")
			end
			for _, layer in active do
				if layer.text then
					plaque = true
				end
			end
			if plaque then
				target:AddTag("facet-skin-caption")
			else
				target:RemoveTag("facet-skin-caption")
			end
		end
	end)
	local shadow = Compose.formula(function(use: Compose.Use)
		local package = read(packageOrReadable, use) or neutral
		local recipe = (package.chrome or {})[slot]
		local value = if recipe then recipe.shadow else nil
		if type(value) == "string" then
			value = (package.style.shadows or {})[value] or shadowPresets[value]
			assert(value ~= nil, "Facet theme unknown shadow preset")
		end
		return value
	end)
	local previousShadow: ThemeTypes.Shadow?
	local retainedShadow = Compose.formula(function(use: Compose.Use): ThemeTypes.Shadow?
		local current = use(shadow)
		if current then
			previousShadow = current :: ThemeTypes.Shadow
		end
		return previousShadow
	end)
	runtime.mountFragment(function()
		return {
			Compose.show(retainedShadow, function()
				local function axis(value: ThemeTypes.ShadowAxis?): (number, number)
					local resolved: ThemeTypes.ShadowAxis = value or {}
					return resolved.scale or 0, resolved.offset or 0
				end
				local function pair(value: ThemeTypes.ShadowPair?): UDim2
					local resolved: ThemeTypes.ShadowPair = value or {}
					local x, xo = axis(resolved.x)
					local y, yo = axis(resolved.y)
					return D2.new(x, xo, y, yo)
				end
				local properties: Engine.UIShadowNativeProps = {
					Name = "ChromeShadow",
					Color = function(use: Compose.Use)
						return color(
								types,
								(use(retainedShadow) :: ThemeTypes.Shadow).color or { r = 0, g = 0, b = 0 }
							) :: Color3
					end,
					Transparency = function(use: Compose.Use)
						return (use(retainedShadow) :: ThemeTypes.Shadow).transparency or 0.5
					end,
					ZIndex = function(use: Compose.Use)
						return (use(retainedShadow) :: ThemeTypes.Shadow).zIndex or -1
					end,
					Enabled = function(use: Compose.Use)
						local current = use(shadow)
						return current ~= nil and (current :: ThemeTypes.Shadow).enabled ~= false
					end,
					BlurRadius = function(use: Compose.Use)
						return types.UDim.new(axis((use(retainedShadow) :: ThemeTypes.Shadow).blurRadius))
					end,
					Offset = function(use: Compose.Use)
						return pair((use(retainedShadow) :: ThemeTypes.Shadow).offset)
					end,
					Spread = function(use: Compose.Use)
						return pair((use(retainedShadow) :: ThemeTypes.Shadow).spread)
					end,
				}
				return Host.UIShadow(properties)
			end),
		}
	end, settings.target or root)
	return decoration(runtime, types, settings.target, root) :: Frame
end

local surface: ThemeTypes.Themes = themes
return surface
