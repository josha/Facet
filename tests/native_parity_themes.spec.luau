--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type MotionLevel = typeof(require("@repo/tools/typecheck/aliases").MotionLevel)
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T
	local ThemeTypes = require("../src/ui/theme_types")

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local gallery = require("../examples/gallery/client/screen")
	local Compose: ComposeModule = Facet.Compose
	local themes = Facet.themes

	type Harness = {
		engine: any,
		runtime: any,
		UI: any,
		Host: any,
		gui: any,
		dispose: () -> (),
	}

	local function openSettings(root: any)
		local function seek(node: any, name: string): any
			if node.Name == name then
				return node
			end
			for _, child in node:GetChildren() do
				local found = seek(child, name)
				if found then
					return found
				end
			end
			return nil
		end
		local layer = root:FindFirstAncestorWhichIsA("LayerCollector") or root
		seek(layer, "Showcase").Activated:Fire()
		seek(seek(layer, "Section"), "settings").Activated:Fire()
	end
	local function harness(options: { [string]: any }?): Harness
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
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
			Host = (runtime.constructors :: unknown) :: RobloxHost,
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
		local settings: { [string]: any } =
			{ types = h.engine.types, preferredTransparency = 1, motionLevel = "normal" }
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
		return math.abs(left.r - right.r) < 1e-6
			and math.abs(left.g - right.g) < 1e-6
			and math.abs(left.b - right.b) < 1e-6
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

	verifyHarness:suite("native parity themes", function()
		verifyHarness:case("derives unauthored strong and numeral roles from the package face", {
			id = "native_parity_themes::native parity themes::derives unauthored strong and numeral roles from the package face",
			run = function()
				for _, name in REFERENCE do
					local package, module = reference(name)
					local authored = module.definition(themes).metrics.typography
					local typography = package.metrics.typography
					for role, base in { strong = "body", numeral = "control" } do
						Verify.expect(authored[role]):toBe(nil)
						Verify.expect(typography[role].font.family):toBe(typography[base].font.family)
						Verify.expect(typography[role].font.style):toBe(typography[base].font.style)
						Verify.expect(typography[role].size):toBe(typography[base].size)
						Verify.expect(typography[role].lineHeight):toBe(typography[base].lineHeight)
						Verify.expect(typography[role].font.weight)
							:toBe(if role == "strong" then "SemiBold" else "Bold")
					end
				end
				local definition = themes.neutralPackage()
				definition.identity.id = "authored"
				definition.metrics.typography.body = { size = 15, font = { family = "rbxassetid://5" } }
				definition.metrics.typography.strong =
					{ size = 21, font = { family = "rbxassetid://6", weight = "Heavy" } }
				local package = assert(themes.define(definition))
				Verify.expect(package.metrics.typography.strong.size):toBe(21)
				Verify.expect((package.metrics.typography.strong.font :: ThemeTypes.FontSpec).family)
					:toBe("rbxassetid://6")
				Verify.expect(package.metrics.typography.numeral.size):toBe(18)
				local neutral = assert(themes.define({ identity = { id = "plain" } }))
				Verify.expect((neutral.metrics.typography.strong.font :: ThemeTypes.FontSpec).weight):toBe("SemiBold")
				Verify.expect((neutral.metrics.typography.numeral.font :: ThemeTypes.FontSpec).weight):toBe("Bold")
				Verify.expect((neutral.metrics.typography.numeral.font :: ThemeTypes.FontSpec).family)
					:toBe("BuilderSans")
				local derived = assert(themes.define({ base = package, identity = { id = "derived" } }))
				Verify.expect(derived.metrics.typography.strong.size):toBe(21)
				local h = harness()
				local faced = reference("fantasy_parchment")
				local sheet, stop = sheetFor(h, faced)
				Verify.expect(style(sheet, ".facet-type-strong").FontFace.Family)
					:toBe(faced.metrics.typography.body.font.family)
				Verify.expect(style(sheet, ".facet-type-numeral").TextSize):toBe(faced.metrics.typography.control.size)
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("authors circular and spinner metrics in every reference package across a twofold span", {
			id = "native_parity_themes::native parity themes::authors circular and spinner metrics in every reference package across a twofold span",
			run = function()
				local neutral = themes.neutralPackage().metrics.controls.progress
				local extremes: { [string]: { typeof(math.huge) | number } } =
					{ circularSize = { math.huge, 0 }, spinnerDotSize = { math.huge, 0 } }
				for _, name in REFERENCE do
					local package, module = reference(name)
					local authored = module.definition(themes).metrics.controls.progress
					local progress = package.metrics.controls.progress
					local differs = false
					for _, field in { "circularSize", "circularThickness", "spinnerDotSize" } do
						Verify.expect((type(authored[field]))):toBe("number")
						Verify.expect(progress[field] > 0):toBe(true)
						Verify.expect(progress[field]):toBe(authored[field])
						differs = differs or progress[field] ~= neutral[field]
					end
					Verify.expect(differs):toBe(true)
					for field, range in extremes do
						range[1] = math.min(range[1], progress[field])
						range[2] = math.max(range[2], progress[field])
					end
					local h = harness({ theme = package })
					local root, stop = mount(h, function()
						return h.Host.Frame({
							h.UI.ProgressView({ Name = "Ring", presentation = "circular" :: "circular", value = 0.5 }) :: unknown,
							h.UI.ProgressView({ Name = "Dots", presentation = "spinner" :: "spinner" }),
						})
					end)
					Verify.expect(find(find(root, "Ring"), "Indicator").Size.X.Offset):toBe(progress.circularSize)
					Verify.expect(find(find(root, "Ring"), "RingFill").Thickness)
						:toBe(math.max(progress.circularThickness, math.round(progress.circularSize * 0.08)))
					Verify.expect(find(find(root, "Dots"), "Segment1").Size.X.Offset):toBe(progress.spinnerDotSize)
					stop()
					h.dispose()
				end
				for _, range in extremes do
					Verify.expect(range[2] / range[1] >= 2):toBe(true)
				end
			end,
		})

		verifyHarness:case("answers the progress metrics from neutral for a package that authors none", {
			id = "native_parity_themes::native parity themes::answers the progress metrics from neutral for a package that authors none",
			run = function()
				local stub = (require :: any)("../examples/themes/fantasy_parchment_stub")
				Verify.expect(stub.definition(themes).metrics.controls):toBe(nil)
				local package, report = stub.build(themes)
				Verify.expect(report.ok):toBe(true)
				local h = harness({ theme = package })
				local root, stop = mount(h, function()
					return h.Host.Frame({
						h.UI.ProgressView({ Name = "Ring", presentation = "circular" :: "circular", value = 0.25 }) :: unknown,
						h.UI.ProgressView({ Name = "Dots", presentation = "spinner" :: "spinner" }),
					})
				end)
				Verify.expect(find(find(root, "Ring"), "Indicator").Size.X.Offset):toBe(32)
				Verify.expect(find(find(root, "Ring"), "RingTrack").Thickness):toBe(3)
				Verify.expect(find(find(root, "Dots"), "Segment1").Size.X.Offset):toBe(4)
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("resolves content and contentId to the same skin and icon image", {
			id = "native_parity_themes::native parity themes::resolves content and contentId to the same skin and icon image",
			run = function()
				local module = (require :: any)("../examples/themes/content_alias_test")
				local resolved = {}
				for _, build in { module.build, module.buildAlias } do
					local package, report = build(themes)
					Verify.expect(report.ok):toBe(true)
					local h = harness({ theme = package })
					local node, stop = skinned(h, package, "control")
					local root, stopIcon = mount(h, function()
						return h.UI.Label({ title = "Up", icon = "increment" })
					end)
					local skin = images(node)
					Verify.expect(#skin):toBe(1)
					local icon = root:FindFirstChildWhichIsA("ImageLabel", true)
					table.insert(resolved, { skin[1].Image, icon.Image, themes.resolveIcon(package, "increment") })
					stopIcon()
					stop()
					h.dispose()
				end
				Verify.expect(resolved[1][1]):toBe("rbxassetid://70509734376718")
				Verify.expect(resolved[1][2]):toBe("rbxassetid://137937473154830")
				for index = 1, 3 do
					Verify.expect(resolved[2][index]):toBe(resolved[1][index])
				end
			end,
		})

		verifyHarness:case("refuses an unknown text role and follows a bound role", {
			id = "native_parity_themes::native parity themes::refuses an unknown text role and follows a bound role",
			run = function()
				local h = harness()
				local ok, message = pcall(function()
					mount(h, function()
						return h.UI.Text({ text = "x", textRole = "huge" :: "huge" })
					end)
				end)
				Verify.expect(ok):toBe(false)
				Verify.expect(string.find(tostring(message), "textRole", 1, true) ~= nil):toBe(true)
				local role = Compose.cell("caption")
				local root, stop = mount(h, function()
					return h.UI.Text({ Name = "Bound", text = "x", textRole = role })
				end)
				Verify.expect((find(root, "Bound"):HasTag("facet-type-caption"))):toBe(true)
				local refused = pcall(function()
					role:set("huge" :: any)
				end)
				Verify.expect(refused):toBe(false)
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("inherits unrestated base values in a derived package and gates it as strictly", {
			id = "native_parity_themes::native parity themes::inherits unrestated base values in a derived package and gates it as strictly",
			run = function()
				local basis = themes.neutralPackage()
				basis.identity.id = "b"
				basis.metrics.radii.control = 3
				basis.metrics.space.m = 11
				local base = assert(themes.define(basis))
				local derived, report =
					themes.define({ base = base, identity = { id = "d" }, metrics = { radii = { panel = 20 } } })
				Verify.expect(report.ok):toBe(true)
				assert(derived)
				Verify.expect(derived.identity.id):toBe("d")
				Verify.expect(derived.metrics.radii.control):toBe(3)
				Verify.expect(derived.metrics.radii.panel):toBe(20)
				Verify.expect(derived.metrics.space.m):toBe(11)
				Verify.expect(derived.metrics.typography.body.size):toBe(16)
				Verify.expect((table.isfrozen(derived.metrics))):toBe(true)
				Verify.expect((table.isfrozen(derived.metrics.radii))):toBe(true)
				Verify.expect(base.metrics.radii.panel):toBe(12)
				local surface = base.style.themes[1].colors.surface
				local unreadable, refusal = themes.define({
					base = base,
					identity = { id = "x" },
					style = {
						themes = {
							{ name = "Dark", colors = { content = { r = surface.r, g = surface.g, b = surface.b } } },
						},
					},
				} :: any)
				Verify.expect(unreadable):toBe(nil)
				Verify.expect(refusal.ok):toBe(false)
				local named = false
				for _, issue in refusal.errors do
					named = named or string.find(issue.message, "contrast", 1, true) ~= nil
				end
				Verify.expect(named):toBe(true)
				local selectedFill, selectedRefusal = themes.define({
					base = base,
					identity = { id = "y" },
					style = {
						themes = { { name = "Dark", extra = { controlSelected = { r = 0.9, g = 0.9, b = 0.92 } } } },
					},
				})
				Verify.expect(selectedFill):toBe(nil)
				Verify.expect(selectedRefusal.ok):toBe(false)
				Verify.expect((select(2, themes.define({ base = 5 :: any, identity = { id = "z" } }))).ok):toBe(false)
			end,
		})

		verifyHarness:case("rejects non-finite theme numbers with the field path", {
			id = "native_parity_themes::native parity themes::rejects non-finite theme numbers with the field path",
			run = function()
				for _, value in { 0 / 0, math.huge, -math.huge } do
					local definition = themes.neutralPackage()
					definition.metrics.space.m = value
					local package, report = themes.define(definition)
					Verify.expect(package):toBe(nil)
					Verify.expect(report.ok):toBe(false)
					Verify.expect(report.errors[1].field):toBe("package.metrics.space.m")
					Verify.expect(report.errors[1].message):toBe("Theme numbers must be finite")
				end
				local color = themes.neutralPackage()
				color.style.themes[1].colors.accent = { r = 0 / 0, g = 0, b = 0 }
				local _, report = themes.define(color)
				Verify.expect(report.ok):toBe(false)
				Verify.expect(report.errors[1].field):toBe("package.style.themes.1.colors.accent.r")
				local cyclic: any = themes.neutralPackage()
				cyclic.rules = { { selector = ".x", properties = {} } }
				cyclic.rules[1].properties.self = cyclic.rules
				local _, cycle = themes.define(cyclic)
				Verify.expect(cycle.ok):toBe(false)
				Verify.expect(cycle.errors[1].message):toBe("Theme packages cannot contain cycles")
			end,
		})

		verifyHarness:case("terminates on a self-referential metrics table and rejects it as a cycle", {
			id = "native_parity_themes::native parity themes::terminates on a self-referential metrics table and rejects it as a cycle",
			run = function()
				for _, shape in { "self", "nested" } :: { "nested" | "self" } do
					local definition: any = themes.neutralPackage()
					if shape == "self" then
						definition.metrics.self = definition.metrics
					else
						local loop: any = {}
						loop.self = loop
						definition.metrics.controlSizes.cycle = loop
					end
					local package, report = themes.define(definition)
					Verify.expect(package):toBe(nil)
					Verify.expect(report.ok):toBe(false)
					local found = false
					for _, entry in report.errors do
						found = found or entry.message == "Theme packages cannot contain cycles"
					end
					Verify.expect(found):toBe(true)
				end
			end,
		})

		verifyHarness:case("slices the slider rail and paints a sliced = false thumb as a whole image", {
			id = "native_parity_themes::native parity themes::slices the slider rail and paints a sliced = false thumb as a whole image",
			run = function()
				local definition = themes.neutralPackage()
				definition.identity.id = "sliced-slider"
				definition.assets = {
					a = { content = "rbxassetid://1", sliceCenter = { x0 = 4, y0 = 4, x1 = 12, y1 = 12 } },
				}
				assert(definition.chrome).sliderTrack = { kind = "nineSlice" :: "nineSlice", asset = "a" }
				assert(definition.chrome).sliderThumb =
					{ kind = "nineSlice" :: "nineSlice", asset = "a", sliced = false }
				local package, report = themes.define(definition)
				Verify.expect(report.ok):toBe(true)
				local h = harness({ theme = package })
				local root, stop = mount(h, function()
					return h.UI.Slider({ Name = "Volume", value = Compose.cell(0.5) })
				end)
				local Enum = h.engine.types.Enum
				local rail = find(root, "sliderTrack1")
				local thumb = find(root, "sliderThumb1")
				Verify.expect(rail.Image):toBe("rbxassetid://1")
				Verify.expect(thumb.Image):toBe("rbxassetid://1")
				Verify.expect(rail.ScaleType):toBe(Enum.ScaleType.Slice)
				Verify.expect(rail.SliceCenter):toBe(h.engine.types.Rect.new(4, 4, 12, 12))
				Verify.expect(thumb.ScaleType):toBe(Enum.ScaleType.Stretch)
				Verify.expect(thumb.SliceCenter):toBe(h.engine.types.Rect.new(0, 0, 0, 0))
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("paints omitted semantic pairs from the neutral fallbacks in every palette", {
			id = "native_parity_themes::native parity themes::paints omitted semantic pairs from the neutral fallbacks in every palette",
			run = function()
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
				Verify.expect(report.ok):toBe(true)
				local inherited, inheritedReport = themes.define({ base = package, identity = { id = "derived-one" } })
				Verify.expect(inheritedReport.ok):toBe(true)
				Verify.expect(#assert(inherited).style.themes):toBe(1)
				Verify.expect(assert(inherited).style.themes[1].name):toBe("Dark")
				local derived, derivedReport = themes.define({
					base = package,
					identity = { id = "derived-two" },
					style = { themes = assert(package).style.themes },
				} :: any)
				Verify.expect(derivedReport.ok):toBe(true)
				Verify.expect(#assert(derived).style.themes):toBe(2)
				local h = harness()
				for _, candidate in { package, derived } do
					for _, name in { "Dark", "Light" } do
						local sheet, stop = sheetFor(h, candidate, { theme = name })
						local function expectRole(selector: string, property: string, role: string)
							local value = neutral[role]
							Verify.expect(style(sheet, selector)[property])
								:toBe(h.engine.types.Color3.new(value.r, value.g, value.b))
						end
						expectRole(".facet-status-success", "BackgroundColor3", "success")
						expectRole(".facet-status-success", "TextColor3", "onSuccess")
						expectRole(".facet-status-warning", "BackgroundColor3", "warning")
						expectRole(".facet-status-warning", "TextColor3", "onWarning")
						expectRole(".facet-status-error", "BackgroundColor3", "danger")
						expectRole(".facet-role-destructive >> .facet-button-caption", "TextColor3", "onDanger")
						expectRole(".facet-accent", "BackgroundColor3", "accent")
						local surface = if name == "Dark" then { 0.05, 0.05, 0.08 } else { 1, 1, 1 }
						Verify.expect(style(sheet, ".facet-surface").BackgroundColor3)
							:toBe(h.engine.types.Color3.new(surface[1], surface[2], surface[3]))
						stop()
					end
				end
				h.dispose()
			end,
		})

		verifyHarness:case(
			"falls back to default art for unstated states and ranks disabled over pressed over hover over selected",
			{
				id = "native_parity_themes::native parity themes::falls back to default art for unstated states and ranks disabled over pressed over hover over selected",
				run = function()
					local package = themes.neutralPackage()
					package.assets = {
						rest = { content = "rbxassetid://1" },
						hot = { content = "rbxassetid://2" },
						press = { content = "rbxassetid://3" },
						chosen = { content = "rbxassetid://4" },
						off = { content = "rbxassetid://5" },
					}
					assert(package.chrome).control = {
						kind = "nineSlice" :: "nineSlice",
						asset = { default = "rest", pressed = "press", disabled = "off" },
					}
					local h = harness({ theme = package })
					local enabled, selected = Compose.cell(true), Compose.cell(false)
					local root, stop = mount(h, function()
						return h.UI.Button({ Name = "Skinned", label = "x", enabled = enabled, selected = selected })
					end)
					local button = find(root, "Skinned")
					local art = find(button, "control1")
					local GuiState = h.engine.types.Enum.GuiState
					Verify.expect(art.Image):toBe("rbxassetid://1")
					button.GuiState = GuiState.Hover
					Verify.expect(art.Image):toBe("rbxassetid://1")
					selected:set(true)
					Verify.expect(art.Image):toBe("rbxassetid://1")
					button.GuiState = GuiState.Press
					Verify.expect(art.Image):toBe("rbxassetid://3")
					enabled:set(false)
					Verify.expect(art.Image):toBe("rbxassetid://5")
					stop()
					h.dispose()

					local full = themes.neutralPackage()
					full.assets = package.assets
					assert(full.chrome).control = {
						kind = "nineSlice" :: "nineSlice",
						asset = {
							default = "rest",
							hover = "hot",
							pressed = "press",
							selected = "chosen",
							disabled = "off",
						},
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
					Verify.expect(rankedArt.Image):toBe("rbxassetid://4")
					rankedButton.GuiState = GuiState.Hover
					Verify.expect(rankedArt.Image):toBe("rbxassetid://2")
					rankedButton.GuiState = GuiState.Press
					Verify.expect(rankedArt.Image):toBe("rbxassetid://3")
					enabledAgain:set(false)
					Verify.expect(rankedArt.Image):toBe("rbxassetid://5")
					rankedButton.GuiState = GuiState.Idle
					Verify.expect(rankedArt.Image):toBe("rbxassetid://5")
					enabledAgain:set(true)
					Verify.expect(rankedArt.Image):toBe("rbxassetid://4")
					stopRanked()
					ranked.dispose()
				end,
			}
		)

		verifyHarness:case("shows the derived default art in a state the derived package no longer declares", {
			id = "native_parity_themes::native parity themes::shows the derived default art in a state the derived package no longer declares",
			run = function()
				local basis = themes.neutralPackage()
				basis.assets = {
					a = { content = "rbxassetid://11" },
					p = { content = "rbxassetid://12" },
					c = { content = "rbxassetid://13" },
				}
				assert(basis.chrome).control =
					{ kind = "nineSlice" :: "nineSlice", asset = { default = "a", pressed = "p" } }
				local base = assert(themes.define(basis))
				local derived = assert(themes.define({
					base = base,
					identity = { id = "d" },
					chrome = { control = { kind = "nineSlice" :: "nineSlice", asset = { default = "c" } } },
				} :: ThemeTypes.ThemeDefinition))
				Verify.expect((assert(assert(derived.chrome).control.asset) :: ThemeTypes.AssetVariants).pressed)
					:toBe(nil)
				local h = harness()
				local state = Compose.cell("pressed")
				local node, stop = skinned(h, derived, "control", state)
				Verify.expect(images(node)[1].Image):toBe("rbxassetid://13")
				state:set("default")
				Verify.expect(images(node)[1].Image):toBe("rbxassetid://13")
				stop()
				local baseNode, stopBase = skinned(h, base, "control", Compose.cell("pressed"))
				Verify.expect(images(baseNode)[1].Image):toBe("rbxassetid://12")
				stopBase()
				h.dispose()
			end,
		})

		verifyHarness:case("exercises every declared theme class of each reference package against neutral", {
			id = "native_parity_themes::native parity themes::exercises every declared theme class of each reference package against neutral",
			run = function()
				local neutral = themes.neutralPackage()
				local neutralColors = neutral.style.themes[1].colors
				local h = harness()
				local classes = {}
				for _, name in REFERENCE do
					local package, module = reference(name)
					Verify.expect(#module.themeClasses > 0):toBe(true)
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
								Verify.expect(differs >= 4):toBe(true)
							end
						elseif class == "metrics" then
							local metrics = package.metrics
							Verify.expect(
								metrics.space.m ~= neutral.metrics.space.m
									or metrics.controlSizes.regular.height ~= neutral.metrics.controlSizes.regular.height
									or metrics.radii.control ~= neutral.metrics.radii.control
							):toBe(true)
							Verify.expect(
								metrics.typography.body.size ~= neutral.metrics.typography.body.size
									or metrics.radii.panel ~= neutral.metrics.radii.panel
							):toBe(true)
						elseif class == "font" then
							local differs = false
							for role, entry in package.metrics.typography do
								local plain = neutral.metrics.typography[role]
								local family = entry.font.family or "BuilderSans"
								differs = differs
									or (family ~= "BuilderSans" and family ~= "rbxasset://fonts/families/BuilderSans.json")
									or (entry.font.weight or "Regular")
										~= (plain.font :: ThemeTypes.FontSpec).weight
							end
							Verify.expect(differs):toBe(true)
						elseif class == "assets" then
							local declared = 0
							for _ in package.assets do
								declared += 1
							end
							Verify.expect(declared > 0):toBe(true)
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
					Verify.expect(art > 0):toBe(table.find(module.themeClasses, "assets") ~= nil)
				end
				for _, class in { "palette", "metrics", "font", "assets" } do
					Verify.expect(classes[class]):toBe(true)
				end
				local classic = reference("classic_desktop")
				Verify.expect(#classic.style.themes):toBe(2)
				local day, stopDay = sheetFor(h, classic, { theme = "Day" })
				local night, stopNight = sheetFor(h, classic, { theme = "Night" })
				Verify.expect(
					style(day, ".facet-surface").BackgroundColor3 ~= style(night, ".facet-surface").BackgroundColor3
				)
					:toBe(true)
				Verify.expect(style(day, ".facet-text").TextColor3 ~= style(night, ".facet-text").TextColor3):toBe(true)
				Verify.expect(style(day, ".facet-text").TextSize):toBe(style(night, ".facet-text").TextSize)
				Verify.expect(style(day, ".facet-text").FontFace):toBe(style(night, ".facet-text").FontFace)
				Verify.expect(style(day, ".facet-button::UICorner").CornerRadius)
					:toBe(style(night, ".facet-button::UICorner").CornerRadius)
				stopDay()
				stopNight()
				for _, dense in { "classic_desktop", "compact_pointer" } do
					local compact = reference(dense)
					for _, touch in { "glossy_mobile", "glossy_touch" } do
						local rounded = reference(touch)
						Verify.expect(
							compact.metrics.controlSizes.regular.height < rounded.metrics.controlSizes.regular.height
						)
							:toBe(true)
						Verify.expect(compact.metrics.typography.body.size < rounded.metrics.typography.body.size)
							:toBe(true)
						Verify.expect(compact.metrics.radii.control < rounded.metrics.radii.control):toBe(true)
						Verify.expect(compact.metrics.space.m < rounded.metrics.space.m):toBe(true)
					end
				end
				for _, touch in { "glossy_mobile", "glossy_touch" } do
					Verify.expect(reference(touch).metrics.controlSizes.regular.height >= 44):toBe(true)
				end
				for _, palette in reference("scifi_hud").style.themes do
					Verify.expect(contrast(palette.colors.content, palette.colors.surface) >= 7):toBe(true)
				end
				local pixel = reference("pixel_quest")
				Verify.expect(pixel.identity.rendering):toBe("pixel")
				local node, stop = skinned(h, pixel, "control")
				Verify.expect(#images(node) > 0):toBe(true)
				for _, image in images(node) do
					Verify.expect(image.ResampleMode):toBe(h.engine.types.Enum.ResamplerMode.Pixelated)
				end
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("names declared rbxassetid assets in every chrome and icon recipe", {
			id = "native_parity_themes::native parity themes::names declared rbxassetid assets in every chrome and icon recipe",
			run = function()
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
					Verify.expect(report.ok):toBe(true)
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
					Verify.expect(#referenced > 0):toBe(true)
					for _, asset in referenced do
						local declared = package.assets[asset]
						if declared == nil then
							error(`{name} names undeclared asset {asset}`)
						end
						local content = declared.content or declared.contentId
						Verify.expect(type(content) == "string" and string.sub(content, 1, 13) == "rbxassetid://")
							:toBe(true)
						walked += 1
					end
				end
				Verify.expect(walked > 40):toBe(true)
			end,
		})

		verifyHarness:case("compiles and skins a full stack when a declared asset is bogus", {
			id = "native_parity_themes::native parity themes::compiles and skins a full stack when a declared asset is bogus",
			run = function()
				local ornate: any = (require :: any)("../examples/themes/fantasy_ornate")
				local good = assert(ornate.build(themes))
				local bad, report = ornate.buildBadLayer(themes)
				Verify.expect(report.ok):toBe(true)
				Verify.expect(bad.assets[ornate.BROKEN_ASSET].content):toBe(ornate.BOGUS_CONTENT_ID)
				local h = harness()
				local goodNode, stopGood = skinned(h, good, "panel")
				local badNode, stopBad = skinned(h, bad, "panel")
				local goodImages, badImages = images(goodNode), images(badNode)
				Verify.expect(#badImages):toBe(#goodImages)
				Verify.expect(#badImages > 1):toBe(true)
				local broken = good.assets[ornate.BROKEN_ASSET].content
				local replaced = 0
				for index, image in badImages do
					Verify.expect(image.Name):toBe(goodImages[index].Name)
					if goodImages[index].Image == broken then
						replaced += 1
						Verify.expect(image.Image):toBe(ornate.BOGUS_CONTENT_ID)
					else
						Verify.expect(image.Image):toBe(goodImages[index].Image)
					end
				end
				Verify.expect(replaced > 0):toBe(true)
				stopGood()
				stopBad()
				h.dispose()
				local stub: any = (require :: any)("../examples/themes/fantasy_parchment_stub")
				local missing, missingReport = stub.buildBadAsset(themes)
				Verify.expect(missingReport.ok):toBe(true)
				local themed = harness({ theme = missing })
				local root, stop = mount(themed, function()
					return themed.Host.Frame({
						themed.UI.Button({ Name = "Action", label = "Continue" }) :: unknown,
						themed.UI.Sheet({
							isPresented = Compose.cell(true),
							detent = Compose.cell("medium"),
							title = "Panel",
							content = function(): Instance
								return themed.Host.Frame({})
							end,
						}),
					})
				end)
				local button = find(root, "Action")
				Verify.expect(button.Text):toBe("Continue")
				Verify.expect((button:HasTag("facet-skinned"))):toBe(true)
				local panelArt = false
				for _, node in themed.engine.made do
					if
						node.ClassName == "ImageLabel"
						and node.Image == stub.BOGUS_CONTENT_ID
						and not node:isDestroyed()
					then
						panelArt = true
					end
				end
				Verify.expect(panelArt):toBe(true)
				stop()
				themed.dispose()
			end,
		})

		verifyHarness:case("declares distinct success and warning pairs in every reference palette", {
			id = "native_parity_themes::native parity themes::declares distinct success and warning pairs in every reference palette",
			run = function()
				for _, name in REFERENCE do
					local _, module = reference(name)
					for _, palette in module.definition(themes).style.themes do
						local colors = palette.colors
						for _, role in
							{ "success", "onSuccess", "warning", "onWarning" } :: { "onSuccess" | "onWarning" | "success" | "warning" }
						do
							Verify.expect((type(colors[role]))):toBe("table")
						end
						Verify.expect((same(colors.success, colors.accent))):toBe(false)
						Verify.expect((same(colors.warning, colors.content))):toBe(false)
						Verify.expect((same(colors.success, colors.warning))):toBe(false)
						Verify.expect(contrast(colors.onSuccess, colors.success) >= 4.5):toBe(true)
						Verify.expect(contrast(colors.onWarning, colors.warning) >= 4.5):toBe(true)
					end
				end
			end,
		})

		verifyHarness:case("pairs touch and pointer metrics, hover art and the tile stripe", {
			id = "native_parity_themes::native parity themes::pairs touch and pointer metrics, hover art and the tile stripe",
			run = function()
				local touch, touchModule = reference("glossy_touch")
				local pointer, pointerModule = reference("compact_pointer")
				Verify.expect(touchModule.pairRole):toBe("touch")
				Verify.expect(pointerModule.pairRole):toBe("pointer")
				Verify.expect(touch.metrics.controlSizes.regular.height):toBe(44)
				Verify.expect(touch.metrics.controlSizes.compact.height >= 44):toBe(true)
				Verify.expect(pointer.metrics.controlSizes.regular.height):toBe(24)
				Verify.expect(pointer.metrics.controlSizes.compact.height):toBe(22)
				Verify.expect(pointer.metrics.space.m < touch.metrics.space.m):toBe(true)
				Verify.expect(pointer.metrics.typography.body.size < touch.metrics.typography.body.size):toBe(true)
				Verify.expect(pointer.metrics.radii.panel < touch.metrics.radii.panel):toBe(true)
				Verify.expect(pointer.chrome.control.asset.hover ~= nil):toBe(true)
				Verify.expect(touch.chrome.control.asset.hover):toBe(nil)
				local stripe = touch.chrome.barTrack.layers[2]
				Verify.expect(stripe.kind):toBe("tile")
				Verify.expect(stripe.tileSize.w):toBe(24)
				Verify.expect(stripe.tileSize.h):toBe(24)
				Verify.expect(pointer.chrome.barTrack.kind):toBe("nineSlice")
				local h = harness()
				local Tile = h.engine.types.Enum.ScaleType.Tile
				local touchNode, stopTouch = skinned(h, touch, "barTrack")
				local tiles = 0
				for _, image in images(touchNode) do
					if image.ScaleType == Tile then
						tiles += 1
						Verify.expect(image.TileSize):toBe(h.engine.types.UDim2.fromOffset(24, 24))
					end
				end
				Verify.expect(tiles):toBe(1)
				local pointerNode, stopPointer = skinned(h, pointer, "barTrack")
				for _, image in images(pointerNode) do
					Verify.expect(image.ScaleType ~= Tile):toBe(true)
				end
				local hover = Compose.cell("hover")
				local hoverNode, stopHover = skinned(h, pointer, "control", hover)
				Verify.expect(images(hoverNode)[1].Image)
					:toBe(pointer.assets[pointer.chrome.control.asset.hover].content)
				local touchHover, stopTouchHover = skinned(h, touch, "control", hover)
				Verify.expect(images(touchHover)[1].Image)
					:toBe(touch.assets[touch.chrome.control.asset.default].content)
				stopTouch()
				stopPointer()
				stopHover()
				stopTouchHover()
				h.dispose()
			end,
		})

		verifyHarness:case("loads only shipping theme package modules from the gallery theme folder", {
			id = "native_parity_themes::native parity themes::loads only shipping theme package modules from the gallery theme folder",
			run = function()
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
					Verify.expect((table.isfrozen(package))):toBe(true)
				end
				table.sort(found)
				Verify.expect(found):toEqual(REFERENCE)
				Verify.expect(#loaded.fantasy_ornate.style.themes):toBe(2)
			end,
		})

		verifyHarness:case(
			"lists Neutral first then names, keeps the installed package on reselection and selects a palette",
			{
				id = "native_parity_themes::native parity themes::lists Neutral first then names, keeps the installed package on reselection and selects a palette",
				run = function()
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
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
						Host = (runtime.constructors :: unknown) :: RobloxHost,
						types = engine.types,
						viewport = Compose.cell({ width = 1280, height = 720 }),
						inputTarget = target,
						guiService = gui,
						runService = { Heartbeat = engine.heartbeat },
						selection = Compose.cell("first"),
						theme = Compose.cell(neutral),
						themeMode = Compose.cell("Dark"),
						packages = { Neutral = neutral, Zeta = zeta, Alpha = alpha },
						demos = { { id = "first", title = "First", kind = "fixture" :: "fixture", module = "first" } },
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
					local stop, root: any = runtime.mount(function()
						gallery.configure(ctx)
						ctx.UI = Facet.controls(
							runtime,
							{
								types = engine.types,
								inputParent = target,
								services = { GuiService = gui, UserInputService = input },
								theme = ctx.theme,
								motionLevel = (
										Compose.formula(function(use: Use): "normal" | "limited" | "none"
											return if ctx.reducedMotion and use(ctx.reducedMotion)
												then "none"
												else "normal"
										end) :: unknown
									) :: MotionLevel,
							} :: any
						)
						Compose.watch(function(use: Use)
							use(ctx.theme)
							writes += 1
						end)
						return ctx.Host.ScreenGui("GalleryTest")({ gallery.build(ctx) })
					end, target)
					local function choices(picker: any): { string }
						local out = {}
						for _, node in picker:GetDescendants() do
							if
								node:IsA("TextButton")
								and (node:GetAttribute("FacetLabel") or node:GetAttribute("label")) ~= nil
							then
								table.insert(out, node)
							end
						end
						table.sort(out, function(a, b)
							return a.LayoutOrder < b.LayoutOrder
						end)
						local labels = {}
						for _, node in out do
							table.insert(labels, node:GetAttribute("FacetLabel") or node:GetAttribute("label"))
						end
						return labels
					end
					openSettings(root)
					local picker = find(root, "Packages")
					Verify.expect((choices(picker))):toEqual({ "Facet Neutral", "Alpha", "Zeta" })
					Verify.expect((choices(find(root, "Mode")))):toEqual({ "Dark", "Light" })
					local initialWrites = writes
					find(picker, "P_Alpha").Activated:Fire()
					Verify.expect((ctx.theme:peek())):toBe(alpha)
					Verify.expect((ctx.themeName:peek())):toBe("Alpha")
					Verify.expect((ctx.themeMode:peek())):toBe("Dawn")
					Verify.expect(writes):toBe(initialWrites + 1)
					local mode = find(root, "Mode")
					Verify.expect((choices(mode))):toEqual({ "Dawn", "Dusk" })
					find(mode, "Dusk").Activated:Fire()
					Verify.expect((ctx.themeMode:peek())):toBe("Dusk")
					Verify.expect((ctx.theme:peek())):toBe(alpha)
					find(find(root, "Packages"), "P_Alpha").Activated:Fire()
					Verify.expect((ctx.themeMode:peek())):toBe("Dusk")
					Verify.expect((ctx.theme:peek())):toBe(alpha)
					Verify.expect(writes):toBe(initialWrites + 1)
					find(find(root, "Packages"), "P_Zeta").Activated:Fire()
					Verify.expect((ctx.theme:peek())):toBe(zeta)
					Verify.expect((ctx.themeMode:peek())):toBe("Dark")
					Verify.expect((choices(find(root, "Mode")))):toEqual({ "Dark", "Light" })
					find(find(root, "Mode"), "Light").Activated:Fire()
					Verify.expect((ctx.themeMode:peek())):toBe("Light")
					Verify.expect((ctx.theme:peek())):toBe(zeta)
					stop()
					runtime:dispose()
				end,
			}
		)
	end)
end
