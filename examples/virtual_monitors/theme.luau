--!strict
local theme = {}
local function rgb(r, g, b)
	return { r = r / 255, g = g / 255, b = b / 255 }
end
function theme.create(Facet: any, name: string)
	local function palette(dark)
		local accent = if name == "Discover"
			then (if dark then rgb(144, 220, 190) else rgb(45, 86, 65))
			elseif dark then rgb(192, 172, 255)
			else rgb(91, 70, 140)
		return {
			name = if dark then "Dark" else "Light",
			colors = {
				surface = if dark then rgb(18, 17, 26) else rgb(243, 240, 233),
				surfaceStrong = if dark then rgb(32, 30, 44) else rgb(255, 255, 255),
				content = if dark then rgb(233, 229, 244) else rgb(45, 46, 42),
				contentStrong = if dark then rgb(255, 253, 255) else rgb(26, 32, 29),
				accent = accent,
				onAccent = if dark then rgb(28, 22, 46) else rgb(255, 255, 255),
				danger = if dark then rgb(255, 166, 166) else rgb(161, 39, 46),
				onDanger = if dark then rgb(42, 15, 15) else rgb(255, 255, 255),
			},
			extra = {
				-- Paint feedback keeps labels at their authored size.
				pressedScale = 1,
				control = if dark then rgb(58, 54, 80) else rgb(232, 230, 223),
				controlHover = if dark then rgb(74, 68, 100) else rgb(222, 221, 212),
				controlPressed = if dark then rgb(86, 78, 114) else rgb(211, 214, 203),
				controlSelected = accent,
				onSelected = if dark then rgb(28, 22, 46) else rgb(255, 255, 255),
				contentSecondary = if dark then rgb(174, 168, 188) else rgb(102, 105, 94),
				hairline = if dark then rgb(66, 61, 88) else rgb(189, 191, 178),
			},
		}
	end
	local typography = {}
	for role, size in { caption = 13, label = 16, body = 19, control = 17, heading = 25, title = 34 } do
		typography[role] =
			{ font = { family = "rbxasset://fonts/families/BuilderSans.json" }, size = size, lineHeight = 1.25 }
	end
	typography.title.font.weight = "Bold"
	typography.heading.font.weight = "SemiBold"
	return Facet.themes.define({
		base = Facet.themes.neutralPackage(),
		identity = {
			id = "virtual-monitors-" .. string.lower(name),
			displayName = "Virtual Monitors / " .. name,
			schemaVersion = Facet.themes.SCHEMA,
			version = "1.0.0",
		},
		style = { defaultTheme = "Dark", themes = { palette(false), palette(true) } },
		metrics = {
			motion = { fast = 0.12, normal = 0.32 },
			typography = typography,
			space = { xs = 4, s = 8, m = 14, l = 22, xl = 32 },
			radii = { control = 12, panel = 18, pill = 999 },
		},
	})
end

-- Theme changes animate paint only. Layout, focus and content stay live, and
-- the host disables these native transitions for reduced motion.
function theme.sheet(controller: any, package: any, displaySize: string)
	local model = controller.sheetModelFor(package, displaySize)
	for _, rule in model.rules do
		-- Panels here wear `surfaceStrong`, which is also the slider thumb's
		-- stock colour; the thumb takes the strong content colour so it reads.
		if
			type(rule.selector) == "string"
			and string.find(rule.selector, "facet-slot-sliderThumb", 1, true)
			and rule.props.BackgroundColor3 ~= nil
		then
			rule.props.BackgroundColor3 = "$ContentStrong"
		end
		for property in rule.props do
			if
				property == "BackgroundColor3"
				or property == "TextColor3"
				or property == "ImageColor3"
				or property == "Color"
			then
				rule.transitions = rule.transitions or {}
				rule.transitions[property] = rule.transitions[property] or "normal"
			end
		end
	end
	return model
end
return theme
