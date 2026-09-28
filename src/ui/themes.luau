--!strict
local segmentMetrics = require("./segment_metrics")
local decoration = require("./native_decoration")
local ComposeTypes = require("../vendor/compose/core")
local icons = require("./icons")
local ThemeTypes = require("./theme_types")
local Engine = require("./engine_types")
local adaptive = require("./adaptive")
local motionLevels = require("./motion")
local preferredInput = require("./preferred_input")
local themeDistance = require("./theme_distance")
export type ThemePackage = ThemeTypes.ThemePackage
export type ThemeDefinition = ThemeTypes.ThemeDefinition
export type ThemeOptions = ThemeTypes.ThemeOptions
export type SkinOptions = ThemeTypes.SkinOptions
export type Themes = ThemeTypes.Themes

local themes = {}
local EASING_STYLES: { [string]: boolean } = {
	Linear = true,
	Sine = true,
	Back = true,
	Quad = true,
	Quart = true,
	Quint = true,
	Bounce = true,
	Elastic = true,
	Exponential = true,
	Circular = true,
	Cubic = true,
}
local function contrast(first: Color3, second: Color3): number
	local function luminance(value: Color3): number
		local function linear(channel: number): number
			return if channel <= 0.04045 then channel / 12.92 else ((channel + 0.055) / 1.055) ^ 2.4
		end
		return 0.2126 * linear(value.R) + 0.7152 * linear(value.G) + 0.0722 * linear(value.B)
	end
	local a, b = luminance(first), luminance(second)
	return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05)
end
themes.SCHEMA = "facet-theme/2"
themes.TYPE_ROLES = table.freeze({ "caption", "label", "body", "heading", "title", "control", "strong", "numeral" })
themes.REQUIRED_TYPE_ROLES = themes.TYPE_ROLES
local AVATAR_BACKGROUNDS: { [string]: string } = table.freeze({
	surface = "content",
	surfaceStrong = "content",
	control = "content",
	contentStrong = "surface",
	accent = "onAccent",
	success = "onSuccess",
	warning = "onWarning",
	danger = "onDanger",
})

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

local skinStates = { default = true, hover = true, pressed = true, selected = true, disabled = true }
local function stateMap(value: unknown): boolean
	if type(value) ~= "table" or next(value :: { [unknown]: unknown }) == nil then
		return false
	end
	for key in value :: { [unknown]: unknown } do
		if not skinStates[key :: string] then
			return false
		end
	end
	return true
end

local function merge<T>(base: T, overrides: unknown): T
	local out = (copy(base) :: unknown) :: { [unknown]: unknown }
	for key, value in (overrides or {}) :: { [unknown]: unknown } do
		if key ~= "base" then
			out[key] = if type(value) == "table"
					and type(out[key]) == "table"
					and #(value :: { unknown }) == 0
					and not stateMap(value)
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
			{
				name = "Light",
				colors = {
					surface = rgb(242, 244, 248),
					surfaceStrong = rgb(255, 255, 255),
					content = rgb(28, 32, 41),
					contentStrong = rgb(12, 14, 20),
					accent = rgb(44, 98, 210),
					onAccent = rgb(255, 255, 255),
					danger = rgb(185, 28, 28),
					onDanger = rgb(255, 255, 255),
					success = rgb(21, 107, 58),
					onSuccess = rgb(255, 255, 255),
					warning = rgb(224, 166, 32),
					onWarning = rgb(28, 22, 6),
				},
				extra = {
					control = rgb(228, 231, 238),
					controlHover = rgb(219, 223, 233),
					controlPressed = rgb(206, 211, 224),
					controlSelected = rgb(205, 219, 245),
					contentSecondary = rgb(90, 98, 114),
					hairline = rgb(10, 12, 18),
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
		motion = {
			fast = 0.12,
			normal = 0.2,
			press = 0.08,
			hover = 0.15,
			reducedFade = 0.15,
			revealFadeShare = 0.5,
			presentFadeIn = 0.6,
			presentFadeOut = 0.5,
			unfoldStart = 0.25,
			restLimit = 0.25,
			popover = { enter = 0.15, exit = 0.1 },
			dialog = { enter = 0.2, exit = 0.15 },
			reveal = { enter = 0.25, exit = 0.2 },
			sheet = { enter = 0.3, exit = 0.2 },
			toast = { enter = 0.2, exit = 0.2 },
			radial = { enter = 0.2, exit = 0.12, slot = 0.16 },
			durations = {
				tabFade = 0.2,
				pageTurn = 0.3,
				popoverSheetExit = 0.2,
				rowDeparture = 0.24,
				cardFade = 0.15,
				regionPop = 0.15,
				fieldReject = 0.24,
				buttonPop = 0.45,
				scrollReveal = 0.25,
				focusPulse = 1,
				busyLoop = 1,
				progressLoop = 1,
				spinnerLoop = 1.4,
				glide = 0.22,
				trailDelay = 0.3,
				trailSettle = 0.35,
			},
			springs = {
				snappy = { period = 0.2, damping = 1 },
				quick = { period = 0.18, damping = 1 },
				control = { period = 0.25, damping = 1 },
				move = { period = 0.3, damping = 1 },
				sheet = { period = 0.4, damping = 1 },
			},
			materialize = {
				anchored = 0.9,
				menu = 0.96,
				modal = 0.94,
				branch = 0.3,
				lift = 1.04,
				radialSpread = 0.2,
				popOvershoot = 0.25,
				popDecay = 3,
			},
			distances = { menuSlide = 32, parallax = 0.3, dim = 0.1 },
			easing = { present = "outCubic", fade = "outQuad" },
			styles = { paint = "Quad", scroll = "Quad", page = "Cubic", fling = "Back", pulse = "Sine" },
			fling = { friction = 3, maxSpeed = 4000, projection = 0.08 },
		},
		iconSizes = { small = 16, medium = 20, large = 24 },
		controls = {
			progress = { trackHeight = 6, circularSize = 32, circularThickness = 3, spinnerDotSize = 4 },
			image = { defaultSize = 48 },
			alert = { maxWidth = 560 },
			popup = { panelWidth = 360 },
			dialog = { wideWidth = 800 },
			snackbar = { maxWidth = 480 },
			radial = { narrow = 48, regular = 64, wide = 88 },
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
			weight = if role == "heading"
					or role == "title"
					or role == "numeral"
				then "Bold"
				elseif role == "strong" then "SemiBold"
				else "Regular",
			style = "Normal",
		},
		lineHeight = 1.2,
	}
end

local function read<T>(source: Engine.Value<T>, use: ComposeTypes.Use?): T
	if type(source) == "function" then
		return (source :: (ComposeTypes.Use) -> T)(use or function<U>(value: ComposeTypes.Readable<U>): U
			return value:peek()
		end)
	end
	if type(source) == "table" and type(source.peek) == "function" then
		local readable = source :: ComposeTypes.Readable<T>
		return if use then use(readable) else readable:peek()
	end
	return source :: T
end

function themes.neutralPackage(): ThemeTypes.ThemePackage
	return copy(neutral)
end

themes.forDistance = themeDistance(neutral)

local function frozen<T>(value: T): T
	if type(value) ~= "table" or table.isfrozen(value) then
		return value
	end
	for _, child in (value :: unknown) :: { [unknown]: unknown } do
		frozen(child)
	end
	return (table.freeze(value) :: unknown) :: T
end

local derivedTypeRoles: { [string]: { base: string, weight: string } } = {
	strong = { base = "body", weight = "SemiBold" },
	numeral = { base = "control", weight = "Bold" },
}

local shadowPresets: { [string]: ThemeTypes.Shadow } = {
	raised = { blurRadius = { offset = 14 }, transparency = 0.35, offset = { y = { offset = 3 } } },
	overlay = { blurRadius = { offset = 24 }, transparency = 0.45, offset = { y = { offset = 8 } } },
}

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
	local base = copy(definition.base or neutral)
	if type(base.style) == "table" and type(base.style.themes) == "table" and #base.style.themes > 1 then
		base.style.themes = { base.style.themes[1] }
	end
	local package = merge(base, definition)
	if type(package.identity) ~= "table" or type(package.identity.id) ~= "string" then
		table.insert(errors, { field = "identity.id", message = "A theme package needs an identity" })
	end
	if type(package.style) ~= "table" or type(package.style.themes) ~= "table" or #package.style.themes == 0 then
		table.insert(errors, { field = "style.themes", message = "A theme package needs at least one palette" })
	end
	if #errors > 0 then
		return nil, { ok = false, errors = errors, missing = {}, contrast = {} }
	end
	local typography = (package.metrics.typography :: unknown) :: { [string]: unknown }
	local definedMetrics = (definition :: { metrics: unknown? }).metrics
	local authored: { [string]: unknown } = if type(definedMetrics) == "table"
			and type((definedMetrics :: { typography: unknown? }).typography) == "table"
		then (definedMetrics :: { typography: { [string]: unknown } }).typography
		else {}
	for role, derivation in derivedTypeRoles do
		local source = typography[derivation.base]
		if authored[role] == nil and authored[derivation.base] ~= nil and type(source) == "table" then
			local entry = source :: { size: unknown, lineHeight: unknown, font: unknown }
			if type(entry.font) == "table" then
				local face = entry.font :: ThemeTypes.FontSpec
				typography[role] = {
					size = entry.size,
					lineHeight = entry.lineHeight,
					font = { family = face.family, weight = derivation.weight, style = face.style },
				}
			end
		end
	end
	for _, role in themes.TYPE_ROLES do
		local entry = typography[role]
		local size = if type(entry) == "table" then (entry :: { size: unknown }).size else nil
		if entry ~= nil and (type(size) ~= "number" or size <= 0) then
			table.insert(
				errors,
				{ field = "metrics.typography." .. role, message = "Type roles require a positive size" }
			)
		end
	end
	local space = (package.metrics :: { space: unknown }).space
	if type(space) ~= "table" then
		table.insert(errors, { field = "metrics.space", message = "Spacing steps must be a table of pixel sizes" })
	else
		for step, pixels in space :: { [unknown]: unknown } do
			if type(step) ~= "string" or type(pixels) ~= "number" or pixels < 0 then
				table.insert(errors, {
					field = "metrics.space." .. tostring(step),
					message = "Spacing steps require a pixel size of 0 or more",
				})
			end
		end
	end
	local controlSizes = (package.metrics :: { controlSizes: unknown }).controlSizes
	local xsmall = if type(controlSizes) == "table" then (controlSizes :: { [string]: unknown }).xsmall else nil
	if xsmall ~= nil then
		for _, field in { "height", "paddingX", "iconSize" } do
			local value = if type(xsmall) == "table" then (xsmall :: { [string]: unknown })[field] else nil
			if type(value) ~= "number" or (value :: number) < 0 then
				table.insert(errors, {
					field = "metrics.controlSizes.xsmall." .. field,
					message = "The xsmall rung needs a height, a paddingX and an iconSize of 0 or more",
				})
			end
		end
	end
	local targets = (package.metrics :: { targetSizes: unknown }).targetSizes
	local sizes: { [string]: unknown } = if type(targets) == "table" then targets :: { [string]: unknown } else {}
	local pointer, minimum = sizes.pointer, sizes.minimum
	if
		pointer ~= nil
		and (
			type(pointer) ~= "number"
			or (pointer :: number) < 24
			or (type(minimum) == "number" and (pointer :: number) > (minimum :: number))
		)
	then
		table.insert(errors, {
			field = "metrics.targetSizes.pointer",
			message = "targetSizes.pointer must be from 24 to targetSizes.minimum",
		})
	end
	local motion = (package.metrics :: { motion: unknown }).motion
	if type(motion) ~= "table" then
		table.insert(errors, { field = "metrics.motion", message = "Motion tokens must be a table" })
	else
		local function issue(path: string, message: string)
			table.insert(errors, { field = "metrics.motion." .. path, message = message })
		end
		local function number(path: string, value: unknown, low: number, high: number, open: boolean?)
			if
				type(value) ~= "number"
				or (value :: number) > high
				or (value :: number) < low
				or (open == true and value == low)
			then
				issue(path, `must be a number from {low} to {high}{if open then ", above " .. low else ""}`)
			end
		end
		local tokens = motion :: { [string]: unknown }
		local function each(group: string, check: (string, unknown) -> ())
			local entries = tokens[group]
			if entries == nil then
				return
			end
			if type(entries) ~= "table" then
				issue(group, "must be a table")
				return
			end
			for key, value in entries :: { [unknown]: unknown } do
				check(group .. "." .. tostring(key), value)
			end
		end
		for _, key in { "fast", "normal", "press", "hover" } do
			if tokens[key] ~= nil then
				number(key, tokens[key], 0, 10)
			end
		end
		if tokens.reducedFade ~= nil then
			number("reducedFade", tokens.reducedFade, 0, 10, true)
		end
		for _, key in { "revealFadeShare", "unfoldStart" } do
			if tokens[key] ~= nil then
				number(key, tokens[key], 0, 1)
			end
		end
		if tokens.restLimit ~= nil then
			number("restLimit", tokens.restLimit, 0, 1)
		end
		for _, key in { "presentFadeIn", "presentFadeOut" } do
			if tokens[key] ~= nil then
				number(key, tokens[key], 0, 1, true)
			end
		end
		for _, role in { "popover", "dialog", "reveal", "sheet", "toast", "radial" } do
			each(role, function(path: string, value: unknown)
				number(path, value, 0, 10)
			end)
		end
		each("durations", function(path: string, value: unknown)
			number(path, value, 0, 10)
		end)
		each("springs", function(path: string, value: unknown)
			if type(value) ~= "table" then
				issue(path, "must be { period, damping }")
				return
			end
			local spring = value :: { period: unknown, damping: unknown }
			number(path .. ".period", spring.period, 0, 10, true)
			number(path .. ".damping", spring.damping, 0, 10, true)
		end)
		each("materialize", function(path: string, value: unknown)
			number(path, value, 0, 10, true)
		end)
		each("distances", function(path: string, value: unknown)
			number(path, value, 0, 10000)
		end)
		each("fling", function(path: string, value: unknown)
			number(path, value, 0, 100000, path ~= "fling.projection")
		end)
		each("easing", function(path: string, value: unknown)
			if type(value) ~= "string" or (ComposeTypes :: any).easing[value] == nil then
				issue(path, "must name a Compose.easing function")
			end
		end)
		each("styles", function(path: string, value: unknown)
			if type(value) ~= "string" or EASING_STYLES[value :: string] == nil then
				issue(path, "must name an Enum.EasingStyle item")
			end
		end)
	end
	local chrome: { [string]: ThemeTypes.SkinLayer } = package.chrome or {}
	local shadows: { [string]: ThemeTypes.Shadow } = package.style.shadows or {}
	local function checkLinks(value: unknown, path: string)
		if type(value) ~= "table" then
			return
		end
		local link = value :: { rotation: unknown, tint: unknown }
		if link.rotation ~= nil and link.rotation ~= 0 and link.rotation ~= 180 then
			table.insert(errors, { field = path .. ".rotation", message = "Art rotation must be 0 or 180" })
		end
		local tint = link.tint :: { [string]: unknown }
		if tint ~= nil then
			for _, channel in { "r", "g", "b" } do
				local amount = if type(tint) == "table" then tint[channel] else nil
				if type(amount) ~= "number" or (amount :: number) < 0 or (amount :: number) > 1 then
					table.insert(errors, { field = path .. ".tint", message = "Art tint needs r, g and b from 0 to 1" })
					break
				end
			end
		end
		for key, child in value :: { [unknown]: unknown } do
			checkLinks(child, path .. "." .. tostring(key))
		end
	end
	for slot, recipe in chrome do
		local shadow = recipe.shadow
		if type(shadow) == "string" and shadows[shadow] == nil and shadowPresets[shadow] == nil then
			table.insert(
				errors,
				{ field = "chrome." .. slot .. ".shadow", message = "Unknown shadow preset " .. shadow }
			)
		end
		checkLinks(recipe, "chrome." .. slot)
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
			local extra = (
				merge(neutral.style.themes[1].extra or {}, palette.extra or {}) :: unknown
			) :: { [string]: ThemeTypes.RGB? }
			local selectedFill = extra.controlSelected
			local selectedLabel = extra.onSelected or colors.content
			if type(selectedFill) == "table" and type(selectedLabel) == "table" then
				local first, second = luminance(selectedLabel), luminance(selectedFill)
				local ratio = (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05)
				table.insert(contrast, { pair = "onSelected/controlSelected", ratio = ratio, ok = ratio >= 4.5 })
				if ratio < 4.5 then
					table.insert(
						errors,
						{ field = "style." .. palette.name, message = "onSelected contrast is below 4.5:1" }
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
	local assets: { [string]: ThemeTypes.Asset } = package.assets or {}
	local entry: unknown = (package.icons or {})[name] or icons.ART[name]
	local regular = string.match(name, "^(.+)%.fill$")
	if entry == nil and regular then
		return themes.resolveIcon(package, regular, state)
	end
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
	local icon = entry :: ThemeTypes.IconAsset
	local asset: ThemeTypes.Asset? = if icon.asset then assets[icon.asset] else icon
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
	local spec = value :: ThemeTypes.FontSpec
	local family = spec.family or "BuilderSans"
	if not string.find(family, "://", 1, true) then
		family = "rbxasset://fonts/families/" .. family .. ".json"
	end
	return types.Font.new(
		family,
		((types.Enum.FontWeight :: unknown) :: { [string]: Enum.FontWeight })[spec.weight or "Regular"],
		((types.Enum.FontStyle :: unknown) :: { [string]: Enum.FontStyle })[spec.style or "Normal"]
	)
end

local SEGMENT_INSET = segmentMetrics.inset

type NativeRule = { id: string, selector: string, properties: ThemeTypes.RuleProperties, priority: number }
local function rulesFor(package: ThemeTypes.ThemePackage, selected: string?, types: Engine.RobloxTypes): { NativeRule }
	local palette = paletteFor(package, selected)
	local colors = merge(neutral.style.themes[1].colors, palette.colors)
	local extra = merge(neutral.style.themes[1].extra :: ThemeTypes.PaletteExtra, palette.extra)
	local resolvedColors: { [string]: Color3? }, typefaces: { [string]: Font? } = {}, {}
	local fallbacks: { [string]: string } = {
		selection = "accent",
		onSelection = "onAccent",
		inverseSurface = "contentStrong",
		onInverse = "surface",
		tableHeader = "control",
		tableRow = "control",
		tableRowAlternate = "controlHover",
	}
	local function source(role: string): ThemeTypes.RGB?
		local value = (colors[role] or extra[role]) :: ThemeTypes.RGB?
		local fallback = fallbacks[role]
		if value == nil and fallback then
			value = (colors[fallback] or extra[fallback]) :: ThemeTypes.RGB?
		end
		return value
	end
	local function c(role: string): Color3?
		if resolvedColors[role] == nil then
			local value = color(types, source(role))
			if value == nil and role == "voice" then
				value = (c("warning") :: Color3):Lerp(c("danger") :: Color3, 0.5)
			end
			resolvedColors[role] = value
		end
		return resolvedColors[role]
	end
	local function f(value: ThemeTypes.FontSpec | Font): Font
		if typeof(value) == "Font" then
			return value
		end
		local spec = value :: ThemeTypes.FontSpec
		local key = (spec.family or "BuilderSans")
			.. ":"
			.. (spec.weight or "Regular")
			.. ":"
			.. (spec.style or "Normal")
		if typefaces[key] == nil then
			typefaces[key] = font(types, value)
		end
		return typefaces[key] :: Font
	end
	local rules: { NativeRule } = {}
	local occurrences: { [string]: number } = {}
	local function add(selector: string, properties: ThemeTypes.RuleProperties)
		local occurrence = (occurrences[selector] or 0) + 1
		occurrences[selector] = occurrence
		table.insert(rules, {
			id = selector .. ":" .. tostring(occurrence),
			selector = selector,
			properties = properties,
			priority = #rules * 10,
		})
	end
	local function rule(selector: string, properties: ThemeTypes.RuleProperties, authored: boolean?)
		if string.sub(selector, -10) == "::UIStroke" then
			properties = table.clone(properties)
			properties.ApplyStrokeMode = properties.ApplyStrokeMode or types.Enum.ApplyStrokeMode.Border
			if not authored and properties.ApplyStrokeMode == types.Enum.ApplyStrokeMode.Border then
				properties.BorderStrokePosition = properties.BorderStrokePosition
					or types.Enum.BorderStrokePosition.Inner
			end
		end
		if string.sub(selector, -10) == "::UIStroke" then
			add(string.sub(selector, 1, -11) .. " > .facet-fade-stroke", properties)
		end
		add(selector, properties)
		if string.sub(selector, -11) == "::UIPadding" then
			add(string.sub(selector, 1, -12) .. " > UIPadding", properties)
		end
	end
	add(".facet-fade-stroke", { Enabled = false, Transparency = 1 })
	rule("ScrollingFrame", {
		VerticalScrollBarInset = types.Enum.ScrollBarInset.Always,
		HorizontalScrollBarInset = types.Enum.ScrollBarInset.ScrollBar,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = c("contentSecondary"),
		ScrollBarImageTransparency = 0.4,
	})
	rule(".facet-layout", { BackgroundTransparency = 1 })
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
			TextColor3 = if role == "caption" then c("contentSecondary") else nil,
		})
	end
	rule(".facet-validation", { TextColor3 = c("danger"), TextSize = package.metrics.typography.caption.size })
	rule(".facet-secondary", { TextColor3 = c("contentSecondary") })
	rule("TextBox.facet-text", { PlaceholderColor3 = c("contentSecondary") })
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
		local radius = if role == "panel"
				or role == "sheet"
				or role == "menu"
			then package.metrics.radii.panel
			else package.metrics.radii.control
		rule(".facet-" .. role .. "::UICorner", { CornerRadius = types.UDim.new(0, radius) })
	end
	rule(".facet-button", {
		TextColor3 = c("content"),
		FontFace = f(package.metrics.typography.control.font),
		TextSize = package.metrics.typography.control.size,
	})
	for _, role in themes.TYPE_ROLES do
		local typography = package.metrics.typography[role] or neutral.metrics.typography[role]
		rule(".facet-button.facet-type-" .. role, { FontFace = f(typography.font), TextSize = typography.size })
	end
	for _, role in
		{ "toggle", "toggle-indicator", "slider-rail", "slider-track", "chip", "shortcut-hint", "text-input" }
	do
		rule(".facet-" .. role, { BackgroundColor3 = c("control"), BackgroundTransparency = 0, BorderSizePixel = 0 })
	end
	rule(".facet-chip::UICorner", { CornerRadius = types.UDim.new(0, package.metrics.radii.pill) })
	for _, role in { "toggle-mark", "slider-fill", "slider-thumb", "selection-indicator" } do
		local ink = if role == "slider-fill" or role == "selection-indicator" then "selection" else "accent"
		rule(".facet-" .. role, { BackgroundColor3 = c(ink), BackgroundTransparency = 0, BorderSizePixel = 0 })
	end
	for role, slot in
		{
			button = "control",
			field = "field",
			badge = "badge",
			panel = "panel",
			["control.facet-skinned"] = "control",
		} :: { [string]: string }
	do
		local chrome = package.chrome
		local recipe = if chrome then chrome[slot] else nil
		local inset: ThemeTypes.Insets = if recipe then recipe.contentInsets or {} else {}
		local horizontal = if role == "button" then 12 elseif role == "badge" then 8 else 0
		local vertical = if role == "badge" then 3 else 0
		local function side(face: number, carve: number?): UDim
			return types.UDim.new(0, if role == "badge" then math.max(face, carve or 0) else face + (carve or 0))
		end
		rule(".facet-" .. role .. "::UIPadding", {
			PaddingLeft = side(horizontal, inset.left),
			PaddingRight = side(horizontal, inset.right),
			PaddingTop = side(vertical, inset.top),
			PaddingBottom = side(vertical, inset.bottom),
		})
	end
	local buttonInsets: ThemeTypes.Insets = if ((package.chrome or {}) :: { [string]: ThemeTypes.SkinLayer }).control
		then ((package.chrome or {}) :: { [string]: ThemeTypes.SkinLayer }).control.contentInsets or {}
		else {}
	for _, pair in
		{ { "tablehead", "tableHeader" }, { "tablerow", "tableRow" }, { "tablerow-alternate", "tableRowAlternate" } }
	do
		rule(".facet-" .. pair[1], { BackgroundColor3 = c(pair[2]), BackgroundTransparency = 0, BorderSizePixel = 0 })
	end
	for _, band in { "tablehead", "tablerow" } do
		rule(".facet-" .. band .. "::UICorner", { CornerRadius = types.UDim.new(0, package.metrics.radii.control) })
	end
	for _, row in { "tablerow", "row-action" } do
		rule(".facet-" .. row .. "::UIStroke", {
			Color = c("surface"),
			Thickness = 1,
			Transparency = 0,
			BorderStrokePosition = types.Enum.BorderStrokePosition.Inner,
		})
	end
	rule(".facet-tableheading", { BackgroundTransparency = 1 })
	local function rungMetric(rung: string, field: string): number
		local authored = (package.metrics.controlSizes or {})[rung]
		if authored and type(authored[field]) == "number" then
			return authored[field]
		end
		local fallback = neutral.metrics.controlSizes[rung]
		if fallback then
			return fallback[field]
		end
		return math.max(0, 2 * rungMetric("compact", field) - rungMetric("regular", field))
	end
	for _, rung in { "xsmall", "compact", "regular", "large" } do
		local paddingX = rungMetric(rung, "paddingX")
		rule(".facet-button.facet-size-" .. rung .. "::UIPadding", {
			PaddingLeft = types.UDim.new(0, paddingX + (buttonInsets.left or 0)),
			PaddingRight = types.UDim.new(0, paddingX + (buttonInsets.right or 0)),
		})
	end
	rule(".facet-button-tight::UIPadding", {
		PaddingLeft = types.UDim.new(0, buttonInsets.left or 0),
		PaddingRight = types.UDim.new(0, buttonInsets.right or 0),
	})
	local cellLeft, cellRight = 12 + (buttonInsets.left or 0), 12 + (buttonInsets.right or 0)
	for _, cell in { "tablevalue", "tableheading" } do
		rule(".facet-" .. cell .. "::UIPadding", {
			PaddingLeft = types.UDim.new(0, cellLeft),
			PaddingRight = types.UDim.new(0, cellRight),
		})
	end
	rule(".facet-tablecellinset", {
		Position = types.UDim2.fromOffset(cellLeft, 0),
		Size = types.UDim2.new(1, -(cellLeft + cellRight), 1, 0),
	})
	rule(".facet-button-glyph::UIPadding", {
		PaddingLeft = types.UDim.new(0, buttonInsets.left or 0),
		PaddingRight = types.UDim.new(0, buttonInsets.right or 0),
	})
	rule(".facet-button-glyph.facet-appearance-utility::UIPadding", {
		PaddingLeft = types.UDim.new(0, 0),
		PaddingRight = types.UDim.new(0, 0),
		PaddingTop = types.UDim.new(0, 0),
		PaddingBottom = types.UDim.new(0, 0),
	})
	rule(".facet-disclosure::UIPadding", { PaddingRight = types.UDim.new(0, 32 + (buttonInsets.right or 0)) })
	rule(".facet-button-described::UIPadding", {
		PaddingTop = types.UDim.new(0, 10 + (buttonInsets.top or 0)),
		PaddingBottom = types.UDim.new(0, 10 + (buttonInsets.bottom or 0)),
	})
	rule(".facet-toggle-row::UIPadding", { PaddingLeft = types.UDim.new(0, 0), PaddingRight = types.UDim.new(0, 0) })
	rule(".facet-toggle-settings::UIPadding", {
		PaddingLeft = types.UDim.new(0, 12 + (buttonInsets.left or 0)),
		PaddingRight = types.UDim.new(0, 12 + (buttonInsets.right or 0)),
	})
	rule(".facet-slider-settings::UIPadding", {
		PaddingLeft = types.UDim.new(0, 12 + (buttonInsets.left or 0)),
		PaddingRight = types.UDim.new(0, 12 + (buttonInsets.right or 0)),
	})
	local space: { [string]: number } = package.metrics.space or neutral.metrics.space
	local rowGap = space.xs or neutral.metrics.space.xs
	rule(".facet-calendar-choice::UIPadding", {
		PaddingLeft = types.UDim.new(0, rowGap),
		PaddingRight = types.UDim.new(0, rowGap),
	})
	for _, rung in { "", "xsmall", "compact", "regular", "large" } do
		local step = if rung == "" then "regular" else rung
		local paddingX = rungMetric(step, "paddingX")
		local paddingY = math.max(0, (rungMetric(step, "height") - rungMetric(step, "iconSize") - rowGap) // 2)
		rule(".facet-list-row" .. (if rung == "" then "" else ".facet-size-" .. rung) .. "::UIPadding", {
			PaddingLeft = types.UDim.new(0, paddingX + (buttonInsets.left or 0)),
			PaddingRight = types.UDim.new(0, paddingX + (buttonInsets.right or 0)),
			PaddingTop = types.UDim.new(0, math.max(paddingY, buttonInsets.top or 0)),
			PaddingBottom = types.UDim.new(0, math.max(paddingY, buttonInsets.bottom or 0)),
		})
	end
	rule(".facet-menu-dense::UIPadding", { PaddingTop = types.UDim.new(0, 0), PaddingBottom = types.UDim.new(0, 0) })
	rule(".facet-busy::UIPadding", { PaddingRight = types.UDim.new(0, 32 + (buttonInsets.right or 0)) })
	rule(".facet-shape-circle::UIPadding", {
		PaddingLeft = types.UDim.new(0, 0),
		PaddingRight = types.UDim.new(0, 0),
		PaddingTop = types.UDim.new(0, 0),
		PaddingBottom = types.UDim.new(0, 0),
	})
	rule(".facet-button-media::UIPadding", {
		PaddingLeft = types.UDim.new(0, buttonInsets.left or 0),
		PaddingRight = types.UDim.new(0, buttonInsets.right or 0),
		PaddingTop = types.UDim.new(0, buttonInsets.top or 0),
		PaddingBottom = types.UDim.new(0, 10 + (buttonInsets.bottom or 0)),
	})
	rule(".facet-button-media-body::UIPadding", {
		PaddingLeft = types.UDim.new(0, 12),
		PaddingRight = types.UDim.new(0, 12),
	})
	rule(".facet-button-captioned", { TextTransparency = 1 })
	rule(".facet-badge-captioned", { TextTransparency = 1 })
	rule(".facet-badge-caption", { TextTransparency = 0 })
	rule(".facet-button-caption", {
		TextTransparency = 0,
		TextColor3 = c("content"),
		FontFace = f(package.metrics.typography.control.font),
		TextSize = package.metrics.typography.control.size,
	})
	rule(".facet-accent >> .facet-button-caption", { TextColor3 = c("onAccent") })
	rule(".facet-disabled >> .facet-button-caption", { TextTransparency = extra.disabledContentOpacity })
	rule(".facet-disabled >> .facet-text", { TextTransparency = extra.disabledContentOpacity })
	rule(".facet-skin-caption > Frame > Frame > .facet-button-caption", { TextTransparency = 1 })
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
	rule(".facet-role-destructive >> .facet-text", { TextColor3 = c("onDanger") })
	local onSelected = c("onSelected") or c("content")
	rule(".facet-selected", { BackgroundColor3 = c("controlSelected"), TextColor3 = onSelected })
	rule(".facet-selected >> .facet-text", { TextColor3 = onSelected })
	rule(".facet-disabled", { TextTransparency = extra.disabledContentOpacity })
	rule(".facet-disabled >> .facet-icon", { ImageTransparency = extra.disabledContentOpacity })

	rule(".facet-drag-held", { TextTransparency = 1 })
	rule(".facet-drag-held >> .facet-text", { TextTransparency = 1 })
	rule(".facet-drag-held >> .facet-icon", { ImageTransparency = 1 })
	rule(".facet-accent", { BackgroundColor3 = c("accent"), TextColor3 = c("onAccent") })
	rule(".facet-fill", { BackgroundColor3 = c("accent"), BackgroundTransparency = 0, BorderSizePixel = 0 })
	rule(".facet-level-segment", { BackgroundColor3 = c("control"), BackgroundTransparency = 0, BorderSizePixel = 0 })
	rule(".facet-level-on", { BackgroundColor3 = c("accent") })
	rule(".facet-progress-ring-track", { Color3 = c("control") })
	rule(".facet-path", { Color3 = c("content") })
	rule(".facet-path-content", { Color3 = c("content") })
	rule(".facet-path-secondary", { Color3 = c("contentSecondary") })
	rule(".facet-path-accent", { Color3 = c("accent") })
	rule(".facet-progress-ring-fill", { Color3 = c("accent") })
	rule(".facet-icon", { ImageColor3 = c("content"), BackgroundTransparency = 1 })
	rule(".facet-role-destructive >> .facet-icon", { ImageColor3 = c("onDanger") })
	rule(".facet-selected >> .facet-icon", { ImageColor3 = onSelected })
	rule(
		".facet-divider",
		{ BackgroundColor3 = c("hairline"), BackgroundTransparency = extra.hairlineOpacity, BorderSizePixel = 0 }
	)
	rule(".facet-divider-strong", {
		BackgroundTransparency = extra.strongHairlineOpacity
			or math.max(0, 1 - (1 - (extra.hairlineOpacity or 0.92)) * 3),
	})
	rule(".facet-pane", { BackgroundColor3 = c("surfaceStrong"), BackgroundTransparency = 0, BorderSizePixel = 0 })
	rule(".facet-scrim", {
		BackgroundColor3 = color(types, extra.scrim) or types.Color3.new(0, 0, 0),
		BackgroundTransparency = 1 - (extra.scrimOpacity or 0.45),
		BorderSizePixel = 0,
	})
	rule(".facet-scrim.facet-radial-scrim", {
		BackgroundColor3 = types.Color3.new(0, 0, 0),
		BackgroundTransparency = 1 - math.max(extra.scrimOpacity or 0.45, 0.8),
	})
	local statusRoles: { [string]: string } = {
		neutral = "contentSecondary",
		info = "accent",
		success = "success",
		warning = "warning",
		error = "danger",
		accent = "accent",
		voice = "voice",
		contrast = "contentStrong",
	}
	for status, role in statusRoles do
		local partner = if status == "neutral"
			then "surface"
			elseif status == "error" then "onDanger"
			elseif status == "info" or status == "accent" then "onAccent"
			elseif status == "warning" or status == "voice" then "onWarning"
			elseif status == "contrast" then "surface"
			else "onSuccess"
		rule(".facet-status-" .. status, { BackgroundColor3 = c(role), TextColor3 = c(partner) })
		rule(".facet-status-" .. status .. " > .facet-status-ring", { Color = c(role) })
		rule(".facet-icon-" .. status, { ImageColor3 = c(role), BackgroundTransparency = 1 })
		rule(".facet-status-" .. status .. " > .facet-text", { TextColor3 = c(partner) })
		rule(".facet-status-" .. status .. " > .facet-icon", { ImageColor3 = c(partner) })
	end
	rule(".facet-status-hollow", { BackgroundTransparency = 1 })
	rule(".facet-badge-utility", { BackgroundTransparency = 1, TextColor3 = c("contentSecondary") })
	rule(".facet-badge-utility > .facet-text", { TextColor3 = c("contentSecondary") })
	rule(".facet-badge-utility > .facet-icon", { ImageColor3 = c("contentSecondary") })
	rule(".facet-badge-status", { BackgroundColor3 = c("control"), TextColor3 = c("content") })
	rule(".facet-badge-status > .facet-text", { TextColor3 = c("content") })
	rule(".facet-badge-status > .facet-icon", { ImageColor3 = c("content") })
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

	rule(".facet-shortcut-hint", {
		BackgroundColor3 = c("surfaceStrong"),
		TextColor3 = c("contentStrong"),
		TextSize = package.metrics.typography.caption.size,
	})
	rule(
		".facet-shortcut-hint::UICorner",
		{ CornerRadius = types.UDim.new(0, math.min(6, package.metrics.radii.control)) }
	)
	local families: { [string]: { [string]: number } } = package.metrics.controls or {}
	local hintFamily: { [string]: number } = families.shortcutHint or {}
	local capStroke = hintFamily.capStroke or package.metrics.strokes.hairline or 1
	if capStroke > 0 then
		rule(".facet-shortcut-hint::UIStroke", {
			Color = c("hairline"),
			Transparency = extra.hairlineOpacity or 0.92,
			Thickness = capStroke,
			ApplyStrokeMode = types.Enum.ApplyStrokeMode.Border,
		})
	end
	rule(".facet-shortcut-hint::UIPadding", {
		PaddingLeft = types.UDim.new(0, 8),
		PaddingRight = types.UDim.new(0, 8),
	})
	rule(".facet-toggle-row", { BackgroundTransparency = 1 })
	rule(".facet-toggle-row:Hover", { BackgroundTransparency = 1 })
	rule(".facet-toggle-row:Press", { BackgroundTransparency = 1 })
	rule(".facet-toggle-row.facet-selected", { TextColor3 = c("content") })
	rule(".facet-toggle-row.facet-selected >> .facet-text", { TextColor3 = c("content") })
	rule(".facet-toggle-row.facet-selected >> .facet-icon", { ImageColor3 = c("content") })
	rule(".facet-toggle-plain", { BackgroundTransparency = 1 })
	rule(".facet-toggle-indicator", { BackgroundColor3 = c("control"), BackgroundTransparency = 0 })
	rule(".facet-toggle-on", { BackgroundColor3 = c("selection") })
	local knob, offTrack, loudKnob = c("onSelection") :: Color3, c("control") :: Color3, c("content") :: Color3
	local offKnob = if contrast(knob, offTrack) >= 3
			or contrast(knob, offTrack) >= contrast(loudKnob, offTrack)
		then knob
		else loudKnob
	rule(".facet-toggle-switch >> .facet-toggle-mark", { BackgroundColor3 = offKnob })
	rule(".facet-toggle-checkbox >> .facet-toggle-mark", { BackgroundColor3 = knob })
	rule(".facet-toggle-on >> .facet-toggle-mark", { BackgroundColor3 = knob })
	rule(".facet-toggle-check", { ImageColor3 = c("onSelection") })
	rule(".facet-toggle-checkbox::UIStroke", { Color = c("contentSecondary"), Thickness = 1.5, Transparency = 0.2 })
	rule(".facet-tooltip", { BackgroundColor3 = c("surfaceStrong"), BackgroundTransparency = 0, BorderSizePixel = 0 })
	rule(".facet-tooltip::UICorner", { CornerRadius = types.UDim.new(0, math.min(6, package.metrics.radii.control)) })
	rule(".facet-tooltip::UIStroke", { Color = c("hairline"), Transparency = 0.4, Thickness = 1 })
	rule(".facet-appearance-utility", { BackgroundTransparency = 1 })
	rule(".facet-appearance-utility:Hover", { BackgroundTransparency = 0, BackgroundColor3 = c("controlHover") })
	rule(".facet-appearance-utility:Press", { BackgroundTransparency = 0, BackgroundColor3 = c("controlPressed") })
	rule(
		".facet-appearance-soft",
		{ BackgroundColor3 = c("accent"), BackgroundTransparency = 0.8, TextColor3 = c("accent") }
	)
	rule(".facet-appearance-soft:Hover", { BackgroundColor3 = c("accent"), BackgroundTransparency = 0.7 })
	rule(".facet-appearance-soft:Press", { BackgroundColor3 = c("accent"), BackgroundTransparency = 0.6 })
	rule(".facet-appearance-soft >> .facet-button-caption", { TextColor3 = c("accent") })
	rule(".facet-appearance-soft >> .facet-icon", { ImageColor3 = c("accent") })
	rule(".facet-appearance-link", { BackgroundTransparency = 1, TextColor3 = c("accent") })
	rule(".facet-appearance-link:Hover", { BackgroundTransparency = 1, TextColor3 = c("accent") })
	rule(".facet-appearance-link:Press", { BackgroundTransparency = 1, TextTransparency = 0.3 })
	rule(".facet-appearance-link >> .facet-button-caption", { TextColor3 = c("accent") })
	rule(".facet-appearance-link >> .facet-icon", { ImageColor3 = c("accent") })
	rule(".facet-appearance-link:Press >> .facet-button-caption", { TextTransparency = 0.3 })
	rule(".facet-appearance-link:Press >> .facet-text", { TextTransparency = 0.3 })
	rule(".facet-appearance-link:Press >> .facet-icon", { ImageTransparency = 0.3 })
	rule(
		".facet-appearance-link::UIPadding",
		{ PaddingLeft = types.UDim.new(0, 0), PaddingRight = types.UDim.new(0, 0) }
	)
	local inverse, onInverse = source("inverseSurface"), source("onInverse")
	rule(
		".facet-appearance-inverse",
		{ BackgroundColor3 = c("inverseSurface"), BackgroundTransparency = 0, TextColor3 = c("onInverse") }
	)
	if inverse and onInverse then
		local function toward(amount: number): Color3
			return types.Color3.new(
				inverse.r + (onInverse.r - inverse.r) * amount,
				inverse.g + (onInverse.g - inverse.g) * amount,
				inverse.b + (onInverse.b - inverse.b) * amount
			)
		end
		rule(".facet-appearance-inverse:Hover", { BackgroundColor3 = toward(0.12), TextColor3 = c("onInverse") })
		rule(".facet-appearance-inverse:Press", { BackgroundColor3 = toward(0.2), TextColor3 = c("onInverse") })
	end
	rule(".facet-appearance-inverse >> .facet-button-caption", { TextColor3 = c("onInverse") })
	rule(".facet-appearance-inverse >> .facet-text", { TextColor3 = c("onInverse") })
	rule(".facet-appearance-inverse >> .facet-icon", { ImageColor3 = c("onInverse") })
	local utilityStroke = package.metrics.strokes.utility
	if type(utilityStroke) == "number" and utilityStroke > 0 then
		rule(".facet-appearance-utility::UIStroke", {
			Color = c("hairline"),
			Transparency = extra.hairlineOpacity,
			Thickness = utilityStroke,
			ApplyStrokeMode = types.Enum.ApplyStrokeMode.Border,
		})
	end
	rule(".facet-grabber", { BackgroundColor3 = c("contentSecondary"), BackgroundTransparency = 0.5 })
	rule(".facet-menu-item", { BackgroundTransparency = 1 })
	rule(".facet-menu-item:Hover", { BackgroundTransparency = 0, BackgroundColor3 = c("controlHover") })
	rule(".facet-menu-item:Press", { BackgroundTransparency = 0, BackgroundColor3 = c("controlPressed") })
	rule(".facet-menu-destructive", { BackgroundTransparency = 1, TextColor3 = c("danger") })
	rule(".facet-menu-destructive:Hover", { BackgroundTransparency = 0, BackgroundColor3 = c("controlHover") })
	rule(".facet-menu-destructive:Press", { BackgroundTransparency = 0, BackgroundColor3 = c("controlPressed") })
	rule(".facet-menu-destructive >> .facet-button-caption", { TextColor3 = c("danger") })
	rule(".facet-menu-destructive >> .facet-icon", { ImageColor3 = c("danger") })
	rule(".facet-menu::UIStroke", {
		Color = c("hairline"),
		Transparency = 0.3,
		Thickness = 1,
		ApplyStrokeMode = types.Enum.ApplyStrokeMode.Border,
	})
	rule(".facet-menu::UIShadow", {
		BlurRadius = types.UDim.new(0, 14),
		Transparency = 0.35,
		Offset = types.UDim2.fromOffset(0, 3),
	})
	rule(".facet-menu-group::UICorner", { CornerRadius = types.UDim.new(0, package.metrics.radii.panel) })
	rule(
		".facet-menu-hairline",
		{ BackgroundColor3 = c("hairline"), BackgroundTransparency = extra.hairlineOpacity, BorderSizePixel = 0 }
	)
	for _, state in { "", ":Hover", ":Press" } do
		rule(".facet-menu-item.facet-selected" .. state, {
			BackgroundTransparency = 0,
			BackgroundColor3 = c("accent"),
			TextColor3 = c("onAccent"),
		})
	end
	rule(".facet-menu-item.facet-selected >> .facet-button-caption", { TextColor3 = c("onAccent") })
	rule(".facet-menu-item.facet-selected >> .facet-text", { TextColor3 = c("onAccent") })
	rule(".facet-menu-item.facet-selected >> .facet-icon", { ImageColor3 = c("onAccent") })
	rule(".facet-radial-sector", { Color3 = c("surfaceStrong") })
	rule(".facet-radial-sector.facet-radial-candidate", { Color3 = c("controlSelected") })
	rule(".facet-radial-item::UIPadding", {
		PaddingLeft = types.UDim.new(0, 0),
		PaddingRight = types.UDim.new(0, 0),
		PaddingTop = types.UDim.new(0, 0),
		PaddingBottom = types.UDim.new(0, 0),
	})
	rule(".facet-page-indicator", { BackgroundTransparency = 1 })
	rule(".facet-page-indicator:Hover", { BackgroundTransparency = 1 })
	rule(".facet-page-indicator:Press", { BackgroundTransparency = 1 })
	rule(".facet-page-indicator.facet-selected", { BackgroundTransparency = 1 })
	rule(".facet-page-dot", { BackgroundColor3 = c("contentSecondary"), BackgroundTransparency = 0 })
	rule(".facet-page-indicator:Hover >> .facet-page-dot", { BackgroundColor3 = c("content") })
	rule(".facet-page-indicator.facet-selected >> .facet-page-dot", {
		BackgroundColor3 = c("accent"),
		BackgroundTransparency = 0,
	})
	rule(".facet-floating::UIStroke", { Color = c("hairline"), Transparency = 0.3, Thickness = 1 })
	rule(".facet-tail", { BackgroundColor3 = c("surfaceStrong"), BackgroundTransparency = 0, BorderSizePixel = 0 })
	local outlineInk = c("hairline") :: Color3
	local outlineFill = c("surfaceStrong") :: Color3
	rule(".facet-outlined::UIStroke", { Transparency = 1 })
	rule(".facet-outline", { Color3 = outlineInk:Lerp(outlineFill, 0.3), Thickness = 1 })
	rule(".facet-outline-tooltip", { Color3 = outlineInk:Lerp(outlineFill, 0.4) })
	rule(".facet-step-circle::UIStroke", { Color = c("contentSecondary"), Thickness = 1 })
	rule(".facet-invalid::UIStroke", { Color = c("danger"), Thickness = 1 })
	rule(".facet-date-time-picker", { BackgroundTransparency = 1 })
	rule(".facet-radio-mark::UIStroke", { Color = c("contentSecondary"), Thickness = 1.5 })
	rule(".facet-segmented-stroke", { BackgroundTransparency = 1 })
	rule(".facet-segmented-stroke::UIStroke", { Color = c("hairline"), Thickness = 1 })
	rule(".facet-segmented-utility", { BackgroundTransparency = 1 })
	rule(".facet-card-option::UIStroke", { Color = c("hairline"), Thickness = 1 })
	rule(".facet-color-picker", { BackgroundTransparency = 1 })
	rule(".facet-color-swatch::UIStroke", { Color = c("hairline"), Transparency = 0, Thickness = 1 })
	rule(".facet-color-swatch >> UICorner", { CornerRadius = types.UDim.new(0, package.metrics.radii.control) })
	rule(".facet-color-cell::UIPadding", {
		PaddingLeft = types.UDim.new(0, 0),
		PaddingRight = types.UDim.new(0, 0),
		PaddingTop = types.UDim.new(0, 0),
		PaddingBottom = types.UDim.new(0, 0),
	})
	for _, member in { ".facet-avatar", ".facet-button" } do
		rule(".facet-avatar-stack > " .. member .. "::UIStroke", {
			Color = c("surface"),
			Thickness = 2,
			ApplyStrokeMode = types.Enum.ApplyStrokeMode.Border,
			BorderStrokePosition = types.Enum.BorderStrokePosition.Outer,
		})
	end
	for role, ink in AVATAR_BACKGROUNDS do
		local selector = ".facet-avatar-background-" .. role
		rule(selector, { BackgroundColor3 = c(role), BackgroundTransparency = 0, TextColor3 = c(ink) })
		rule(selector .. " > .facet-text", { TextColor3 = c(ink) })
		rule(selector .. " > .facet-icon", { ImageColor3 = c(ink) })
	end
	local focus = if package.chrome then package.chrome.focus else nil
	local focusColor = if focus then focus.color else nil
	rule(".facet-focus-ring", {
		BackgroundColor3 = if type(focusColor) == "table"
			then color(types, focusColor :: ThemeTypes.RGB)
			elseif type(focusColor) == "string" then c(
				string.lower(string.sub(focusColor, 2, 2)) .. string.sub(focusColor, 3)
			) or c("accent")
			else c("accent"),
	})
	rule(".facet-focus-ring::UICorner", { CornerRadius = types.UDim.new(0, package.metrics.radii.control) })
	rule(".facet-avatar-ring", { Color = c("accent"), Transparency = 0 })
	rule(".facet-avatar-hover", { Color = c("accent") })
	rule(".facet-avatar-ring-gap", { Color = c("surface"), Transparency = 0 })
	rule(".facet-quiet-destructive", { TextColor3 = c("danger") })
	rule(".facet-quiet-destructive:Hover", { TextColor3 = c("danger") })
	rule(".facet-quiet-destructive:Press", { TextColor3 = c("danger") })
	rule(".facet-quiet-destructive >> .facet-button-caption", { TextColor3 = c("danger") })
	rule(".facet-quiet-destructive >> .facet-icon", { ImageColor3 = c("danger") })

	local track, quiet, loud = c("control") :: Color3, c("contentSecondary") :: Color3, c("content") :: Color3
	local segmentInk = if contrast(quiet, track) >= 4.5 or contrast(quiet, track) >= contrast(loud, track)
		then quiet
		else loud
	rule(".facet-tab-item", { BackgroundTransparency = 1, TextColor3 = c("contentSecondary") })
	rule(".facet-tab-item >> .facet-button-caption", { TextColor3 = c("contentSecondary") })
	rule(".facet-tab-item.facet-skinned", { TextColor3 = segmentInk })
	rule(".facet-tab-item.facet-skinned >> .facet-button-caption", { TextColor3 = segmentInk })
	rule(".facet-tab-item:Hover", { BackgroundTransparency = 1, TextColor3 = c("content") })
	rule(".facet-tab-item:Hover >> .facet-button-caption", { TextColor3 = c("content") })
	rule(".facet-tab-item:Press", { BackgroundTransparency = 1, TextColor3 = c("content") })
	rule(".facet-tab-item:Press >> .facet-button-caption", { TextColor3 = c("content") })
	rule(".facet-tab-current", { TextColor3 = c("content") })
	rule(".facet-tab-current >> .facet-button-caption", { TextColor3 = c("content") })
	rule(".facet-tab-item.facet-selected", { BackgroundTransparency = 0, TextColor3 = onSelected })
	rule(".facet-tab-item.facet-selected >> .facet-button-caption", { TextColor3 = onSelected })
	rule(
		".facet-tab-filled",
		{ BackgroundTransparency = 0, BackgroundColor3 = c("accent"), TextColor3 = c("onAccent") }
	)
	rule(".facet-tab-filled >> .facet-button-caption", { TextColor3 = c("onAccent") })
	rule(".facet-tab-filled >> .facet-icon", { ImageColor3 = c("onAccent") })
	rule(".facet-stepper-track", { BackgroundColor3 = c("control"), BackgroundTransparency = 0, BorderSizePixel = 0 })
	rule(".facet-stepper-track::UICorner", { CornerRadius = types.UDim.new(0, package.metrics.radii.control) })
	rule(".facet-skinned > #Content > .facet-stepper-track", { BackgroundTransparency = 1 })
	do
		local recipe = if package.chrome then package.chrome.stepperPlate else nil
		local inset: ThemeTypes.Insets = if recipe then recipe.contentInsets or {} else {}
		rule(".facet-skinned >> .facet-stepper-inset", {
			PaddingLeft = types.UDim.new(0, math.max(12, inset.left or 0)),
		})
	end
	rule(".facet-stepper-button", { BackgroundTransparency = 1 })
	rule(".facet-stepper-button:Hover", { BackgroundTransparency = 0, BackgroundColor3 = c("controlHover") })
	rule(".facet-stepper-button:Press", { BackgroundTransparency = 0, BackgroundColor3 = c("controlPressed") })
	rule(".facet-choice", { BackgroundTransparency = 1, TextXAlignment = types.Enum.TextXAlignment.Left })
	rule(".facet-choice:Hover", { BackgroundTransparency = 0, BackgroundColor3 = c("controlHover") })
	rule(".facet-choice:Press", { BackgroundTransparency = 0, BackgroundColor3 = c("controlPressed") })
	rule(
		".facet-choice-current",
		{ BackgroundTransparency = 0.82, BackgroundColor3 = c("accent"), TextColor3 = c("accent") }
	)
	rule(".facet-choice-current:Hover", { BackgroundTransparency = 0.72, BackgroundColor3 = c("accent") })
	rule(".facet-choice-current:Press", { BackgroundTransparency = 0.62, BackgroundColor3 = c("accent") })
	rule(".facet-choice-current >> .facet-button-caption", { TextColor3 = c("accent") })
	rule(".facet-choice-current >> .facet-icon", { ImageColor3 = c("accent") })
	rule(".facet-segmented", { BackgroundColor3 = c("control"), BackgroundTransparency = 0, BorderSizePixel = 0 })
	local trackRadius = if package.metrics.radii.control > 0 then package.metrics.radii.control + 2 else 0
	rule(".facet-segmented::UICorner", { CornerRadius = types.UDim.new(0, trackRadius) })

	rule(".facet-tab-plate", { BackgroundColor3 = c("surfaceStrong") })
	rule(".facet-tab-plate::UIStroke", {
		Color = c("hairline"),
		Transparency = extra.hairlineOpacity,
		Thickness = package.metrics.strokes.hairline or 1,
	})
	rule(".facet-segmented::UIPadding", {
		PaddingLeft = types.UDim.new(0, SEGMENT_INSET),
		PaddingRight = types.UDim.new(0, SEGMENT_INSET),
		PaddingTop = types.UDim.new(0, SEGMENT_INSET),
		PaddingBottom = types.UDim.new(0, SEGMENT_INSET),
	})
	rule(".facet-segment", { BackgroundTransparency = 1, TextColor3 = segmentInk })
	rule(".facet-segment::UICorner", { CornerRadius = types.UDim.new(0, math.max(0, trackRadius - SEGMENT_INSET)) })
	rule(".facet-segmented-pill >> .facet-segment::UICorner", { CornerRadius = types.UDim.new(1, 0) })
	rule(".facet-segmented-square >> .facet-segment::UICorner", { CornerRadius = types.UDim.new(0, 0) })
	rule(".facet-segment-fill", { BackgroundColor3 = c("accent"), BackgroundTransparency = 0, BorderSizePixel = 0 })
	rule(
		".facet-segment-fill::UICorner",
		{ CornerRadius = types.UDim.new(0, math.max(0, trackRadius - SEGMENT_INSET)) }
	)
	rule(".facet-segmented-pill >> .facet-segment-fill::UICorner", { CornerRadius = types.UDim.new(1, 0) })
	rule(".facet-segmented-square >> .facet-segment-fill::UICorner", { CornerRadius = types.UDim.new(0, 0) })
	rule(".facet-segment >> .facet-button-caption", { TextColor3 = segmentInk })
	rule(
		".facet-segment:Hover",
		{ BackgroundTransparency = 0, BackgroundColor3 = c("controlHover"), TextColor3 = c("content") }
	)
	rule(
		".facet-segment:Press",
		{ BackgroundTransparency = 0, BackgroundColor3 = c("controlPressed"), TextColor3 = c("content") }
	)
	rule(
		".facet-segment-current",
		{ BackgroundTransparency = 0, BackgroundColor3 = c("accent"), TextColor3 = c("onAccent") }
	)
	rule(".facet-segment-current:Hover", { BackgroundColor3 = c("accent"), TextColor3 = c("onAccent") })
	rule(".facet-segment-current:Press", { BackgroundColor3 = c("accent"), TextColor3 = c("onAccent") })
	rule(".facet-segment-current >> .facet-button-caption", { TextColor3 = c("onAccent") })
	rule(".facet-segment-current >> .facet-icon", { ImageColor3 = c("onAccent") })
	rule(".facet-menu-destructive >> .facet-text", { TextColor3 = c("danger") })
	rule(".facet-appearance-soft >> .facet-text", { TextColor3 = c("accent") })
	rule(".facet-appearance-link >> .facet-text", { TextColor3 = c("accent") })
	rule(".facet-quiet-destructive >> .facet-text", { TextColor3 = c("danger") })
	rule(".facet-menu-item::UICorner", {
		CornerRadius = types.UDim.new(
			0,
			math.max(0, package.metrics.radii.panel - (package.metrics.space or neutral.metrics.space).xs)
		),
	})
	rule(".facet-menu-destructive", { TextColor3 = c("content") })
	rule(".facet-menu-destructive >> .facet-button-caption", { TextColor3 = c("content") })
	rule(".facet-menu-destructive >> .facet-text", { TextColor3 = c("content") })
	for _, state in { ":Hover", ":Press" } do
		rule(".facet-menu-destructive" .. state, { BackgroundTransparency = 0, BackgroundColor3 = c("danger") })
		rule(".facet-menu-destructive" .. state .. " >> .facet-button-caption", { TextColor3 = c("onDanger") })
		rule(".facet-menu-destructive" .. state .. " >> .facet-text", { TextColor3 = c("onDanger") })
		rule(".facet-menu-destructive" .. state .. " >> .facet-icon", { ImageColor3 = c("onDanger") })
	end
	rule(".facet-choice-current >> .facet-text", { TextColor3 = c("accent") })
	rule(".facet-tab-filled >> .facet-text", { TextColor3 = c("onAccent") })
	rule(".facet-segment-current >> .facet-text", { TextColor3 = c("onAccent") })
	rule(".facet-accent >> .facet-text", { TextColor3 = c("onAccent") })
	rule(".facet-accent >> .facet-icon", { ImageColor3 = c("onAccent") })
	rule(".facet-calendar-day", { BackgroundTransparency = 1 })
	rule(".facet-calendar-day::UIPadding", {
		PaddingLeft = types.UDim.new(0, 0),
		PaddingRight = types.UDim.new(0, 0),
		PaddingTop = types.UDim.new(0, 0),
		PaddingBottom = types.UDim.new(0, 0),
	})
	rule(".facet-calendar-day:Hover", { BackgroundTransparency = 0, BackgroundColor3 = c("controlHover") })
	rule(".facet-calendar-day:Press", { BackgroundTransparency = 0, BackgroundColor3 = c("controlPressed") })
	rule(".facet-calendar-band", { BackgroundColor3 = c("controlSelected"), BackgroundTransparency = 0 })
	rule(".facet-calendar-disc", { BackgroundColor3 = c("accent"), BackgroundTransparency = 0 })
	rule(".facet-calendar-end", { BackgroundColor3 = c("content") })
	rule(".facet-calendar-today::UIStroke", { Color = c("accent"), Thickness = 1 })
	rule(".facet-calendar-strike", { BackgroundColor3 = c("contentSecondary"), BackgroundTransparency = 0 })
	rule(".facet-calendar-number", { FontFace = f({ weight = "SemiBold" }) })
	rule(".facet-calendar-banded", { TextColor3 = onSelected })
	rule(".facet-calendar-dim", { TextColor3 = c("contentSecondary"), FontFace = f({ weight = "Regular" }) })
	rule(".facet-calendar-chosen", { TextColor3 = c("onAccent") })
	rule(".facet-calendar-chosen-end", { TextColor3 = c("surface") })
	rule(".facet-skinned", { BackgroundTransparency = 1 })

	for _, slot in { "control", "field", "panel" } do
		rule(".facet-skin-art-" .. slot, if extra.artTint then { ImageColor3 = c("artTint") } else {})
	end
	for status, role in statusRoles do
		rule(".facet-badge.facet-status-" .. status .. " > #SkinBoundary >> .facet-skin-art", { ImageColor3 = c(role) })
	end
	for _, appearance in { "status", "utility" } do
		rule(
			".facet-badge-" .. appearance .. " > #SkinBoundary >> .facet-skin-art",
			{ ImageColor3 = types.Color3.new(1, 1, 1) }
		)
	end
	local plate = ((package.chrome or {}) :: { [string]: ThemeTypes.SkinLayer }).control
	local selectedArt: ThemeTypes.AssetLink? = nil
	local selectedLayer = 0
	local plateLayers: { ThemeTypes.SkinLayer } = if plate == nil
		then {}
		elseif plate.kind == "layered" then plate.layers or {}
		else { plate }
	for index, layer in plateLayers do
		local link = if type(layer.asset) == "table" then (layer.asset :: ThemeTypes.AssetVariants).selected else nil
		if link ~= nil and selectedArt == nil then
			selectedArt, selectedLayer = link, index
		end
	end
	local selectedLink: { asset: string, rotation: number?, tint: ThemeTypes.RGB? }? = if type(selectedArt)
			== "string"
		then { asset = selectedArt }
		else selectedArt :: any
	local white, black = types.Color3.new(1, 1, 1), types.Color3.new(0, 0, 0)
	local art = if selectedLink then (package.assets or {})[selectedLink.asset] else nil
	local pressedEmphasis = false
	for _, theme in package.style.themes do
		local swatch = merge(neutral.style.themes[1].colors, theme.colors)
		local fill, ink = color(types, swatch.accent), color(types, swatch.onAccent)
		if art and fill and ink and contrast(ink, black) <= contrast(fill, black) then
			pressedEmphasis = true
		end
	end
	for _, entry in
		{ { ".facet-role-destructive", "danger", "onDanger" }, { ".facet-accent", "accent", "onAccent" } } :: { { string } }
	do
		local selector, fill, ink = entry[1], c(entry[2]) :: Color3, c(entry[3]) :: Color3
		local pressed = pressedEmphasis and entry[2] == "accent"
		local tinted = not pressed and contrast(ink, black) > contrast(fill, black)
		rule(selector .. " > #SkinBoundary >> .facet-skin-art", { ImageColor3 = if tinted then fill else white })
		rule(selector .. ".facet-skinned", {
			BackgroundTransparency = if tinted or pressed then 1 else 0,
			TextColor3 = if pressed then onSelected else nil,
		})
		rule(selector .. " > #SkinBoundary", { Visible = tinted or pressed })
		local swapped = pressed and selectedLink ~= nil and art ~= nil
		rule(
			selector .. " > #SkinBoundary >> #control" .. math.max(selectedLayer, 1),
			if swapped
					and selectedLink
					and art
				then {
					Image = art.content or art.contentId or "",
					Rotation = selectedLink.rotation or 0,
					ImageColor3 = color(types, selectedLink.tint) or white,
				}
				else {}
		)
		rule(selector .. ".facet-skinned >> .facet-button-caption", if swapped then { TextColor3 = onSelected } else {})
		rule(selector .. ".facet-skinned >> .facet-text", if swapped then { TextColor3 = onSelected } else {})
		rule(selector .. ".facet-skinned >> .facet-icon", if swapped then { ImageColor3 = onSelected } else {})
	end
	rule(".facet-toggle-checkbox.facet-skinned::UIStroke", { Transparency = 1 })
	rule(".facet-menu.facet-skinned::UIStroke", { Transparency = 1 })
	rule(".facet-segment-current.facet-skinned", if selectedArt then {} else { BackgroundTransparency = 0 })
	rule(".facet-segment-current > #SkinBoundary", if selectedArt then {} else { Visible = false })
	rule(".facet-segment-fill", if selectedArt then { Visible = false } else {})
	rule(".facet-segmented-slides > .facet-segment-current", if selectedArt then {} else { BackgroundTransparency = 1 })
	local authoredSelection = false
	for _, theme in package.style.themes do
		if type(theme.extra) == "table" and theme.extra.selection ~= nil then
			authoredSelection = true
		end
	end
	local markPlate = if authoredSelection then c("selection") else c("controlSelected")
	local markInk = if authoredSelection then c("onSelection") else onSelected
	local markStates: { string } = if authoredSelection then { "", ":Hover", ":Press" } else { "" }
	for _, suffix in markStates do
		rule(".facet-selection-mark.facet-selected" .. suffix, { BackgroundColor3 = markPlate, TextColor3 = markInk })
	end
	rule(".facet-selection-mark.facet-selected >> .facet-button-caption", { TextColor3 = markInk })
	rule(".facet-selection-mark.facet-selected >> .facet-text", { TextColor3 = markInk })
	rule(".facet-selection-mark.facet-selected >> .facet-icon", { ImageColor3 = markInk })
	if authoredSelection then
		local linkInk = c("selection")
		rule(".facet-appearance-link.facet-selected", { TextColor3 = linkInk })
		rule(".facet-appearance-link.facet-selected >> .facet-button-caption", { TextColor3 = linkInk })
		rule(".facet-appearance-link.facet-selected >> .facet-text", { TextColor3 = linkInk })
		rule(".facet-appearance-link.facet-selected >> .facet-icon", { ImageColor3 = linkInk })
	end
	if extra.dimDisabledPlates == true then
		local dim = extra.disabledContentOpacity or 0.4
		local page = source("surface")
		local function faded(role: string): Color3?
			local plate, base = source(role), page
			if plate == nil or base == nil then
				return c(role)
			end
			return types.Color3.new(
				plate.r + (base.r - plate.r) * dim,
				plate.g + (base.g - plate.g) * dim,
				plate.b + (base.b - plate.b) * dim
			)
		end
		for _, entry in
			{
				{ ".facet-button.facet-disabled", "control" },
				{ ".facet-button.facet-selected.facet-disabled", "controlSelected" },
				{ ".facet-accent.facet-disabled", "accent" },
				{ ".facet-appearance-soft.facet-disabled", "accent" },
				{ ".facet-appearance-inverse.facet-disabled", "inverseSurface" },
				{ ".facet-role-destructive.facet-disabled", "danger" },
				{ ".facet-disabled >> .facet-toggle-indicator", "control" },
				{ ".facet-disabled >> .facet-toggle-on", "selection" },
			} :: { { string } }
		do
			rule(entry[1], { BackgroundColor3 = faded(entry[2]) })
		end
		rule(".facet-appearance-utility.facet-disabled", { BackgroundColor3 = c("surface") })
		if authoredSelection then
			rule(".facet-selection-mark.facet-selected.facet-disabled", { BackgroundColor3 = faded("selection") })
		end
	end
	do
		local on = selectedArt ~= nil
		local tint = if selectedLink then selectedLink.tint else nil
		rule(
			".facet-skinned.facet-selected",
			if on then { BackgroundTransparency = 1, TextColor3 = onSelected } else {}
		)
		rule(".facet-skinned.facet-selected > #SkinBoundary", if on then { Visible = true } else {})
		rule(
			".facet-skinned.facet-selected > #SkinBoundary >> .facet-skin-art",
			if on then { ImageColor3 = color(types, tint) or types.Color3.new(1, 1, 1) } else {}
		)
		rule(".facet-skinned.facet-selected >> .facet-button-caption", if on then { TextColor3 = onSelected } else {})
		rule(".facet-skinned.facet-selected >> .facet-text", if on then { TextColor3 = onSelected } else {})
		rule(".facet-skinned.facet-selected >> .facet-icon", if on then { ImageColor3 = onSelected } else {})
	end
	rule(".facet-tab-filled.facet-skinned", if selectedArt then {} else { BackgroundTransparency = 0 })
	rule(".facet-tab-filled > #SkinBoundary", if selectedArt then {} else { Visible = false })
	add(".facet-fading::UIStroke", {
		Enabled = false,
		ApplyStrokeMode = types.Enum.ApplyStrokeMode.Border,
		BorderStrokePosition = types.Enum.BorderStrokePosition.Inner,
	})
	add(".facet-fading > .facet-fade-stroke", { Enabled = true })
	for _, definition in (package.rules or {}) :: { ThemeTypes.Rule } do
		local properties = table.clone(definition.properties or definition.props or {})
		for key, value in properties do
			if type(value) == "table" and type((value :: any).role) == "string" then
				properties[key] = c((value :: any).role)
			end
		end
		rule(definition.selector, properties, true)
	end
	local present: { [string]: boolean } = {}
	local presence: { NativeRule } = {}
	for _, definition in rules do
		local selector = definition.selector
		if
			string.sub(selector, -21) == " > .facet-fade-stroke"
			and selector ~= ".facet-fading > .facet-fade-stroke"
			and not present[selector]
		then
			present[selector] = true
			table.insert(presence, {
				id = selector .. ":presence",
				selector = selector,
				properties = { Transparency = 0 },
				priority = #presence,
			})
		end
	end
	local ordered = { rules[1] }
	table.move(presence, 1, #presence, 2, ordered)
	table.move(rules, 2, #rules, #ordered + 1, ordered)
	for index, definition in ordered do
		definition.priority = (index - 1) * 10
	end
	return ordered
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

local function createStyleSheet(
	Compose: typeof(ComposeTypes),
	runtime: ComposeTypes.Runtime,
	packageOrReadable: Engine.Value<ThemeTypes.ThemePackage>?,
	options: ThemeTypes.ThemeOptions?
): StyleSheet
	local settings: ThemeTypes.ThemeOptions = options or {}
	local types = typesFor(settings)
	local Host = (runtime.constructors :: unknown) :: Engine.Host
	assert(
		((settings :: unknown) :: { [string]: unknown }).reducedMotion == nil,
		'Facet createStyleSheet: the reducedMotion option is gone; set motionLevel = "normal", "limited" or "none"'
	)
	local function snaps(use: ComposeTypes.Use): boolean
		local chosen = read(settings.motionLevel, use)
		return chosen ~= nil and motionLevels.resolve(chosen, false) == "none"
	end
	local preferredTransparency = settings.preferredTransparency
	if preferredTransparency == nil then
		local globals = getfenv(0)
		local gui = globals.game and globals.game:GetService("GuiService")
		if gui then
			local source = Compose.cell(gui.PreferredTransparency)
			preferredTransparency = source
			local connection = gui:GetPropertyChangedSignal("PreferredTransparency"):Connect(function()
				source:set(gui.PreferredTransparency)
			end)
			Compose.cleanup(function()
				connection:Disconnect()
			end)
		end
	end
	local hover: Engine.Value<boolean>? = nil
	do
		local globals = getfenv(0)
		local input = globals.game and globals.game:GetService("UserInputService")
		if input then
			local held = input.PreferredInput
			local stopNudges: (() -> ())? = nil
			local refresh: () -> ()
			local function pointing(): boolean
				local current = input.PreferredInput
				if preferredInput.withheld(input, current, types.Enum.PreferredInput.KeyboardAndMouse) then
					stopNudges = stopNudges or preferredInput.nudges(input, types.Enum, refresh)
				else
					held = current
					if stopNudges then
						stopNudges()
						stopNudges = nil
					end
				end
				return held ~= types.Enum.PreferredInput.Touch
			end
			local source = Compose.cell(false)
			hover = source
			refresh = function()
				source:set(pointing())
			end
			refresh()
			local connection = input:GetPropertyChangedSignal("PreferredInput"):Connect(refresh)
			Compose.cleanup(function()
				connection:Disconnect()
				if stopNudges then
					stopNudges()
				end
			end)
		end
	end
	local distant: Engine.Value<boolean>? = settings.tenFoot
	if distant == nil then
		local globals = getfenv(0)
		local gui = globals.game and globals.game:GetService("GuiService")
		local input = globals.game and globals.game:GetService("UserInputService")
		if gui and input then
			local interface = false
			pcall(function()
				interface = gui:IsTenFootInterface()
			end)
			local function sample(): boolean
				return adaptive.isTenFoot({
					tenFootInterface = interface,
					displaySize = if typeof(gui.ViewportDisplaySize) == "EnumItem"
						then gui.ViewportDisplaySize.Name
						else nil,
					mouse = input.MouseEnabled,
					touch = input.TouchEnabled,
				})
			end
			local source = Compose.cell(sample())
			distant = source
			local connections = {
				gui:GetPropertyChangedSignal("ViewportDisplaySize"):Connect(function()
					source:set(sample())
				end),
				input:GetPropertyChangedSignal("MouseEnabled"):Connect(function()
					source:set(sample())
				end),
				input:GetPropertyChangedSignal("TouchEnabled"):Connect(function()
					source:set(sample())
				end),
			}
			Compose.cleanup(function()
				for _, connection in connections do
					connection:Disconnect()
				end
			end)
		end
	end
	local hoverless: { [{ NativeRule }]: { NativeRule } } = setmetatable({}, { __mode = "k" }) :: any
	local function withoutHover(rules: { NativeRule }): { NativeRule }
		local cached = hoverless[rules]
		if cached then
			return cached
		end
		local kept: { NativeRule } = {}
		for _, definition in rules do
			if not string.find(definition.selector, ":Hover", 1, true) then
				table.insert(kept, definition)
			end
		end
		hoverless[rules] = kept
		return kept
	end
	local function preferenceFor(use: ComposeTypes.Use): number
		local value = read(preferredTransparency, use)
		return if type(value) == "number" and value == value then math.clamp(value, 0, 1) else 1
	end
	local defaultTimings: { [string]: TweenInfo } = {}
	type PaintState = "normal" | "press" | "hover"
	local function timingFor(package: ThemeTypes.ThemePackage, role: PaintState, use: ComposeTypes.Use): TweenInfo
		local explicit = read(settings.transition, use)
		local motion = ((package.metrics or {}) :: { motion: ThemeTypes.MotionMetrics? }).motion
		local normal = if motion and motion.normal then motion.normal else neutral.metrics.motion.normal
		local seconds
		if snaps(use) or explicit == false then
			seconds = 0
		elseif explicit ~= nil then
			return explicit :: TweenInfo
		elseif role == "normal" then
			seconds = normal
		else
			local authored = if motion then (motion :: any)[role] else nil
			seconds = math.min(authored or (neutral.metrics.motion :: any)[role], normal)
		end
		local style = (motion and motion.styles and motion.styles.paint)
			or (neutral.metrics.motion.styles :: { [string]: string }).paint
		local key = `{seconds}|{style}`
		local cached: TweenInfo? = defaultTimings[key]
		if cached then
			return cached
		end
		local timing =
			types.TweenInfo.new(seconds, (types.Enum.EasingStyle :: any)[style], types.Enum.EasingDirection.Out)
		defaultTimings[key] = timing
		return timing
	end
	local function stateOf(selector: string): PaintState
		return if string.find(selector, ":Press", 1, true)
			then "press"
			elseif string.find(selector, ":Hover", 1, true) then "hover"
			else "normal"
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
	local scaled = setmetatable(
		{} :: { [NativeRule]: { preference: number, properties: ThemeTypes.RuleProperties } },
		{ __mode = "k" }
	)
	local function withPreference(definition: NativeRule, preference: number): NativeRule
		local translucent = definition.properties.BackgroundTransparency
		if
			preference >= 1
			or (definition.selector ~= ".facet-scrim" and definition.selector ~= ".facet-scrim.facet-radial-scrim")
			or type(translucent) ~= "number"
			or translucent <= 0
			or translucent >= 1
		then
			return definition
		end
		local cached = scaled[definition]
		if cached == nil or cached.preference ~= preference then
			local properties = table.clone(definition.properties)
			properties.BackgroundTransparency = translucent * preference
			cached = { preference = preference, properties = properties }
			scaled[definition] = cached
		end
		return {
			id = definition.id,
			selector = definition.selector,
			priority = definition.priority,
			properties = cached.properties,
		}
	end
	local ids = Compose.cell({} :: { string })
	local TOKENS: { [PaintState]: string } =
		{ normal = "FacetMotionNormal", press = "FacetMotionPress", hover = "FacetMotionHover" }
	type MountedRule = {
		node: StyleRule,
		priority: number,
		properties: ThemeTypes.RuleProperties?,
		transitions: { [string]: string }?,
		timing: string?,
	}
	local mounted: { [string]: MountedRule } = {}
	type ByTiming = { [string]: { [string]: string } }
	local transitionTables = (
		setmetatable({} :: { [ThemeTypes.RuleProperties]: ByTiming }, { __mode = "k" }) :: unknown
	) :: { [ThemeTypes.RuleProperties]: ByTiming }
	local function transitionsFor(properties: ThemeTypes.RuleProperties, timing: string): { [string]: string }
		local byTiming = transitionTables[properties]
		if byTiming == nil then
			local fresh = (setmetatable({} :: ByTiming, { __mode = "k" }) :: unknown) :: ByTiming
			byTiming = fresh
			transitionTables[properties] = fresh
		end
		local transitions = byTiming[timing]
		if transitions == nil then
			local built: { [string]: string } = {}
			for property, value in properties do
				if typeof(value) == "Color3" or string.find(property, "Transparency$") then
					built[property] = "$" .. timing
				end
			end
			byTiming[timing] = built
			transitions = built
		end
		return transitions :: { [string]: string }
	end
	type Known = { [ThemeTypes.RuleProperties]: boolean }
	local comparisons = (
		setmetatable({} :: { [ThemeTypes.RuleProperties]: Known }, { __mode = "k" }) :: unknown
	) :: { [ThemeTypes.RuleProperties]: Known }
	local function sameRuleProperties(left: ThemeTypes.RuleProperties, right: ThemeTypes.RuleProperties): boolean
		local known = comparisons[left]
		if known == nil then
			known = (setmetatable({} :: Known, { __mode = "k" }) :: unknown) :: Known
			comparisons[left] = known
		end
		local same = known[right]
		if same == nil then
			same = sameProperties(left, right)
			known[right] = same
		end
		return same :: boolean
	end
	local function apply(record: MountedRule, definition: NativeRule, timing: string)
		if record.priority ~= definition.priority then
			record.node.Priority = definition.priority
			record.priority = definition.priority
		end
		local properties = definition.properties
		local propertiesChanged = record.properties == nil
			or (record.properties ~= properties and not sameRuleProperties(record.properties, properties))
		if not propertiesChanged and record.timing == timing then
			return
		end
		local transitions = transitionsFor(properties, timing)
		local previous = record.transitions
		local timingChanged = previous ~= transitions and (previous == nil or not sameProperties(previous, transitions))
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
	local written: { [string]: TweenInfo } = {}
	local sheet = Host.StyleSheet(settings.name or "FacetTheme")({
		Compose.keyed({
			from = ids,
			render = function(current: ComposeTypes.Readable<string>)
				local id = current:peek()
				local initial = definitions[id]
				local node = Host.StyleRule({
					Name = initial.id,
					Selector = initial.selector,
					Priority = initial.priority,
				})
				local record: MountedRule = { node = node, priority = initial.priority }
				mounted[id] = record
				apply(record, initial, TOKENS[stateOf(initial.selector)])
				Compose.cleanup(function()
					if mounted[id] == record then
						mounted[id] = nil
					end
				end)
				return node
			end,
		}),
	})
	Compose.watch(function(use: ComposeTypes.Use)
		local package = themes.forDistance(
			read(packageOrReadable, use) or neutral,
			if read(distant, use) == true then "ten-foot" else "near"
		)
		local current = compiledRules(package, read(settings.theme, use))
		local hovering = read(settings.hover, use)
		if hovering == nil then
			hovering = read(hover, use)
		end
		if hovering == false then
			current = withoutHover(current)
		end
		for state, token in TOKENS do
			local timing = timingFor(package, state :: PaintState, use)
			written[token] = timing
			sheet:SetAttribute(token, timing)
		end
		local preference = preferenceFor(use)
		local previousIds = ids:peek()
		local structureChanged = #previousIds ~= #current
		table.clear(definitions)
		for index, compiledDefinition in current do
			local definition = withPreference(compiledDefinition, preference)
			definitions[definition.id] = definition
			if previousIds[index] ~= definition.id then
				structureChanged = true
			end
			local record = mounted[definition.id]
			if record then
				apply(record, definition, TOKENS[stateOf(definition.selector)])
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
	for _, token in TOKENS do
		local connection = sheet:GetAttributeChangedSignal(token):Connect(function()
			local timing: unknown = written[token]
			if timing ~= nil and sheet:GetAttribute(token) ~= timing then
				sheet:SetAttribute(token, timing)
			end
		end)
		Compose.cleanup(function()
			connection:Disconnect()
		end)
	end
	local warmed: { [ThemeTypes.ThemePackage]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	Compose.watch(function(use: ComposeTypes.Use)
		local package = read(packageOrReadable, use)
		if package == nil or warmed[package] then
			return
		end
		warmed[package] = true
		local content: { string } = {}
		for _, asset in pairs(package.assets or {}) do
			local id = asset.content or asset.contentId
			if type(id) == "string" and id ~= "" and asset.preload ~= "lazy" then
				table.insert(content, id)
			end
		end
		local provider: ContentProvider? = settings.contentProvider
		if provider == nil and #content > 0 then
			local globals = getfenv(0)
			provider = globals.game and globals.game:GetService("ContentProvider")
		end
		if provider and #content > 0 then
			if task then
				task.spawn(provider.PreloadAsync, provider, content)
			else
				provider:PreloadAsync(content)
			end
		end
	end)
	return sheet
end

local function variantAsset(
	value: ThemeTypes.AssetSource?,
	state: ThemeTypes.SkinState,
	selected: boolean
): (string?, { rotation: number?, tint: ThemeTypes.RGB? })
	if type(value) == "string" then
		return value, {}
	end
	if type(value) ~= "table" then
		return nil, {}
	end
	local linked = ((value :: unknown) :: { asset: unknown }).asset
	if linked ~= nil then
		return linked :: string, value :: any
	end
	local variants = value :: ThemeTypes.AssetVariants
	local chosen = (
		if state == "hover"
			then variants.hover
			elseif state == "pressed" then variants.pressed
			elseif state == "selected" then variants.selected
			elseif state == "disabled" then variants.disabled
			else nil
	)
		or (if selected then variants.selected else nil)
		or variants.default
	if type(chosen) == "table" then
		return chosen.asset, chosen
	end
	return chosen, {}
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
	Rotation: number,
	ImageColor3: Color3,
}

type MountedImage = {
	node: ImageLabel,
	properties: ImageLayer,
	caption: ComposeTypes.Cell<ImageLayer>?,
	visible: boolean,
}

local function grown(types: Engine.RobloxTypes, value: ImageLayer, fit: Vector2): UDim2
	local size = value.Size
	if not value.text or fit.X <= 0 then
		return size
	end
	local inset: ThemeTypes.Insets = value.textInsets or {}
	return types.UDim2.new(
		size.X.Scale,
		math.max(size.X.Offset, math.ceil(fit.X) + (inset.left or 0) + (inset.right or 0)),
		size.Y.Scale,
		math.max(size.Y.Offset, math.ceil(fit.Y) + (inset.top or 0) + (inset.bottom or 0))
	)
end

local function skin(
	Compose: typeof(ComposeTypes),
	runtime: ComposeTypes.Runtime,
	packageOrReadable: Engine.Value<ThemeTypes.ThemePackage>?,
	slot: string,
	options: ThemeTypes.SkinOptions?
): Frame
	local settings: ThemeTypes.SkinOptions = options or {}
	local types, Host = typesFor(settings), (runtime.constructors :: unknown) :: Engine.Host
	local D2, V2 = types.UDim2, types.Vector2
	if not Compose.isReadable(packageOrReadable) and type(packageOrReadable) ~= "function" then
		local package = read(packageOrReadable) or neutral
		local chrome = package.chrome
		local recipe = if chrome then chrome[slot] else nil
		if recipe == nil or recipe.kind == "native" or recipe.kind == "none" then
			local root = Host.Frame "Skin" {
				Size = settings.Size or D2.fromScale(1, 1),
				AnchorPoint = settings.AnchorPoint or V2.new(0, 0),
				Position = settings.Position or D2.fromScale(0, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = settings.ZIndex or 0,
			}
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
					return Host.UIShadow "ChromeShadow" {
						Color = color(types, shadow.color or { r = 0, g = 0, b = 0 }),
						Transparency = shadow.transparency or 0.5,
						ZIndex = shadow.zIndex or -1,
						Enabled = shadow.enabled ~= false,
						BlurRadius = types.UDim.new(axis(shadow.blurRadius)),
						Offset = pair(shadow.offset),
						Spread = pair(shadow.spread),
					}
				end, settings.target or root)
			end
			return decoration(Compose, runtime, types, settings.target, root) :: Frame
		end
	end
	type CompiledLayers = {
		package: ThemeTypes.ThemePackage,
		state: ThemeTypes.SkinState,
		selected: boolean,
		direction: string?,
		fit: number?,
		layers: { ImageLayer },
	}
	local compiled: { CompiledLayers } = {}
	local overText = settings.target ~= nil and settings.target:IsA("TextBox")
	local function buildLayers(use: ComposeTypes.Use): { ImageLayer }
		local package = read(packageOrReadable, use) or neutral
		local chrome = package.chrome
		local recipe = if chrome then chrome[slot] else nil
		if recipe == nil or recipe.kind == "native" or recipe.kind == "none" or overText then
			return {}
		end
		local state = (read(settings.state, use) or "default") :: ThemeTypes.SkinState
		local selected = read(settings.selected, use) == true
		local direction = if slot == "barCap" then read(settings.direction, use) or "ltr" else nil
		local fit = read(settings.fit, use)
		for _, cached in compiled do
			if
				cached.package == package
				and cached.state == state
				and cached.selected == selected
				and cached.direction == direction
				and cached.fit == fit
			then
				return cached.layers
			end
		end
		local output: { ImageLayer } = {}
		local function finish(): { ImageLayer }
			if deeplyFrozen(package, {}) then
				local snapshot: CompiledLayers = {
					package = package,
					state = state :: ThemeTypes.SkinState,
					selected = selected,
					direction = direction,
					fit = fit,
					layers = output,
				}
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
			local assetName, link = variantAsset(source or layer.asset, state :: ThemeTypes.SkinState, selected)
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
				Rotation = link.rotation or 0,
				ImageColor3 = color(types, link.tint) or types.Color3.new(1, 1, 1),
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
			local vertical = direction == "ttb" or direction == "btt"
			local scale = fit or 1
			if scale <= 0 then
				return finish()
			end
			local box = D2.fromOffset(math.round(size.w * scale), math.round(size.h * scale))
			if slot == "barCenter" then
				image(recipe, "barCenter", box, D2.fromScale(0.5, 0.5), V2.new(0.5, 0.5))
			else
				local reverse = direction == "rtl" or direction == "btt"
				for _, endpoint in { "start", "end" } do
					local position = if (endpoint == "end") ~= reverse then 1 else 0
					local at = V2.new(if vertical then 0.5 else position, if vertical then position else 0.5)
					image(
						recipe,
						"barCap-" .. endpoint,
						box,
						D2.fromScale(at.X, at.Y),
						at,
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
					if asset or layer.asset then
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
				local reach = (if horizontal then size.h else size.w) / 2 - overhang
				local offset = if endPoint then -reach else reach
				local position = if horizontal
					then D2.new(0.5, 0, if endPoint then 1 else 0, offset)
					else D2.new(if endPoint then 1 else 0, offset, 0.5, 0)
				image(layer, name, D2.fromOffset(size.w, size.h), position, V2.new(0.5, 0.5))
			else
				image(layer, name)
			end
		end
		return finish()
	end
	local target = settings.target
	local function labelled(use: ComposeTypes.Use?): boolean
		local label = settings.label
		return label ~= nil and (read(label, use) or "") ~= ""
	end
	local function createImage(initial: ImageLayer): MountedImage
		local shown = not initial.text or labelled()
		local properties: Engine.ImageLabelNativeProps = {
			Name = initial.id,
			Visible = shown,
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
			Rotation = initial.Rotation,
			ImageColor3 = initial.ImageColor3,
		}
		local captionSource: ComposeTypes.Cell<ImageLayer>?
		local fit = Compose.cell(V2.new(0, 0))
		if settings.label then
			local current = Compose.cell(initial)
			captionSource = current
			table.insert(
				properties,
				Compose.show(function(use: ComposeTypes.Use)
					return use(current).text == true and labelled(use)
				end, function()
					local padding: Engine.UIPaddingNativeProps = {
						PaddingLeft = function(use: ComposeTypes.Use)
							local inset: ThemeTypes.Insets = use(current).textInsets or {}
							return types.UDim.new(0, inset.left or 0)
						end,
						PaddingRight = function(use: ComposeTypes.Use)
							local inset: ThemeTypes.Insets = use(current).textInsets or {}
							return types.UDim.new(0, inset.right or 0)
						end,
						PaddingTop = function(use: ComposeTypes.Use)
							local inset: ThemeTypes.Insets = use(current).textInsets or {}
							return types.UDim.new(0, inset.top or 0)
						end,
						PaddingBottom = function(use: ComposeTypes.Use)
							local inset: ThemeTypes.Insets = use(current).textInsets or {}
							return types.UDim.new(0, inset.bottom or 0)
						end,
					}
					local label = Host.TextLabel "PlaqueCaption" {
						Text = settings.label,
						Size = D2.fromScale(1, 1),
						BackgroundTransparency = 1,
						ZIndex = 1,
						TextXAlignment = types.Enum.TextXAlignment.Center,
						Host.UIPadding(padding),
					}
					label:AddTag("facet-skin-caption-text")
					local observation = runtime.host.observation
					if observation then
						Compose.cleanup(observation.observeProperty(label, "TextBounds", function()
							fit:set(label.TextBounds)
						end))
					end
					fit:set(label.TextBounds)
					Compose.cleanup(function()
						fit:set(V2.new(0, 0))
					end)
					return label
				end)
			)
		end
		local node = Host.ImageLabel(properties)
		node:AddTag("facet-skin-art")
		node:AddTag("facet-skin-art-" .. slot)
		if captionSource then
			local current = captionSource
			Compose.watch(function(use: ComposeTypes.Use)
				local size = grown(types, use(current), use(fit))
				if node.Size ~= size then
					node.Size = size
				end
			end)
		end
		return { node = node, properties = initial, caption = captionSource, visible = shown }
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
			if value.Rotation ~= previous.Rotation then
				node.Rotation = value.Rotation
			end
			if value.ImageColor3 ~= previous.ImageColor3 then
				node.ImageColor3 = value.ImageColor3
			end
			local caption = record.caption
			if caption and value ~= previous then
				caption:set(value)
			end
			record.properties = value
		end
	end
	local activeLayers: { ImageLayer } = {}
	local slots: ComposeTypes.Cell<{ number }> = Compose.cell({})
	local mounted: { [number]: MountedImage } = {}
	local root = Host.Frame "Skin" {
		Size = settings.Size or D2.fromScale(1, 1),
		AnchorPoint = settings.AnchorPoint or V2.new(0, 0),
		Position = settings.Position or D2.fromScale(0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = settings.ZIndex or 0,
		Compose.keyed({
			from = slots,
			render = function(current: ComposeTypes.Readable<number>)
				local index = current:peek()
				local record = createImage(activeLayers[index])
				mounted[index] = record
				Compose.cleanup(function()
					mounted[index] = nil
				end)
				return record.node
			end,
		}),
	}
	Compose.watch(function(use: ComposeTypes.Use)
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
		local titled = labelled(use)
		for index, record in mounted do
			local layer = active[index]
			applyImage(record, layer, layer ~= nil and (not layer.text or titled))
		end
		local plaque = false
		for _, layer in active do
			if layer.text and titled then
				plaque = true
			end
		end
		if settings.onCaption then
			settings.onCaption(plaque)
		end
		if target then
			if #active > 0 then
				target:AddTag("facet-skinned")
			else
				target:RemoveTag("facet-skinned")
			end
			if plaque then
				target:AddTag("facet-skin-caption")
			else
				target:RemoveTag("facet-skin-caption")
			end
		end
	end)
	local shadow = Compose.formula(function(use: ComposeTypes.Use)
		local package = read(packageOrReadable, use) or neutral
		local chrome = package.chrome
		local recipe = if chrome then chrome[slot] else nil
		local value = if recipe then recipe.shadow else nil
		if type(value) == "string" then
			value = (package.style.shadows or {})[value] or shadowPresets[value]
			assert(value ~= nil, "Facet theme unknown shadow preset")
		end
		return value
	end)
	local previousShadow: ThemeTypes.Shadow?
	local retainedShadow = Compose.formula(function(use: ComposeTypes.Use): ThemeTypes.Shadow?
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
					Color = function(use: ComposeTypes.Use)
						return color(
								types,
								(use(retainedShadow) :: ThemeTypes.Shadow).color or { r = 0, g = 0, b = 0 }
							) :: Color3
					end,
					Transparency = function(use: ComposeTypes.Use)
						return (use(retainedShadow) :: ThemeTypes.Shadow).transparency or 0.5
					end,
					ZIndex = function(use: ComposeTypes.Use)
						return (use(retainedShadow) :: ThemeTypes.Shadow).zIndex or -1
					end,
					Enabled = function(use: ComposeTypes.Use)
						local current = use(shadow)
						return current ~= nil and (current :: ThemeTypes.Shadow).enabled ~= false
					end,
					BlurRadius = function(use: ComposeTypes.Use)
						return types.UDim.new(axis((use(retainedShadow) :: ThemeTypes.Shadow).blurRadius))
					end,
					Offset = function(use: ComposeTypes.Use)
						return pair((use(retainedShadow) :: ThemeTypes.Shadow).offset)
					end,
					Spread = function(use: ComposeTypes.Use)
						return pair((use(retainedShadow) :: ThemeTypes.Shadow).spread)
					end,
				}
				return Host.UIShadow(properties)
			end),
		}
	end, settings.target or root)
	return decoration(Compose, runtime, types, settings.target, root) :: Frame
end

local bound: { [typeof(ComposeTypes)]: ThemeTypes.Themes } = {}
setmetatable(bound, { __mode = "k" })

return function(Compose: typeof(ComposeTypes)): ThemeTypes.Themes
	local cached = bound[Compose]
	if cached then
		return cached
	end
	local surface: ThemeTypes.Themes = {
		SCHEMA = themes.SCHEMA,
		TYPE_ROLES = themes.TYPE_ROLES,
		REQUIRED_TYPE_ROLES = themes.REQUIRED_TYPE_ROLES,
		neutralPackage = themes.neutralPackage,
		forDistance = themes.forDistance,
		define = themes.define,
		checkCoverage = themes.checkCoverage,
		resolveIcon = themes.resolveIcon,
		createStyleSheet = function(
			runtime: ComposeTypes.Runtime,
			packageOrReadable: Engine.Value<ThemeTypes.ThemePackage>?,
			options: ThemeTypes.ThemeOptions?
		): StyleSheet
			return createStyleSheet(Compose, runtime, packageOrReadable, options)
		end,
		skin = function(
			runtime: ComposeTypes.Runtime,
			packageOrReadable: Engine.Value<ThemeTypes.ThemePackage>?,
			slot: string,
			options: ThemeTypes.SkinOptions?
		): Frame
			return skin(Compose, runtime, packageOrReadable, slot, options)
		end,
	}
	bound[Compose] = surface
	return surface
end
