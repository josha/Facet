--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local gallery = require("../examples/gallery/client/screen")
local Compose = Facet.Compose
local themes = Facet.themes

type Harness = {
	engine: any,
	runtime: any,
	UI: any,
	Host: any,
	gui: any,
	dispose: () -> (),
}

local function harness(options: { [string]: any }?): Harness
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local config: { [string]: any } = { types = engine.types, guiService = gui, services = { GuiService = gui } }
	for key, value in (options or {}) :: { [string]: any } do
		config[key] = value
	end
	local UI = Facet.controls(runtime, config :: any)
	return {
		engine = engine,
		runtime = runtime,
		UI = UI,
		Host = runtime.constructors,
		gui = gui,
		dispose = function()
			runtime:dispose()
		end,
	}
end

local function mount(h: Harness, build: () -> any): (any, () -> ())
	local stop, root = h.runtime.mount(function()
		return h.Host.Frame({ build() })
	end, h.engine.new("ScreenGui"))
	return root, stop
end

local function sheetFor(h: Harness, package: any, options: { [string]: any }?): (any, () -> ())
	local settings: { [string]: any } = { types = h.engine.types, preferredTransparency = 1, reducedMotion = false }
	for key, value in (options or {}) :: { [string]: any } do
		settings[key] = value
	end
	local stop, sheet = h.runtime.mount(function()
		return themes.createStyleSheet(h.runtime, package, settings :: any)
	end, h.engine.new("Folder"))
	return sheet, stop
end

local function style(sheet: any, selector: string): { [string]: any }
	local found
	for _, node in sheet:GetChildren() do
		if node.Selector == selector then
			found = node
		end
	end
	assert(found, "No rule: " .. selector)
	return found:GetProperties()
end

local function find(root: any, name: string): any
	if root.Name == name then
		return root
	end
	for _, child in root:GetChildren() do
		local found = find(child, name)
		if found then
			return found
		end
	end
	return nil
end

local function skinned(h: Harness, package: any, slot: string, state: any?): (any, () -> ())
	local stop, node = h.runtime.mount(function()
		return themes.skin(h.runtime, package, slot, { types = h.engine.types, state = state })
	end, h.engine.new("Folder"))
	return node, stop
end

local function images(node: any): { any }
	local out = {}
	for _, child in node:GetDescendants() do
		if child.ClassName == "ImageLabel" and child.Visible then
			table.insert(out, child)
		end
	end
	table.sort(out, function(a, b)
		return a.Name < b.Name
	end)
	return out
end

local REFERENCE = {
	"classic_desktop",
	"compact_pointer",
	"fantasy_ornate",
	"fantasy_parchment",
	"glossy_mobile",
	"glossy_touch",
	"pixel_quest",
	"scifi_hud",
}

local function reference(name: string): (any, any)
	local module: any = (require :: any)("../examples/themes/" .. name)
	local package, report = module.build(themes)
	assert(report.ok, name .. " did not build")
	return package, module
end

local function same(left: any, right: any): boolean
	return math.abs(left.r - right.r) < 1e-6 and math.abs(left.g - right.g) < 1e-6 and math.abs(left.b - right.b) < 1e-6
end

local function luminance(value: any): number
	local function linear(channel: number): number
		return if channel <= 0.04045 then channel / 12.92 else ((channel + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * linear(value.r) + 0.7152 * linear(value.g) + 0.0722 * linear(value.b)
end

local function contrast(first: any, second: any): number
	local a, b = luminance(first), luminance(second)
	return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05)
end

t.describe("native parity themes", function()
	t.it("derives unauthored strong and numeral roles from the package face", function()
		for _, name in REFERENCE do
			local package, module = reference(name)
			local authored = module.definition(themes).metrics.typography
			local typography = package.metrics.typography
			for role, base in { strong = "body", numeral = "control" } do
				t.expect(authored[role]).toBe(nil)
				t.expect(typography[role].font.family).toBe(typography[base].font.family)
				t.expect(typography[role].font.style).toBe(typography[base].font.style)
				t.expect(typography[role].size).toBe(typography[base].size)
				t.expect(typography[role].lineHeight).toBe(typography[base].lineHeight)
				t.expect(typography[role].font.weight).toBe(if role == "strong" then "SemiBold" else "Bold")
			end
		end
		local definition = themes.neutralPackage()
		definition.identity.id = "authored"
		definition.metrics.typography.body = { size = 15, font = { family = "rbxassetid://5" } }
		definition.metrics.typography.strong = { size = 21, font = { family = "rbxassetid://6", weight = "Heavy" } }
		local package = assert(themes.define(definition))
		t.expect(package.metrics.typography.strong.size).toBe(21)
		t.expect(package.metrics.typography.strong.font.family).toBe("rbxassetid://6")
		t.expect(package.metrics.typography.numeral.size).toBe(18)
		local neutral = assert(themes.define({ identity = { id = "plain" } }))
		t.expect(neutral.metrics.typography.strong.font.weight).toBe("SemiBold")
		t.expect(neutral.metrics.typography.numeral.font.weight).toBe("Bold")
		t.expect(neutral.metrics.typography.numeral.font.family).toBe("BuilderSans")
		local derived = assert(themes.define({ base = package, identity = { id = "derived" } }))
		t.expect(derived.metrics.typography.strong.size).toBe(21)
		local h = harness()
		local faced = reference("fantasy_parchment")
		local sheet, stop = sheetFor(h, faced)
		t.expect(style(sheet, ".facet-type-strong").FontFace.Family).toBe(faced.metrics.typography.body.font.family)
		t.expect(style(sheet, ".facet-type-numeral").TextSize).toBe(faced.metrics.typography.control.size)
		stop()
		h.dispose()
	end)

	t.it("authors circular and spinner metrics in every reference package across a twofold span", function()
		local neutral = themes.neutralPackage().metrics.controls.progress
		local extremes = { circularSize = { math.huge, 0 }, spinnerDotSize = { math.huge, 0 } }
		for _, name in REFERENCE do
			local package, module = reference(name)
			local authored = module.definition(themes).metrics.controls.progress
			local progress = package.metrics.controls.progress
			local differs = false
			for _, field in { "circularSize", "circularThickness", "spinnerDotSize" } do
				t.expect(type(authored[field])).toBe("number")
				t.expect(progress[field] > 0).toBe(true)
				t.expect(progress[field]).toBe(authored[field])
				differs = differs or progress[field] ~= neutral[field]
			end
			t.expect(differs).toBe(true)
			for field, range in extremes do
				range[1] = math.min(range[1], progress[field])
				range[2] = math.max(range[2], progress[field])
			end
			local h = harness({ theme = package })
			local root, stop = mount(h, function()
				return h.Host.Frame({
					h.UI.ProgressView({ Name = "Ring", presentation = "circular", value = 0.5 }),
					h.UI.ProgressView({ Name = "Dots", presentation = "spinner" }),
				})
			end)
			t.expect(find(find(root, "Ring"), "Indicator").Size.X.Offset).toBe(progress.circularSize)
			t.expect(find(find(root, "Ring"), "RingFill").Thickness)
				.toBe(math.max(progress.circularThickness, math.round(progress.circularSize * 0.08)))
			t.expect(find(find(root, "Dots"), "Segment1").Size.X.Offset).toBe(progress.spinnerDotSize)
			stop()
			h.dispose()
		end
		for _, range in extremes do
			t.expect(range[2] / range[1] >= 2).toBe(true)
		end
	end)

	t.it("answers the progress metrics from neutral for a package that authors none", function()
		local stub = (require :: any)("../examples/themes/fantasy_parchment_stub")
		t.expect(stub.definition(themes).metrics.controls).toBe(nil)
		local package, report = stub.build(themes)
		t.expect(report.ok).toBe(true)
		local h = harness({ theme = package })
		local root, stop = mount(h, function()
			return h.Host.Frame({
				h.UI.ProgressView({ Name = "Ring", presentation = "circular", value = 0.25 }),
				h.UI.ProgressView({ Name = "Dots", presentation = "spinner" }),
			})
		end)
		t.expect(find(find(root, "Ring"), "Indicator").Size.X.Offset).toBe(32)
		t.expect(find(find(root, "Ring"), "RingTrack").Thickness).toBe(3)
		t.expect(find(find(root, "Dots"), "Segment1").Size.X.Offset).toBe(4)
		stop()
		h.dispose()
	end)

	t.it("resolves content and contentId to the same skin and icon image", function()
		local module = (require :: any)("../examples/themes/content_alias_test")
		local resolved = {}
		for _, build in { module.build, module.buildAlias } do
			local package, report = build(themes)
			t.expect(report.ok).toBe(true)
			local h = harness({ theme = package })
			local node, stop = skinned(h, package, "control")
			local root, stopIcon = mount(h, function()
				return h.UI.Label({ text = "Up", icon = "increment" })
			end)
			local skin = images(node)
			t.expect(#skin).toBe(1)
			local icon = root:FindFirstChildWhichIsA("ImageLabel", true)
			table.insert(resolved, { skin[1].Image, icon.Image, themes.resolveIcon(package, "increment") })
			stopIcon()
			stop()
			h.dispose()
		end
		t.expect(resolved[1][1]).toBe("rbxassetid://70509734376718")
		t.expect(resolved[1][2]).toBe("rbxassetid://137937473154830")
		for index = 1, 3 do
			t.expect(resolved[2][index]).toBe(resolved[1][index])
		end
	end)

	t.it("refuses an unknown text role and follows a bound role", function()
		local h = harness()
		local ok, message = pcall(function()
			mount(h, function()
				return h.UI.Label({ text = "x", textRole = "huge" })
			end)
		end)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(message), "textRole", 1, true) ~= nil).toBe(true)
		local role = Compose.cell("caption")
		local root, stop = mount(h, function()
			return h.UI.Label({ Name = "Bound", text = "x", textRole = role })
		end)
		t.expect(find(root, "Bound"):HasTag("facet-type-caption")).toBe(true)
		local refused = pcall(function()
			role:set("huge" :: any)
		end)
		t.expect(refused).toBe(false)
		stop()
		h.dispose()
	end)

	t.it("inherits unrestated base values in a derived package and gates it as strictly", function()
		local basis = themes.neutralPackage()
		basis.identity.id = "b"
		basis.metrics.radii.control = 3
		basis.metrics.space.m = 11
		local base = assert(themes.define(basis))
		local derived, report =
			themes.define({ base = base, identity = { id = "d" }, metrics = { radii = { panel = 20 } } })
		t.expect(report.ok).toBe(true)
		assert(derived)
		t.expect(derived.identity.id).toBe("d")
		t.expect(derived.metrics.radii.control).toBe(3)
		t.expect(derived.metrics.radii.panel).toBe(20)
		t.expect(derived.metrics.space.m).toBe(11)
		t.expect(derived.metrics.typography.body.size).toBe(16)
		t.expect(table.isfrozen(derived.metrics)).toBe(true)
		t.expect(table.isfrozen(derived.metrics.radii)).toBe(true)
		t.expect(base.metrics.radii.panel).toBe(12)
		local surface = base.style.themes[1].colors.surface
		local unreadable, refusal = themes.define({
			base = base,
			identity = { id = "x" },
			style = {
				themes = { { name = "Dark", colors = { content = { r = surface.r, g = surface.g, b = surface.b } } } },
			},
		})
		t.expect(unreadable).toBe(nil)
		t.expect(refusal.ok).toBe(false)
		local named = false
		for _, issue in refusal.errors do
			named = named or string.find(issue.message, "contrast", 1, true) ~= nil
		end
		t.expect(named).toBe(true)
		local selectedFill, selectedRefusal = themes.define({
			base = base,
			identity = { id = "y" },
			style = { themes = { { name = "Dark", extra = { controlSelected = { r = 0.9, g = 0.9, b = 0.92 } } } } },
		})
		t.expect(selectedFill).toBe(nil)
		t.expect(selectedRefusal.ok).toBe(false)
		t.expect((select(2, themes.define({ base = 5 :: any, identity = { id = "z" } }))).ok).toBe(false)
	end)

	t.it("rejects non-finite theme numbers with the field path", function()
		for _, value in { 0 / 0, math.huge, -math.huge } do
			local definition = themes.neutralPackage()
			definition.metrics.space.m = value
			local package, report = themes.define(definition)
			t.expect(package).toBe(nil)
			t.expect(report.ok).toBe(false)
			t.expect(report.errors[1].field).toBe("package.metrics.space.m")
			t.expect(report.errors[1].message).toBe("Theme numbers must be finite")
		end
		local color = themes.neutralPackage()
		color.style.themes[1].colors.accent = { r = 0 / 0, g = 0, b = 0 }
		local _, report = themes.define(color)
		t.expect(report.ok).toBe(false)
		t.expect(report.errors[1].field).toBe("package.style.themes.1.colors.accent.r")
		local cyclic: any = themes.neutralPackage()
		cyclic.rules = { { selector = ".x", properties = {} } }
		cyclic.rules[1].properties.self = cyclic.rules
		local _, cycle = themes.define(cyclic)
		t.expect(cycle.ok).toBe(false)
		t.expect(cycle.errors[1].message).toBe("Theme packages cannot contain cycles")
	end)

	t.it("terminates on a self-referential metrics table and rejects it as a cycle", function()
		for _, shape in { "self", "nested" } do
			local definition: any = themes.neutralPackage()
			if shape == "self" then
				definition.metrics.self = definition.metrics
			else
				local loop: any = {}
				loop.self = loop
				definition.metrics.controlSizes.cycle = loop
			end
			local package, report = themes.define(definition)
			t.expect(package).toBe(nil)
			t.expect(report.ok).toBe(false)
			local found = false
			for _, entry in report.errors do
				found = found or entry.message == "Theme packages cannot contain cycles"
			end
			t.expect(found).toBe(true)
		end
	end)

	t.it("slices the slider rail and paints a sliced = false thumb as a whole image", function()
		local definition = themes.neutralPackage()
		definition.identity.id = "sliced-slider"
		definition.assets = {
			a = { content = "rbxassetid://1", sliceCenter = { x0 = 4, y0 = 4, x1 = 12, y1 = 12 } },
		}
		definition.chrome.sliderTrack = { kind = "nineSlice", asset = "a" }
		definition.chrome.sliderThumb = { kind = "nineSlice", asset = "a", sliced = false }
		local package, report = themes.define(definition)
		t.expect(report.ok).toBe(true)
		local h = harness({ theme = package })
		local root, stop = mount(h, function()
			return h.UI.Slider({ Name = "Volume", value = Compose.cell(0.5) })
		end)
		local Enum = h.engine.types.Enum
		local rail = find(root, "sliderTrack1")
		local thumb = find(root, "sliderThumb1")
		t.expect(rail.Image).toBe("rbxassetid://1")
		t.expect(thumb.Image).toBe("rbxassetid://1")
		t.expect(rail.ScaleType).toBe(Enum.ScaleType.Slice)
		t.expect(rail.SliceCenter).toBe(h.engine.types.Rect.new(4, 4, 12, 12))
		t.expect(thumb.ScaleType).toBe(Enum.ScaleType.Stretch)
		t.expect(thumb.SliceCenter).toBe(h.engine.types.Rect.new(0, 0, 0, 0))
		stop()
		h.dispose()
	end)

	t.it("paints omitted semantic pairs from the neutral fallbacks in every palette", function()
		local neutral = themes.neutralPackage().style.themes[1].colors
		local definition = {
			identity = { id = "two-variant" },
			style = {
				defaultTheme = "Dark",
				themes = {
					{
						name = "Dark",
						colors = {
							surface = { r = 0.05, g = 0.05, b = 0.08 },
							content = { r = 0.95, g = 0.95, b = 0.95 },
						},
					},
					{
						name = "Light",
						colors = { surface = { r = 1, g = 1, b = 1 }, content = { r = 0, g = 0, b = 0 } },
						extra = { controlSelected = { r = 0.8, g = 0.85, b = 0.95 } },
					},
				},
			},
		}
		local package, report = themes.define(definition :: any)
		t.expect(report.ok).toBe(true)
		local inherited, inheritedReport = themes.define({ base = package, identity = { id = "derived-one" } })
		t.expect(inheritedReport.ok).toBe(true)
		t.expect(#inherited.style.themes).toBe(1)
		t.expect(inherited.style.themes[1].name).toBe("Dark")
		local derived, derivedReport = themes.define({
			base = package,
			identity = { id = "derived-two" },
			style = { themes = package.style.themes },
		} :: any)
		t.expect(derivedReport.ok).toBe(true)
		t.expect(#derived.style.themes).toBe(2)
		local h = harness()
		for _, candidate in { package, derived } do
			for _, name in { "Dark", "Light" } do
				local sheet, stop = sheetFor(h, candidate, { theme = name })
				local function expectRole(selector: string, property: string, role: string)
					local value = neutral[role]
					t.expect(style(sheet, selector)[property])
						.toBe(h.engine.types.Color3.new(value.r, value.g, value.b))
				end
				expectRole(".facet-status-success", "BackgroundColor3", "success")
				expectRole(".facet-status-success", "TextColor3", "onSuccess")
				expectRole(".facet-status-warning", "BackgroundColor3", "warning")
				expectRole(".facet-status-warning", "TextColor3", "onWarning")
				expectRole(".facet-status-error", "BackgroundColor3", "danger")
				expectRole(".facet-role-destructive >> .facet-button-caption", "TextColor3", "onDanger")
				expectRole(".facet-accent", "BackgroundColor3", "accent")
				local surface = if name == "Dark" then { 0.05, 0.05, 0.08 } else { 1, 1, 1 }
				t.expect(style(sheet, ".facet-surface").BackgroundColor3)
					.toBe(h.engine.types.Color3.new(surface[1], surface[2], surface[3]))
				stop()
			end
		end
		h.dispose()
	end)

	t.it(
		"falls back to default art for unstated states and ranks disabled over pressed over hover over selected",
		function()
			local package = themes.neutralPackage()
			package.assets = {
				rest = { content = "rbxassetid://1" },
				hot = { content = "rbxassetid://2" },
				press = { content = "rbxassetid://3" },
				chosen = { content = "rbxassetid://4" },
				off = { content = "rbxassetid://5" },
			}
			package.chrome.control =
				{ kind = "nineSlice", asset = { default = "rest", pressed = "press", disabled = "off" } }
			local h = harness({ theme = package })
			local enabled, selected = Compose.cell(true), Compose.cell(false)
			local root, stop = mount(h, function()
				return h.UI.Button({ Name = "Skinned", label = "x", enabled = enabled, selected = selected })
			end)
			local button = find(root, "Skinned")
			local art = find(button, "control1")
			local GuiState = h.engine.types.Enum.GuiState
			t.expect(art.Image).toBe("rbxassetid://1")
			button.GuiState = GuiState.Hover
			t.expect(art.Image).toBe("rbxassetid://1")
			selected:set(true)
			t.expect(art.Image).toBe("rbxassetid://1")
			button.GuiState = GuiState.Press
			t.expect(art.Image).toBe("rbxassetid://3")
			enabled:set(false)
			t.expect(art.Image).toBe("rbxassetid://5")
			stop()
			h.dispose()

			local full = themes.neutralPackage()
			full.assets = package.assets
			full.chrome.control = {
				kind = "nineSlice",
				asset = { default = "rest", hover = "hot", pressed = "press", selected = "chosen", disabled = "off" },
			}
			local ranked = harness({ theme = full })
			local enabledAgain, selectedAgain = Compose.cell(true), Compose.cell(true)
			local rankedRoot, stopRanked = mount(ranked, function()
				return ranked.UI.Button({
					Name = "Ranked",
					label = "x",
					enabled = enabledAgain,
					selected = selectedAgain,
				})
			end)
			local rankedButton = find(rankedRoot, "Ranked")
			local rankedArt = find(rankedButton, "control1")
			t.expect(rankedArt.Image).toBe("rbxassetid://4")
			rankedButton.GuiState = GuiState.Hover
			t.expect(rankedArt.Image).toBe("rbxassetid://2")
			rankedButton.GuiState = GuiState.Press
			t.expect(rankedArt.Image).toBe("rbxassetid://3")
			enabledAgain:set(false)
			t.expect(rankedArt.Image).toBe("rbxassetid://5")
			rankedButton.GuiState = GuiState.Idle
			t.expect(rankedArt.Image).toBe("rbxassetid://5")
			enabledAgain:set(true)
			t.expect(rankedArt.Image).toBe("rbxassetid://4")
			stopRanked()
			ranked.dispose()
		end
	)

	t.it("shows the derived default art in a state the derived package no longer declares", function()
		local basis = themes.neutralPackage()
		basis.assets = {
			a = { content = "rbxassetid://11" },
			p = { content = "rbxassetid://12" },
			c = { content = "rbxassetid://13" },
		}
		basis.chrome.control = { kind = "nineSlice", asset = { default = "a", pressed = "p" } }
		local base = assert(themes.define(basis))
		local derived = assert(themes.define({
			base = base,
			identity = { id = "d" },
			chrome = { control = { kind = "nineSlice", asset = { default = "c" } } },
		}))
		t.expect(derived.chrome.control.asset.pressed).toBe(nil)
		local h = harness()
		local state = Compose.cell("pressed")
		local node, stop = skinned(h, derived, "control", state)
		t.expect(images(node)[1].Image).toBe("rbxassetid://13")
		state:set("default")
		t.expect(images(node)[1].Image).toBe("rbxassetid://13")
		stop()
		local baseNode, stopBase = skinned(h, base, "control", Compose.cell("pressed"))
		t.expect(images(baseNode)[1].Image).toBe("rbxassetid://12")
		stopBase()
		h.dispose()
	end)

	t.it("exercises every declared theme class of each reference package against neutral", function()
		local neutral = themes.neutralPackage()
		local neutralColors = neutral.style.themes[1].colors
		local h = harness()
		local classes = {}
		for _, name in REFERENCE do
			local package, module = reference(name)
			t.expect(#module.themeClasses > 0).toBe(true)
			for _, class in module.themeClasses do
				classes[class] = true
				if class == "palette" then
					for _, palette in package.style.themes do
						local differs = 0
						for role, value in neutralColors do
							if not same((palette.colors or {})[role] or value, value) then
								differs += 1
							end
						end
						t.expect(differs >= 4).toBe(true)
					end
				elseif class == "metrics" then
					local metrics = package.metrics
					t.expect(
						metrics.space.m ~= neutral.metrics.space.m
							or metrics.controlSizes.regular.height ~= neutral.metrics.controlSizes.regular.height
							or metrics.radii.control ~= neutral.metrics.radii.control
					).toBe(true)
					t.expect(
						metrics.typography.body.size ~= neutral.metrics.typography.body.size
							or metrics.radii.panel ~= neutral.metrics.radii.panel
					).toBe(true)
				elseif class == "font" then
					local differs = false
					for role, entry in package.metrics.typography do
						local plain = neutral.metrics.typography[role]
						local family = entry.font.family or "BuilderSans"
						differs = differs
							or (family ~= "BuilderSans" and family ~= "rbxasset://fonts/families/BuilderSans.json")
							or (entry.font.weight or "Regular") ~= plain.font.weight
					end
					t.expect(differs).toBe(true)
				elseif class == "assets" then
					local declared = 0
					for _ in package.assets do
						declared += 1
					end
					t.expect(declared > 0).toBe(true)
				else
					error(name .. " declares unknown theme class " .. class)
				end
			end
			local art = 0
			for _, recipe in package.chrome do
				if
					recipe.kind ~= "native"
					and recipe.kind ~= "none"
					and recipe.kind ~= "glow"
					and recipe.kind ~= "ring"
				then
					art += 1
				end
			end
			t.expect(art > 0).toBe(table.find(module.themeClasses, "assets") ~= nil)
		end
		for _, class in { "palette", "metrics", "font", "assets" } do
			t.expect(classes[class]).toBe(true)
		end
		local classic = reference("classic_desktop")
		t.expect(#classic.style.themes).toBe(2)
		local day, stopDay = sheetFor(h, classic, { theme = "Day" })
		local night, stopNight = sheetFor(h, classic, { theme = "Night" })
		t.expect(style(day, ".facet-surface").BackgroundColor3 ~= style(night, ".facet-surface").BackgroundColor3)
			.toBe(true)
		t.expect(style(day, ".facet-text").TextColor3 ~= style(night, ".facet-text").TextColor3).toBe(true)
		t.expect(style(day, ".facet-text").TextSize).toBe(style(night, ".facet-text").TextSize)
		t.expect(style(day, ".facet-text").FontFace).toBe(style(night, ".facet-text").FontFace)
		t.expect(style(day, ".facet-button::UICorner").CornerRadius)
			.toBe(style(night, ".facet-button::UICorner").CornerRadius)
		stopDay()
		stopNight()
		for _, dense in { "classic_desktop", "compact_pointer" } do
			local compact = reference(dense)
			for _, touch in { "glossy_mobile", "glossy_touch" } do
				local rounded = reference(touch)
				t.expect(compact.metrics.controlSizes.regular.height < rounded.metrics.controlSizes.regular.height)
					.toBe(true)
				t.expect(compact.metrics.typography.body.size < rounded.metrics.typography.body.size).toBe(true)
				t.expect(compact.metrics.radii.control < rounded.metrics.radii.control).toBe(true)
				t.expect(compact.metrics.space.m < rounded.metrics.space.m).toBe(true)
			end
		end
		for _, touch in { "glossy_mobile", "glossy_touch" } do
			t.expect(reference(touch).metrics.controlSizes.regular.height >= 44).toBe(true)
		end
		for _, palette in reference("scifi_hud").style.themes do
			t.expect(contrast(palette.colors.content, palette.colors.surface) >= 7).toBe(true)
		end
		local pixel = reference("pixel_quest")
		t.expect(pixel.identity.rendering).toBe("pixel")
		local node, stop = skinned(h, pixel, "control")
		t.expect(#images(node) > 0).toBe(true)
		for _, image in images(node) do
			t.expect(image.ResampleMode).toBe(h.engine.types.Enum.ResamplerMode.Pixelated)
		end
		stop()
		h.dispose()
	end)

	t.it("names declared rbxassetid assets in every chrome and icon recipe", function()
		local function names(source: any, out: { string })
			if type(source) == "string" then
				table.insert(out, source)
			elseif type(source) == "table" then
				if source.asset ~= nil then
					names(source.asset, out)
				else
					for _, value in source do
						names(value, out)
					end
				end
			end
		end
		local walked = 0
		for _, name in
			{
				"fantasy_parchment_stub",
				"fantasy_parchment",
				"fantasy_ornate",
				"pixel_quest",
				"glossy_touch",
				"compact_pointer",
			}
		do
			local module: any = (require :: any)("../examples/themes/" .. name)
			local package, report = module.build(themes)
			t.expect(report.ok).toBe(true)
			local referenced: { string } = {}
			for _, recipe in package.chrome do
				if
					recipe.kind == "native"
					or recipe.kind == "none"
					or recipe.kind == "glow"
					or recipe.kind == "ring"
				then
					continue
				end
				names(recipe.asset, referenced)
				names(recipe.startAsset, referenced)
				names(recipe.endAsset, referenced)
				for _, layer in recipe.layers or {} do
					names(layer.asset, referenced)
					for _, corner in { "topLeft", "topRight", "bottomLeft", "bottomRight" } do
						names(layer[corner], referenced)
					end
				end
			end
			for _, entry in package.icons or {} do
				names(entry, referenced)
			end
			t.expect(#referenced > 0).toBe(true)
			for _, asset in referenced do
				local declared = package.assets[asset]
				if declared == nil then
					error(`{name} names undeclared asset {asset}`)
				end
				local content = declared.content or declared.contentId
				t.expect(type(content) == "string" and string.sub(content, 1, 13) == "rbxassetid://").toBe(true)
				walked += 1
			end
		end
		t.expect(walked > 40).toBe(true)
	end)

	t.it("compiles and skins a full stack when a declared asset is bogus", function()
		local ornate: any = (require :: any)("../examples/themes/fantasy_ornate")
		local good = assert(ornate.build(themes))
		local bad, report = ornate.buildBadLayer(themes)
		t.expect(report.ok).toBe(true)
		t.expect(bad.assets[ornate.BROKEN_ASSET].content).toBe(ornate.BOGUS_CONTENT_ID)
		local h = harness()
		local goodNode, stopGood = skinned(h, good, "panel")
		local badNode, stopBad = skinned(h, bad, "panel")
		local goodImages, badImages = images(goodNode), images(badNode)
		t.expect(#badImages).toBe(#goodImages)
		t.expect(#badImages > 1).toBe(true)
		local broken = good.assets[ornate.BROKEN_ASSET].content
		local replaced = 0
		for index, image in badImages do
			t.expect(image.Name).toBe(goodImages[index].Name)
			if goodImages[index].Image == broken then
				replaced += 1
				t.expect(image.Image).toBe(ornate.BOGUS_CONTENT_ID)
			else
				t.expect(image.Image).toBe(goodImages[index].Image)
			end
		end
		t.expect(replaced > 0).toBe(true)
		stopGood()
		stopBad()
		h.dispose()
		local stub: any = (require :: any)("../examples/themes/fantasy_parchment_stub")
		local missing, missingReport = stub.buildBadAsset(themes)
		t.expect(missingReport.ok).toBe(true)
		local themed = harness({ theme = missing })
		local root, stop = mount(themed, function()
			return themed.Host.Frame({
				themed.UI.Button({ Name = "Action", label = "Continue" }),
				themed.UI.Sheet({
					isPresented = Compose.cell(true),
					detent = Compose.cell("medium"),
					title = "Panel",
					content = function()
						return themed.Host.Frame({})
					end,
				}),
			})
		end)
		local button = find(root, "Action")
		t.expect(button.Text).toBe("Continue")
		t.expect(button:HasTag("facet-skinned")).toBe(true)
		local panelArt = false
		for _, node in themed.engine.made do
			if node.ClassName == "ImageLabel" and node.Image == stub.BOGUS_CONTENT_ID and not node:isDestroyed() then
				panelArt = true
			end
		end
		t.expect(panelArt).toBe(true)
		stop()
		themed.dispose()
	end)

	t.it("declares distinct success and warning pairs in every reference palette", function()
		for _, name in REFERENCE do
			local _, module = reference(name)
			for _, palette in module.definition(themes).style.themes do
				local colors = palette.colors
				for _, role in { "success", "onSuccess", "warning", "onWarning" } do
					t.expect(type(colors[role])).toBe("table")
				end
				t.expect(same(colors.success, colors.accent)).toBe(false)
				t.expect(same(colors.warning, colors.content)).toBe(false)
				t.expect(same(colors.success, colors.warning)).toBe(false)
				t.expect(contrast(colors.onSuccess, colors.success) >= 4.5).toBe(true)
				t.expect(contrast(colors.onWarning, colors.warning) >= 4.5).toBe(true)
			end
		end
	end)

	t.it("pairs touch and pointer metrics, hover art and the tile stripe", function()
		local touch, touchModule = reference("glossy_touch")
		local pointer, pointerModule = reference("compact_pointer")
		t.expect(touchModule.pairRole).toBe("touch")
		t.expect(pointerModule.pairRole).toBe("pointer")
		t.expect(touch.metrics.controlSizes.regular.height).toBe(44)
		t.expect(touch.metrics.controlSizes.compact.height >= 44).toBe(true)
		t.expect(pointer.metrics.controlSizes.regular.height).toBe(24)
		t.expect(pointer.metrics.controlSizes.compact.height).toBe(22)
		t.expect(pointer.metrics.space.m < touch.metrics.space.m).toBe(true)
		t.expect(pointer.metrics.typography.body.size < touch.metrics.typography.body.size).toBe(true)
		t.expect(pointer.metrics.radii.panel < touch.metrics.radii.panel).toBe(true)
		t.expect(pointer.chrome.control.asset.hover ~= nil).toBe(true)
		t.expect(touch.chrome.control.asset.hover).toBe(nil)
		local stripe = touch.chrome.barTrack.layers[2]
		t.expect(stripe.kind).toBe("tile")
		t.expect(stripe.tileSize.w).toBe(24)
		t.expect(stripe.tileSize.h).toBe(24)
		t.expect(pointer.chrome.barTrack.kind).toBe("nineSlice")
		local h = harness()
		local Tile = h.engine.types.Enum.ScaleType.Tile
		local touchNode, stopTouch = skinned(h, touch, "barTrack")
		local tiles = 0
		for _, image in images(touchNode) do
			if image.ScaleType == Tile then
				tiles += 1
				t.expect(image.TileSize).toBe(h.engine.types.UDim2.fromOffset(24, 24))
			end
		end
		t.expect(tiles).toBe(1)
		local pointerNode, stopPointer = skinned(h, pointer, "barTrack")
		for _, image in images(pointerNode) do
			t.expect(image.ScaleType ~= Tile).toBe(true)
		end
		local hover = Compose.cell("hover")
		local hoverNode, stopHover = skinned(h, pointer, "control", hover)
		t.expect(images(hoverNode)[1].Image).toBe(pointer.assets[pointer.chrome.control.asset.hover].content)
		local touchHover, stopTouchHover = skinned(h, touch, "control", hover)
		t.expect(images(touchHover)[1].Image).toBe(touch.assets[touch.chrome.control.asset.default].content)
		stopTouch()
		stopPointer()
		stopHover()
		stopTouchHover()
		h.dispose()
	end)

	t.it("loads only shipping theme package modules from the gallery theme folder", function()
		local engine: any = engineLib.new()
		local modules = {}
		local names = {
			"classic_desktop",
			"compact_pointer",
			"content_alias_test",
			"custom_control",
			"fantasy_ornate",
			"fantasy_parchment",
			"fantasy_parchment_stub",
			"glossy_mobile",
			"glossy_touch",
			"layered_test",
			"ornate_gauge",
			"pixel_quest",
			"scifi_hud",
		}
		for _, name in names do
			local module = engine.new("ModuleScript")
			module.Name = name
			table.insert(modules, module)
		end
		local folder = engine.new("Folder")
		folder.Name = "Nested"
		table.insert(modules, folder)
		local broken = engine.new("ModuleScript")
		broken.Name = "broken"
		table.insert(modules, broken)
		local loaded = gallery.themePackages(themes, modules, function(module: any): any
			if module.Name == "broken" then
				error("broken module")
			end
			return (require :: any)("../examples/themes/" .. module.Name)
		end)
		local found = {}
		for name, package in loaded do
			table.insert(found, name)
			t.expect(table.isfrozen(package)).toBe(true)
		end
		table.sort(found)
		t.expect(found).toEqual(REFERENCE)
		t.expect(#loaded.fantasy_ornate.style.themes).toBe(2)
	end)

	t.it("lists Neutral first then names, keeps the installed package on reselection and selects a palette", function()
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local target, gui = engine.new("Folder"), engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.PreferredInput = engine.types.Enum.PreferredInput.Gamepad
		input.GetFocusedTextBox = function()
			return nil
		end
		local neutral = themes.neutralPackage()
		local alpha = themes.neutralPackage()
		alpha.identity.id = "alpha"
		alpha.identity.displayName = "Alpha"
		alpha.style.defaultTheme = "Dawn"
		alpha.style.themes[1].name = "Dawn"
		local dusk = table.clone(alpha.style.themes[1])
		dusk.name = "Dusk"
		alpha.style.themes = { alpha.style.themes[1], dusk }
		local zeta = themes.neutralPackage()
		zeta.identity.id = "zeta"
		zeta.identity.displayName = "Zeta"
		local ctx: any = {
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = runtime.constructors,
			types = engine.types,
			viewport = Compose.cell({ width = 1280, height = 720 }),
			inputTarget = target,
			guiService = gui,
			runService = { Heartbeat = engine.heartbeat },
			selection = Compose.cell("first"),
			theme = Compose.cell(neutral),
			themeMode = Compose.cell("Dark"),
			packages = { Neutral = neutral, Zeta = zeta, Alpha = alpha },
			demos = { { id = "first", title = "First", kind = "fixture", module = "first" } },
			load = function()
				return {
					build = function(page: any)
						return {
							screen = function()
								return page.Host.Frame({ Name = "FirstPage" })
							end,
						}
					end,
				}
			end,
		}
		local writes = 0
		local stop, root = runtime.mount(function()
			gallery.configure(ctx)
			ctx.UI = Facet.controls(
				runtime,
				{
					types = engine.types,
					inputParent = target,
					services = { GuiService = gui, UserInputService = input },
					theme = ctx.theme,
					reducedMotion = ctx.reducedMotion,
				} :: any
			)
			Compose.watch(function(use)
				use(ctx.theme)
				writes += 1
			end)
			return ctx.Host.ScreenGui("GalleryTest")({ gallery.build(ctx) })
		end, target)
		local function choices(picker: any): { string }
			local out = {}
			for _, node in picker:GetDescendants() do
				if node:IsA("TextButton") and node:GetAttribute("FacetLabel") ~= nil then
					table.insert(out, node)
				end
			end
			table.sort(out, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			local labels = {}
			for _, node in out do
				table.insert(labels, node:GetAttribute("FacetLabel"))
			end
			return labels
		end
		find(root, "Settings").Activated.fire()
		local picker = find(root, "Theme")
		t.expect(choices(picker)).toEqual({ "Facet Neutral", "Alpha", "Zeta" })
		t.expect(choices(find(root, "Mode"))).toEqual({ "Dark", "Light" })
		local initialWrites = writes
		find(picker, "Alpha").Activated.fire()
		t.expect(ctx.theme:peek()).toBe(alpha)
		t.expect(ctx.themeName:peek()).toBe("Alpha")
		t.expect(ctx.themeMode:peek()).toBe("Dawn")
		t.expect(writes).toBe(initialWrites + 1)
		local mode = find(root, "Mode")
		t.expect(choices(mode)).toEqual({ "Dawn", "Dusk" })
		find(mode, "Dusk").Activated.fire()
		t.expect(ctx.themeMode:peek()).toBe("Dusk")
		t.expect(ctx.theme:peek()).toBe(alpha)
		find(find(root, "Theme"), "Alpha").Activated.fire()
		t.expect(ctx.themeMode:peek()).toBe("Dusk")
		t.expect(ctx.theme:peek()).toBe(alpha)
		t.expect(writes).toBe(initialWrites + 1)
		find(find(root, "Theme"), "Zeta").Activated.fire()
		t.expect(ctx.theme:peek()).toBe(zeta)
		t.expect(ctx.themeMode:peek()).toBe("Dark")
		t.expect(choices(find(root, "Mode"))).toEqual({ "Dark", "Light" })
		find(find(root, "Mode"), "Light").Activated.fire()
		t.expect(ctx.themeMode:peek()).toBe("Light")
		t.expect(ctx.theme:peek()).toBe(zeta)
		stop()
		runtime:dispose()
	end)
end)
