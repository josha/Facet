--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FixtureShadow = typeof(require("@repo/tools/typecheck/aliases").FixtureShadow)
	type Destroyable = typeof(require("@repo/tools/typecheck/aliases").Destroyable)

	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	type ScreenGuiConstructor = typeof(require("@repo/tools/typecheck/aliases").ScreenGuiConstructor)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type MotionLevel = typeof(require("@repo/tools/typecheck/aliases").MotionLevel)
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	local FixtureThemeTypes = require("../src/ui/theme_types")
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local fs = require("@lune/fs")
	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local gallery = require("../examples/gallery/client/screen")
	local themePackages = require("../tools/lune/theme_packages")
	local customControl = require("../examples/themes/custom_control")
	local ornateGauge = require("../examples/themes/ornate_gauge")
	local Compose: ComposeModule = Facet.Compose
	local themes = Facet.themes

	local REFERENCE: { string } = themePackages.REFERENCE_ORDER
	local SHIPPED: { string } = themePackages.shippable()
	local STATES = { "default", "hover", "pressed", "selected", "disabled" }

	local function load(name: string): any
		return (require :: any)("../examples/themes/" .. name)
	end

	local function built(name: string): any
		local package, report = load(name).build(themes)
		assert(package ~= nil and report.ok, name .. " failed its own package gate")
		return package
	end

	local function world(options: { [string]: any }?): (any, any, any, any)
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		local config: { [string]: any } =
			{ types = engine.types, motionLevel = "none", services = { GuiService = gui, UserInputService = input } }
		for key, value in (options or {}) :: { [string]: any } do
			config[key] = value
		end
		local UI = Facet.controls(runtime, config :: any)
		return engine, runtime, UI, gui
	end

	local function sheetFor(engine: any, runtime: any, package: any, options: { [string]: any }?): (any, () -> ())
		local settings: { [string]: any } = { types = engine.types, preferredTransparency = 1, motionLevel = "none" }
		for key, value in (options or {}) :: { [string]: any } do
			settings[key] = value
		end
		local stop, sheet: any = runtime.mount(function()
			return themes.createStyleSheet(runtime, package, settings :: any)
		end, engine.new("Folder"))
		return sheet, stop
	end

	local function ruleNode(sheet: any, selector: string): any
		local found
		for _, node in sheet:GetChildren() do
			if node.Selector == selector then
				found = node
			end
		end
		assert(found, "No rule: " .. selector)
		return found
	end

	local function style(sheet: any, selector: string): { [string]: any }
		return ruleNode(sheet, selector):GetProperties()
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

	local function color(engine: any, value: any): any
		return engine.types.Color3.new(value.r, value.g, value.b)
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

	local function frozenPath(value: any, path: string, seen: { [any]: boolean }): string?
		if type(value) ~= "table" or seen[value] then
			return nil
		end
		seen[value] = true
		if not table.isfrozen(value) then
			return path
		end
		for key, child in value do
			local found = frozenPath(child, path .. "." .. tostring(key), seen)
			if found then
				return found
			end
		end
		return nil
	end

	local function contrastEntries(report: any, pair: string): { any }
		local out = {}
		for _, entry in report.contrast do
			if entry.pair == pair then
				table.insert(out, entry)
			end
		end
		return out
	end

	local function hasError(report: any, field: string, message: string): boolean
		for _, entry in report.errors do
			if entry.field == field and entry.message == message then
				return true
			end
		end
		return false
	end

	local function images(skin: any): { any }
		local out = {}
		for _, child in skin:GetChildren() do
			if child.ClassName == "ImageLabel" and child.Visible then
				table.insert(out, child)
			end
		end
		return out
	end

	local function names(nodes: { any }): string
		local out = {}
		for _, node in nodes do
			table.insert(out, node.Name)
		end
		return table.concat(out, " ")
	end

	local function D2(engine: any, xs: number, xo: number, ys: number, yo: number): any
		return engine.types.UDim2.new(xs, xo, ys, yo)
	end

	local function V2(engine: any, x: number, y: number): any
		return engine.types.Vector2.new(x, y)
	end

	local function skinOf(
		engine: any,
		runtime: any,
		package: any,
		slot: string,
		options: { [string]: any }?
	): (any, () -> ())
		local settings: { [string]: any } = { types = engine.types }
		for key, value in (options or {}) :: { [string]: any } do
			settings[key] = value
		end
		local stop, node: any = runtime.mount(function()
			return themes.skin(runtime, package, slot, settings :: any)
		end, engine.new("Folder"))
		return node, stop
	end

	local function rulesSignature(sheet: any): { string }
		local out = {}
		for _, rule in sheet:GetChildren() do
			local properties = rule:GetProperties()
			local keys = {}
			for key in properties do
				table.insert(keys, key)
			end
			table.sort(keys)
			local parts = { rule.Selector, tostring(rule.Priority) }
			for _, key in keys do
				table.insert(parts, key .. "=" .. tostring(properties[key]))
			end
			table.insert(out, table.concat(parts, "|"))
		end
		return out
	end

	verifyHarness:suite("shipped theme contrast", function()
		verifyHarness:case(
			"pairs every shipped danger plate with a readable onDanger in the report and the destructive rules",
			{
				id = "native_parity_strength_themepkg::shipped theme contrast::pairs every shipped danger plate with a readable onDanger in the report and the destructive rules",
				run = function()
					local engine, runtime = world()
					local checked = 0
					local packages = { { id = "facet-neutral", package = themes.define(themes.neutralPackage()) } }
					for _, name in REFERENCE do
						table.insert(packages, { id = load(name).id, package = built(name) })
					end
					for _, entry in packages do
						local package = entry.package
						local _, report = themes.define(assert(package))
						local entries = contrastEntries(report, "onDanger/danger")
						Verify.expect(#entries):toBe(#assert(package).style.themes)
						for index, palette in assert(package).style.themes do
							local colors = palette.colors
							Verify.expect(contrast(colors.onDanger, colors.danger) >= 4.5):toBe(true)
							Verify.expect(entries[index].ok):toBe(true)
							Verify.expect(
								math.abs(entries[index].ratio - contrast(colors.onDanger, colors.danger)) < 1e-9
							)
								:toBe(true)
							local sheet, stop = sheetFor(engine, runtime, package, { theme = palette.name })
							local destructive = style(sheet, ".facet-role-destructive")
							Verify.expect(destructive.BackgroundColor3):toBe(color(engine, colors.danger))
							Verify.expect(destructive.TextColor3):toBe(color(engine, colors.onDanger))
							Verify.expect(style(sheet, ".facet-role-destructive >> .facet-button-caption").TextColor3)
								:toBe(color(engine, colors.onDanger))
							Verify.expect(style(sheet, ".facet-role-destructive:Press").BackgroundColor3)
								:toBe(color(engine, colors.danger))
							Verify.expect(style(sheet, ".facet-status-error").BackgroundColor3)
								:toBe(color(engine, colors.danger))
							Verify.expect(style(sheet, ".facet-status-error").TextColor3)
								:toBe(color(engine, colors.onDanger))
							stop()
							checked += 1
						end
					end
					Verify.expect(checked):toBe(14)
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("pairs every accent plate with onAccent where the ordinary content color is unreadable", {
			id = "native_parity_strength_themepkg::shipped theme contrast::pairs every accent plate with onAccent where the ordinary content color is unreadable",
			run = function()
				local engine, runtime = world()
				local unreadableContent: { string } = {}
				local packages = { { id = "facet-neutral", package = themes.define(themes.neutralPackage()) } }
				for _, name in REFERENCE do
					table.insert(packages, { id = load(name).id, package = built(name) })
				end
				for _, entry in packages do
					local package = entry.package
					local _, report = themes.define(assert(package))
					local entries = contrastEntries(report, "onAccent/accent")
					Verify.expect(#entries):toBe(#assert(package).style.themes)
					for index, palette in assert(package).style.themes do
						local colors = palette.colors
						local ratio = contrast(colors.onAccent, colors.accent)
						Verify.expect(`{entry.id}/{palette.name}: {if ratio >= 4.5 then "readable" else "unreadable"}`)
							:toBe(`{entry.id}/{palette.name}: readable`)
						Verify.expect(entries[index].ok):toBe(true)
						if contrast(colors.content, colors.accent) < 4.5 then
							table.insert(unreadableContent, `{entry.id}/{palette.name}`)
						end
						local sheet, stop = sheetFor(engine, runtime, package, { theme = palette.name })
						local accent, onAccent = color(engine, colors.accent), color(engine, colors.onAccent)
						Verify.expect(style(sheet, ".facet-accent").BackgroundColor3):toBe(accent)
						Verify.expect(style(sheet, ".facet-accent").TextColor3):toBe(onAccent)
						Verify.expect(style(sheet, ".facet-accent >> .facet-button-caption").TextColor3):toBe(onAccent)
						Verify.expect(style(sheet, ".facet-accent >> .facet-text").TextColor3):toBe(onAccent)
						Verify.expect(style(sheet, ".facet-role-onIndicator >> .facet-button-caption").TextColor3)
							:toBe(onAccent)
						Verify.expect(style(sheet, ".facet-role-onIndicator >> .facet-button-caption").BackgroundColor3)
							:toBe(nil)
						Verify.expect(style(sheet, ".facet-segment-current").BackgroundColor3):toBe(accent)
						Verify.expect(style(sheet, ".facet-segment-current >> .facet-button-caption").TextColor3)
							:toBe(onAccent)
						Verify.expect(style(sheet, ".facet-tab-filled >> .facet-button-caption").TextColor3)
							:toBe(onAccent)
						Verify.expect(style(sheet, ".facet-toggle-on >> .facet-toggle-mark").BackgroundColor3)
							:toBe(onAccent)
						Verify.expect(
							ruleNode(sheet, ".facet-role-onIndicator >> .facet-button-caption").Priority
								> ruleNode(sheet, ".facet-button-caption").Priority
						):toBe(true)
						stop()
					end
				end
				Verify.expect(table.find(unreadableContent, "classic-desktop/Day") ~= nil):toBe(true)
				Verify.expect(table.find(unreadableContent, "classic-desktop/Night") ~= nil):toBe(true)
				Verify.expect(table.find(unreadableContent, "pixel-quest/Quest") ~= nil):toBe(true)
				runtime:dispose()
			end,
		})

		verifyHarness:case("declares readable success and warning pairs of its own in every shipped variant", {
			id = "native_parity_strength_themepkg::shipped theme contrast::declares readable success and warning pairs of its own in every shipped variant",
			run = function()
				local engine, runtime = world()
				local variants: { { name: string, colors: any, package: any, palette: string } } = {}
				local neutral = themes.neutralPackage()
				table.insert(variants, {
					name = "facet-neutral/Dark",
					colors = neutral.style.themes[1].colors,
					package = themes.define(neutral),
					palette = "Dark",
				})
				for _, name in REFERENCE do
					local definition = load(name).definition
					local package = built(name)
					local authored = if definition then definition(themes).style.themes else package.style.themes
					for index, palette in package.style.themes do
						table.insert(variants, {
							name = `{name}/{palette.name}`,
							colors = authored[index].colors,
							package = package,
							palette = palette.name,
						})
					end
				end
				local missing, same, report = {}, {}, {}
				local lowest, worst = math.huge, ""
				for _, variant in variants do
					local colors = variant.colors
					for _, role in
						{ "success", "onSuccess", "warning", "onWarning" } :: { "onSuccess" | "onWarning" | "success" | "warning" }
					do
						if type(colors[role]) ~= "table" then
							table.insert(missing, `{variant.name}.{role}`)
						end
					end
					for _, pair in { { "success", "onSuccess" }, { "warning", "onWarning" } } do
						local ratio = contrast(colors[pair[1]], colors[pair[2]])
						table.insert(report, `{variant.name}/{pair[1]} {math.floor(ratio * 100) / 100}`)
						if ratio < lowest then
							lowest, worst = ratio, `{variant.name}/{pair[1]}`
						end
					end
					local function equal(a: any, b: any): boolean
						return a.r == b.r and a.g == b.g and a.b == b.b
					end
					if equal(colors.success, colors.accent) then
						table.insert(same, `{variant.name}: success == accent`)
					end
					if equal(colors.warning, colors.content) then
						table.insert(same, `{variant.name}: warning == content`)
					end
					if equal(colors.success, colors.warning) then
						table.insert(same, `{variant.name}: success == warning`)
					end
					local sheet, stop = sheetFor(engine, runtime, variant.package, { theme = variant.palette })
					Verify.expect(style(sheet, ".facet-status-success").BackgroundColor3)
						:toBe(color(engine, colors.success))
					Verify.expect(style(sheet, ".facet-status-success").TextColor3)
						:toBe(color(engine, colors.onSuccess))
					Verify.expect(style(sheet, ".facet-status-warning").BackgroundColor3)
						:toBe(color(engine, colors.warning))
					Verify.expect(style(sheet, ".facet-status-warning").TextColor3)
						:toBe(color(engine, colors.onWarning))
					stop()
				end
				Verify.expect(#variants):toBe(13)
				Verify.expect(`missing: {table.concat(missing, " ")}`):toBe("missing: ")
				Verify.expect((table.concat(same, " · "))):toBe("")
				Verify.expect(#report):toBe(26)
				Verify.expect(`worst {worst} {math.floor(lowest * 100) / 100} >= 4.5: {lowest >= 4.5}`)
					:toBe("worst fantasy_parchment/Daylight/warning 5.27 >= 4.5: true")
				for _, name in REFERENCE do
					local _, compiled = load(name).build(themes)
					local themeCount = #built(name).style.themes
					for _, pair in { "onSuccess/success", "onWarning/warning" } do
						local entries = contrastEntries(compiled, pair)
						Verify.expect(#entries):toBe(themeCount)
						for _, entry in entries do
							Verify.expect(entry.ok):toBe(true)
						end
					end
				end
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("theme contrast gate", function()
		verifyHarness:case("reports every semantic pair of an accepted package with its measured ratio", {
			id = "native_parity_strength_themepkg::theme contrast gate::reports every semantic pair of an accepted package with its measured ratio",
			run = function()
				local definition = themes.neutralPackage()
				local package, report = themes.define(definition)
				Verify.expect(package ~= nil):toBe(true)
				Verify.expect(report.ok):toBe(true)
				Verify.expect(#report.errors):toBe(0)
				local expected = {}
				for _, palette in definition.style.themes do
					local colors, extra = palette.colors :: any, palette.extra :: any
					for _, want in
						{
							{ "content/surface", colors.content, colors.surface },
							{ "contentStrong/surfaceStrong", colors.contentStrong, colors.surfaceStrong },
							{ "onAccent/accent", colors.onAccent, colors.accent },
							{ "onDanger/danger", colors.onDanger, colors.danger },
							{ "onSuccess/success", colors.onSuccess, colors.success },
							{ "onWarning/warning", colors.onWarning, colors.warning },
							{ "onSelected/controlSelected", colors.content, extra.controlSelected },
						}
					do
						table.insert(expected, want)
					end
				end
				Verify.expect(#definition.style.themes):toBe(2)
				Verify.expect(#report.contrast):toBe(#expected)
				for index, want in expected do
					local entry = report.contrast[index]
					Verify.expect(entry.pair):toBe(want[1])
					Verify.expect(math.abs(entry.ratio - contrast(want[2], want[3])) < 1e-9):toBe(true)
					Verify.expect(entry.ratio >= 4.5):toBe(true)
					Verify.expect(entry.ok):toBe(true)
				end
			end,
		})

		verifyHarness:case("refuses each unreadable pair at define time and names the pair, palette and ratio", {
			id = "native_parity_strength_themepkg::theme contrast gate::refuses each unreadable pair at define time and names the pair, palette and ratio",
			run = function()
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
					for paletteIndex, name in { "Dark", "Light" } do
						local definition = themes.neutralPackage()
						local colors = definition.style.themes[paletteIndex].colors :: any
						colors[pair[1]] = table.clone(colors[pair[2]])
						local package, report = themes.define(definition)
						Verify.expect(package):toBe(nil)
						Verify.expect(report.ok):toBe(false)
						Verify.expect(#report.errors):toBe(if pair[1] == "content" then 2 else 1)
						Verify.expect((hasError(report, "style." .. name, pair[1] .. " contrast is below 4.5:1")))
							:toBe(true)
						Verify.expect(#report.contrast):toBe(14)
						for index, entry in report.contrast do
							local own = math.floor((index - 1) / 7) + 1 == paletteIndex
							if own and entry.pair == pair[1] .. "/" .. pair[2] then
								Verify.expect(entry.ok):toBe(false)
								Verify.expect(math.abs(entry.ratio - 1) < 1e-9):toBe(true)
							elseif own and pair[1] == "content" and entry.pair == "onSelected/controlSelected" then
								Verify.expect(entry.ok):toBe(false)
								Verify.expect(
									(hasError(report, "style." .. name, "onSelected contrast is below 4.5:1"))
								)
									:toBe(true)
							else
								Verify.expect(entry.ok):toBe(true)
							end
						end
					end
				end
				local selected = themes.neutralPackage()
				local extra = selected.style.themes[1].extra :: any
				extra.onSelected = { r = 45 / 255, g = 58 / 255, b = 92 / 255 }
				local _, selectedReport = themes.define(selected)
				Verify.expect(selectedReport.ok):toBe(false)
				Verify.expect((hasError(selectedReport, "style.Dark", "onSelected contrast is below 4.5:1"))):toBe(true)
				local second = themes.neutralPackage()
				local night = table.clone(second.style.themes[1])
				night.name = "Night"
				night.colors = table.clone(night.colors)
				night.colors.warning = table.clone((night.colors :: any).onWarning)
				table.insert(second.style.themes, night)
				local _, secondReport = themes.define(second)
				Verify.expect(secondReport.ok):toBe(false)
				Verify.expect(#secondReport.errors):toBe(1)
				Verify.expect((hasError(secondReport, "style.Night", "onWarning contrast is below 4.5:1"))):toBe(true)
				Verify.expect(#contrastEntries(secondReport, "onWarning/warning")):toBe(3)
				Verify.expect(contrastEntries(secondReport, "onWarning/warning")[1].ok):toBe(true)
				Verify.expect(contrastEntries(secondReport, "onWarning/warning")[2].ok):toBe(true)
				Verify.expect(contrastEntries(secondReport, "onWarning/warning")[3].ok):toBe(false)
			end,
		})

		verifyHarness:case("refuses a definition with no identity or no palette and names the field", {
			id = "native_parity_strength_themepkg::theme contrast gate::refuses a definition with no identity or no palette and names the field",
			run = function()
				local anonymous, anonymousReport = themes.define({ identity = { id = 7 } } :: any)
				Verify.expect(anonymous):toBe(nil)
				Verify.expect(anonymousReport.ok):toBe(false)
				Verify.expect((hasError(anonymousReport, "identity.id", "A theme package needs an identity")))
					:toBe(true)
				local empty, emptyReport =
					themes.define({ base = { identity = { id = "bare" }, style = { themes = {} } } } :: any)
				Verify.expect(empty):toBe(nil)
				Verify.expect((hasError(emptyReport, "style.themes", "A theme package needs at least one palette")))
					:toBe(true)
				local _, malformed = themes.define({ style = { themes = { { colors = {} } } } } :: any)
				Verify.expect(malformed.ok):toBe(false)
				Verify.expect((hasError(malformed, "style.themes", "Palettes require a name and color dictionary")))
					:toBe(true)
				local definition = themes.neutralPackage();
				(definition.style.themes[1].colors :: any).accent = { r = 2, g = 0, b = 0 }
				local _, channels = themes.define(definition)
				Verify.expect(
					(hasError(channels, "colors.accent", "Colors require RGB components between zero and one"))
				)
					:toBe(true)
			end,
		})
	end)

	verifyHarness:suite("theme coverage", function()
		verifyHarness:case("names each missing need with its message and fix and lists the covered ones", {
			id = "native_parity_strength_themepkg::theme coverage::names each missing need with its message and fix and lists the covered ones",
			run = function()
				local needs: { any } = {
					{ name = "custom:knob", section = "metrics.radii", kind = "number" :: "number" },
					{ name = "custom:tint", kind = "color" :: "color" },
					{ name = "custom:row", section = "metrics.controlSizes", fields = { "height", "paddingX" } },
					{ name = "body", section = "metrics.typography", fields = { "size" } },
					{ name = "accent", kind = "color" :: "color" },
				}
				local neutral = themes.neutralPackage()
				local report = themes.checkCoverage(neutral, needs)
				Verify.expect(report.ok):toBe(false)
				Verify.expect((table.concat(report.covered, " "))):toBe("body accent")
				Verify.expect(#report.missing):toBe(3)
				Verify.expect(report.missing[1].name):toBe("custom:knob")
				Verify.expect(report.missing[1].message):toBe("Theme has no custom:knob")
				Verify.expect(report.missing[1].fix):toBe("Declare metrics.radii.custom:knob")
				Verify.expect(report.missing[2].name):toBe("custom:tint")
				Verify.expect(report.missing[2].message):toBe("Theme has no custom:tint")
				Verify.expect(report.missing[2].fix):toBe("Declare metrics.custom:tint")
				Verify.expect(report.missing[3].name):toBe("custom:row")
				Verify.expect(report.missing[3].message):toBe("Theme has no custom:row")
				Verify.expect(report.missing[3].fix):toBe("Declare metrics.controlSizes.custom:row")
				local partial = themes.neutralPackage();
				(partial.metrics.radii :: any)["custom:knob"] = "round"
				(partial.metrics.controlSizes :: any)["custom:row"] = { height = 30 }
				local second = table.clone(partial.style.themes[1])
				second.name = "Second"
				second.extra = table.clone(second.extra or {});
				(second.extra :: any)["custom:tint"] = { r = 1, g = 0, b = 0 }
				table.insert(partial.style.themes, second)
				local partialReport = themes.checkCoverage(partial, needs)
				Verify.expect(partialReport.ok):toBe(false)
				Verify.expect(#partialReport.missing):toBe(3)
				Verify.expect((table.concat(partialReport.covered, " "))):toBe("body accent")
				local covering = themes.neutralPackage();
				(covering.metrics.radii :: any)["custom:knob"] = 6
				(covering.metrics.controlSizes :: any)["custom:row"] = { height = 30, paddingX = 4 }
				for _, palette in covering.style.themes do
					(palette.extra :: any)["custom:tint"] = { r = 1, g = 0, b = 0 }
				end
				local coveringReport = themes.checkCoverage(covering, needs)
				Verify.expect(coveringReport.ok):toBe(true)
				Verify.expect(#coveringReport.missing):toBe(0)
				Verify.expect((table.concat(coveringReport.covered, " ")))
					:toBe("custom:knob custom:tint custom:row body accent")
			end,
		})

		verifyHarness:case("checks namespaced control sizes, colors and numbers against the shipped packages", {
			id = "native_parity_strength_themepkg::theme coverage::checks namespaced control sizes, colors and numbers against the shipped packages",
			run = function()
				for _, name in REFERENCE do
					local package = built(name)
					local documented = themes.checkCoverage(
						package,
						{
							{
								kind = "color" :: string?,
								name = "accent",
								section = nil :: string?,
								fields = nil :: { string }?,
							},
							{
								section = "metrics.typography",
								name = "body",
								fields = { "size" },
								kind = nil :: string?,
							},
						} :: any
					)
					Verify.expect(`{name}: {documented.ok}`):toBe(`{name}: true`)
				end
				local glossy, classic = built("glossy_mobile"), built("classic_desktop")
				local covering = themes.checkCoverage(glossy, customControl.needs :: any)
				Verify.expect(covering.ok):toBe(true)
				Verify.expect((table.concat(covering.covered, " "))):toBe("demo:gauge demo:gaugeTint")
				local uncovering = themes.checkCoverage(classic, customControl.needs :: any)
				Verify.expect(uncovering.ok):toBe(false)
				Verify.expect(#uncovering.covered):toBe(0)
				Verify.expect(uncovering.missing[1].message):toBe("Theme has no demo:gauge")
				Verify.expect(uncovering.missing[1].fix):toBe("Declare metrics.controlSizes.demo:gauge")
				Verify.expect(uncovering.missing[2].message):toBe("Theme has no demo:gaugeTint")
				Verify.expect(uncovering.missing[2].fix):toBe("Declare style.themes[].extra.demo:gaugeTint")
				local own = customControl.check(classic)
				Verify.expect(own.ok):toBe(false)
				Verify.expect(#own.missing):toBe(2)
				for _, entry in own.missing do
					Verify.expect(string.find(entry.message, classic.identity.id, 1, true) ~= nil):toBe(true)
					Verify.expect(string.find(entry.message, entry.name, 1, true) ~= nil):toBe(true)
					Verify.expect(#entry.fix > 0):toBe(true)
				end
				Verify.expect(customControl.check(glossy).ok):toBe(true)
				Verify.expect(customControl.resolve(glossy).height):toBe(28)
				Verify.expect(customControl.resolve(glossy).usedFallback.size):toBe(false)
				Verify.expect(customControl.resolve(classic).usedFallback.size):toBe(true)
				Verify.expect(customControl.resolve(classic).height)
					:toBe((customControl.needs[1].fallback :: { [string]: number }).height)
				for _, name in { "fantasy_ornate", "pixel_quest" } do
					local report = ornateGauge.check(themes, built(name))
					Verify.expect(report.ok):toBe(true)
					Verify.expect((table.concat(report.covered, " "))):toBe("gauge:dial gauge:needle gauge:ring")
				end
				for _, name in { "fantasy_ornate", "pixel_quest", "classic_desktop", "glossy_touch" } do
					local package = built(name)
					local own = ornateGauge.check(themes, package)
					local framework = themes.checkCoverage(package, ornateGauge.needs :: any)
					Verify.expect(own.ok):toBe(framework.ok)
					Verify.expect(#own.covered):toBe(#framework.covered)
					Verify.expect(#own.missing):toBe(#framework.missing)
				end
				local missing = ornateGauge.check(themes, classic)
				Verify.expect(#missing.missing):toBe(3)
				for _, entry in missing.missing do
					Verify.expect(entry.message):toBe("Theme has no " .. entry.name)
					Verify.expect(string.find(entry.fix, entry.name, 1, true) ~= nil):toBe(true)
				end
				local _, glossyReport = load("glossy_mobile").build(themes)
				local _, classicReport = load("classic_desktop").build(themes)
				Verify.expect(glossyReport.ok):toBe(true)
				Verify.expect(#glossyReport.errors):toBe(0)
				Verify.expect(classicReport.ok):toBe(true)
				Verify.expect(#classicReport.errors):toBe(0)
				Verify.expect((glossy.metrics.controlSizes :: any)["demo:gauge"].height):toBe(28)
				Verify.expect((table.isfrozen((glossy.metrics.controlSizes :: any)["demo:gauge"]))):toBe(true)
			end,
		})
	end)

	verifyHarness:suite("reference theme packages", function()
		verifyHarness:case("accepts every reference package frozen and carrying its module identity", {
			id = "native_parity_strength_themepkg::reference theme packages::accepts every reference package frozen and carrying its module identity",
			run = function()
				Verify.expect(table.find(REFERENCE, "fantasy_parchment_stub") ~= nil):toBe(true)
				for _, name in REFERENCE do
					local module = load(name)
					local package, report = module.build(themes)
					Verify.expect(`{name}: {report.ok} {#report.errors}`):toBe(`{name}: true 0`)
					Verify.expect(package.schema):toBe(themes.SCHEMA)
					Verify.expect(package.identity.id):toBe(module.id)
					Verify.expect(package.identity.displayName):toBe(module.displayName)
					Verify.expect(`{name}: {frozenPath(package, "package", {}) or "frozen"}`):toBe(`{name}: frozen`)
					Verify.expect((pcall(function()
						(package.metrics.space :: any).m = 99
					end))):toBe(false)
					local declared = false
					for _, palette in package.style.themes do
						Verify.expect((type(palette.name))):toBe("string")
						declared = declared or palette.name == package.style.defaultTheme
					end
					Verify.expect(declared):toBe(true)
					for _, role in themes.TYPE_ROLES do
						Verify.expect(package.metrics.typography[role].size > 0):toBe(true)
					end
					Verify.expect(package.metrics.controlSizes.regular.height > 0):toBe(true)
					Verify.expect(package.metrics.targetSizes.minimum >= 44):toBe(true)
					local source = fs.readFile(themePackages.path(name))
					Verify.expect((string.find(source, 'require("../../src', 1, true))):toBe(nil)
				end
			end,
		})

		verifyHarness:case(
			"gives every shipped package and palette the same core rule ids, so a theme swap mounts no rule",
			{
				id = "native_parity_strength_themepkg::reference theme packages::gives every shipped package and palette the same core rule ids, so a theme swap mounts no rule",
				run = function()
					local engine, runtime = world()
					local function ids(package: any, palette: string?): { [string]: string }
						local sheet, stop = sheetFor(engine, runtime, package, { theme = palette })
						local names = {}
						for _, node in sheet:GetChildren() do
							names[node.Name] = node.Selector
						end
						stop()
						return names
					end
					local base = ids(themes.neutralPackage(), nil)
					for _, name in SHIPPED do
						local package = built(name)
						local own: { [string]: boolean } = {}
						for _, definition in package.rules or {} do
							own[definition.selector] = true
						end
						for _, palette in package.style.themes do
							local names, odd = ids(package, palette.name), {}
							for id in base do
								if names[id] == nil then
									table.insert(odd, "-" .. id)
								end
							end
							for id, selector in names do
								if
									base[id] == nil
									and not own[selector]
									and not string.find(selector, "::UIGradient", 1, true)
								then
									table.insert(odd, "+" .. id)
								end
							end
							Verify.expect(`{name}/{palette.name}:{table.concat(odd, " ")}`)
								:toBe(`{name}/{palette.name}:`)
						end
					end
				end,
			}
		)

		verifyHarness:case(
			"compiles every reference package to the same complete rule set twice and paints each palette",
			{
				id = "native_parity_strength_themepkg::reference theme packages::compiles every reference package to the same complete rule set twice and paints each palette",
				run = function()
					local engine, runtime = world()
					for _, name in REFERENCE do
						local package = built(name)
						local first, stopFirst = sheetFor(engine, runtime, package)
						local second, stopSecond = sheetFor(engine, runtime, package)
						local a, b = rulesSignature(first), rulesSignature(second)
						Verify.expect(#a > 30):toBe(true)
						Verify.expect(#a):toBe(#b)
						for index, line in a do
							Verify.expect(b[index]):toBe(line)
						end
						local defaultPalette
						for _, palette in package.style.themes do
							if palette.name == package.style.defaultTheme then
								defaultPalette = palette
							end
						end
						Verify.expect(style(first, ".facet-surface").BackgroundColor3)
							:toBe(color(engine, defaultPalette.colors.surface))
						Verify.expect(style(first, ".facet-text").TextColor3)
							:toBe(color(engine, defaultPalette.colors.content))
						stopFirst()
						stopSecond()
						local painted: { [string]: boolean } = {}
						local count = 0
						for _, palette in package.style.themes do
							local sheet, stop = sheetFor(engine, runtime, package, { theme = palette.name })
							local surface = style(sheet, ".facet-surface").BackgroundColor3
							Verify.expect(surface):toBe(color(engine, palette.colors.surface))
							Verify.expect(style(sheet, ".facet-text").TextColor3)
								:toBe(color(engine, palette.colors.content))
							Verify.expect(style(sheet, ".facet-panel").BackgroundColor3)
								:toBe(color(engine, palette.colors.surfaceStrong))
							Verify.expect(#sheet:GetChildren()):toBe(#a)
							if not painted[tostring(surface)] then
								painted[tostring(surface)] = true
								count += 1
							end
							stop()
						end
						Verify.expect(`{name}: {count}`):toBe(`{name}: {#package.style.themes}`)
					end
					runtime:dispose()
				end,
			}
		)
	end)

	verifyHarness:suite("reference art packages", function()
		verifyHarness:case(
			"Fantasy Ornate declares the whole layer vocabulary, per-state art and a complete bar family",
			{
				id = "native_parity_strength_themepkg::reference art packages::Fantasy Ornate declares the whole layer vocabulary, per-state art and a complete bar family",
				run = function()
					local engine, runtime = world()
					local package, report = load("fantasy_ornate").build(themes)
					Verify.expect(report.ok):toBe(true)
					Verify.expect(#package.style.themes):toBe(2)
					Verify.expect(#report.contrast):toBe(14)
					for _, entry in report.contrast do
						Verify.expect(entry.ok):toBe(true)
						Verify.expect(entry.ratio >= 4.5):toBe(true)
					end
					local chrome = package.chrome :: any
					local panel = chrome.panel
					Verify.expect(panel.kind):toBe("layered")
					local kinds: { [string]: boolean } = {}
					local corners
					for _, layer in panel.layers do
						kinds[layer.kind] = true
						if layer.kind == "corners" then
							corners = layer
						elseif layer.kind == "edges" then
							Verify.expect(layer.tile):toBe(64)
						end
					end
					for _, kind in
						{ "tile", "fill", "frame", "edges", "corners", "plaque" } :: { "corners" | "edges" | "fill" | "frame" | "plaque" | "tile" }
					do
						Verify.expect(`{kind}: {kinds[kind] == true}`):toBe(`{kind}: true`)
					end
					local art: { [string]: boolean } = {}
					for _, corner in { "topLeft", "topRight", "bottomLeft", "bottomRight" } do
						Verify.expect(package.assets[corners[corner]] ~= nil):toBe(true)
						art[corners[corner]] = true
					end
					local distinct = 0
					for _ in art do
						distinct += 1
					end
					Verify.expect(distinct):toBe(4)
					local fill = chrome.control.layers[1].asset
					for _, state in { "default", "hover", "pressed", "error" } do
						Verify.expect(package.assets[fill[state]] ~= nil):toBe(true)
					end
					Verify.expect(fill.selected.asset):toBe("ornate_selection_selected")
					Verify.expect(fill.selected.rotation):toBe(180)
					local count = 0
					for _ in fill do
						count += 1
					end
					Verify.expect(count):toBe(5)
					for slot, states in
						{
							selection = chrome.selection.layers[1].asset,
							toggleTrack = chrome.toggleTrack.asset,
							toggleKnob = chrome.toggleKnob.asset,
							stepperPlate = chrome.stepperPlate.asset,
						} :: { [string]: any }
					do
						local declared = 0
						for _, asset in states do
							Verify.expect(`{slot}: {package.assets[asset] ~= nil}`):toBe(`{slot}: true`)
							declared += 1
						end
						Verify.expect(`{slot}: {declared}`):toBe(`{slot}: 2`)
					end
					Verify.expect(chrome.control.contentInsets.left):toBe(14)
					for _, slot in
						{ "barTrack", "barFill", "barCap", "barCenter", "stepperPlate", "toggleTrack", "toggleKnob" }
					do
						Verify.expect(`{slot}: {chrome[slot] ~= nil}`):toBe(`{slot}: true`)
					end
					Verify.expect(chrome.barFill.direction):toBe("ltr")
					Verify.expect(chrome.barCap.startAsset ~= chrome.barCap.endAsset):toBe(true)
					Verify.expect(package.metrics.controls.progress.trackHeight >= 28):toBe(true)
					Verify.expect((package.metrics.controls :: any).slider.railHeight >= 20):toBe(true)
					Verify.expect(package.metrics.iconSizes.medium):toBe(32)
					for _, name in
						{
							"increment",
							"decrement",
							"chevron.trailing",
							"chevron.down",
							"checkmark",
							"close",
							"ornate:settings",
						}
					do
						local resolved = themes.resolveIcon(package, name)
						local asset = package.assets[(package.icons :: any)[name]]
						Verify.expect(`{name}: {resolved}`):toBe(`{name}: {asset.content or asset.contentId}`)
						Verify.expect((string.sub(resolved :: string, 1, 13))):toBe("rbxassetid://")
					end
					local cap, stopCap = skinOf(engine, runtime, package, "barCap")
					local start, finish = cap:FindFirstChild("barCap-start"), cap:FindFirstChild("barCap-end")
					Verify.expect(start.Image):toBe(package.assets[chrome.barCap.startAsset].content)
					Verify.expect(finish.Image):toBe(package.assets[chrome.barCap.endAsset].content)
					Verify.expect(start.Image ~= finish.Image):toBe(true)
					Verify.expect(start.Size):toBe(D2(engine, 0, 28, 0, 36))
					Verify.expect(start.Position):toBe(D2(engine, 0, 0, 0.5, 0))
					Verify.expect(finish.Position):toBe(D2(engine, 1, 0, 0.5, 0))
					stopCap()
					local progressEngine, progressRuntime, UI = world({ theme = package })
					local stop, bar: any = progressRuntime.mount(function()
						return UI.ProgressView({ value = 0.5 })
					end, progressEngine.new("Folder"))
					Verify.expect(find(bar, "Track").Size.Y.Offset):toBe(package.metrics.controls.progress.trackHeight)
					stop()
					progressRuntime:dispose()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case(
			"Pixel Quest declares pixel rendering and draws every slot nearest-neighbour at integer slice scales",
			{
				id = "native_parity_strength_themepkg::reference art packages::Pixel Quest declares pixel rendering and draws every slot nearest-neighbour at integer slice scales",
				run = function()
					local engine, runtime = world()
					local package = built("pixel_quest")
					Verify.expect((package.identity :: any).rendering):toBe("pixel")
					Verify.expect((package.identity :: any).pixelUnit):toBe(4)
					local sliced = 0
					for name, asset in package.assets :: any do
						Verify.expect(#name > 0):toBe(true)
						if asset.sliceCenter ~= nil then
							Verify.expect(
								`{name}: {asset.sliceScale == math.floor(asset.sliceScale) and asset.sliceScale >= 1}`
							)
								:toBe(`{name}: true`)
							sliced += 1
						end
					end
					Verify.expect(sliced >= 10):toBe(true)
					local drawn, slots = 0, 0
					for slot, recipe in package.chrome :: any do
						if recipe.kind == "native" or recipe.kind == "none" or slot == "focus" then
							continue
						end
						slots += 1
						for _, state in STATES do
							local skin, stop = skinOf(engine, runtime, package, slot, { state = state })
							local layers = images(skin)
							Verify.expect(`{slot}/{state}: {#layers > 0}`):toBe(`{slot}/{state}: true`)
							for _, image in layers do
								Verify.expect(`{slot}/{image.Name}: {image.ResampleMode}`)
									:toBe(`{slot}/{image.Name}: {engine.types.Enum.ResamplerMode.Pixelated}`)
								Verify.expect(
									image.SliceScale == math.floor(image.SliceScale) and image.SliceScale >= 1
								)
									:toBe(true)
								if image.ScaleType == engine.types.Enum.ScaleType.Slice then
									drawn += 1
								end
							end
							stop()
						end
					end
					Verify.expect(slots):toBe(10)
					Verify.expect(drawn > 0):toBe(true)
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("renders Fantasy Ornate's full-vocabulary panel as one image per layer box", {
			id = "native_parity_strength_themepkg::reference art packages::renders Fantasy Ornate's full-vocabulary panel as one image per layer box",
			run = function()
				local engine, runtime = world()
				local package = built("fantasy_ornate")
				local assets = package.assets :: any
				local target
				local stop, skin: any = runtime.mount(function()
					target = ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({})
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
						target :: unknown,
						themes.skin(
							runtime,
							package,
							"panel",
							{ types = engine.types, target = target :: GuiObject, label = "Quest Log" }
						),
					})
				end, engine.new("Folder"))
				skin = find(skin, "Skin")
				local layers = images(skin)
				Verify.expect(#layers):toBe(10)
				Verify.expect((names({ layers[1], layers[2], layers[3], layers[4], layers[5], layers[10] })))
					:toBe("panel1 panel2 panel3 panel4top panel4bottom panel6")
				local cornerNames = { layers[6].Name, layers[7].Name, layers[8].Name, layers[9].Name }
				table.sort(cornerNames)
				Verify.expect((table.concat(cornerNames, " ")))
					:toBe("panel5bottomLeft panel5bottomRight panel5topLeft panel5topRight")
				local T = engine.types
				local tile = skin:FindFirstChild("panel1")
				Verify.expect(tile.Image):toBe(assets.ornate_velvet_tile.content)
				Verify.expect(tile.ScaleType):toBe(T.Enum.ScaleType.Tile)
				Verify.expect(tile.TileSize):toBe(D2(engine, 0, 64, 0, 64))
				Verify.expect(tile.Size):toBe(D2(engine, 1, 0, 1, 0))
				local fill = skin:FindFirstChild("panel2")
				Verify.expect(fill.Image):toBe(assets.ornate_panel_fill.content)
				Verify.expect(fill.ScaleType):toBe(T.Enum.ScaleType.Slice)
				Verify.expect(fill.SliceCenter):toBe(T.Rect.new(32, 32, 96, 96))
				local frame = skin:FindFirstChild("panel3")
				Verify.expect(frame.Image):toBe(assets.ornate_panel_frame.content)
				Verify.expect(frame.SliceCenter):toBe(T.Rect.new(40, 40, 120, 120))
				for _, edge in { "top", "bottom" } :: { "bottom" | "top" } do
					local rail = skin:FindFirstChild("panel4" .. edge)
					Verify.expect(rail.Image):toBe(assets.ornate_edge_rail.content)
					Verify.expect(rail.ScaleType):toBe(T.Enum.ScaleType.Tile)
					Verify.expect(rail.TileSize):toBe(D2(engine, 0, 64, 0, 64))
					Verify.expect(rail.Size):toBe(D2(engine, 1, -88, 0, 12))
					Verify.expect(rail.Position):toBe(D2(engine, 0, 44, if edge == "bottom" then 1 else 0, 0))
				end
				for corner, art in
					{
						topLeft = "ornate_corner_tl",
						topRight = "ornate_corner_tr",
						bottomLeft = "ornate_corner_bl",
						bottomRight = "ornate_corner_br",
					} :: { [string]: string }
				do
					local image = skin:FindFirstChild("panel5" .. corner)
					Verify.expect(`{corner}: {image.Image}`):toBe(`{corner}: {assets[art].content}`)
					Verify.expect(image.Size):toBe(D2(engine, 0, 30, 0, 30))
				end
				local plaque = skin:FindFirstChild("panel6")
				Verify.expect(plaque.Image):toBe(assets.ornate_plaque.content)
				Verify.expect(plaque.Size):toBe(D2(engine, 0, 176, 0, 40))
				Verify.expect(plaque.Position):toBe(D2(engine, 0.5, 0, 0, 0))
				Verify.expect(plaque.AnchorPoint):toBe(V2(engine, 0.5, 0.5))
				local caption = plaque:FindFirstChild("PlaqueCaption")
				Verify.expect(caption.Text):toBe("Quest Log")
				Verify.expect((caption:HasTag("facet-skin-caption-text"))):toBe(true)
				local padding = caption:FindFirstChildWhichIsA("UIPadding")
				Verify.expect(padding.PaddingTop.Offset):toBe(13)
				Verify.expect(padding.PaddingRight.Offset):toBe(16)
				Verify.expect(padding.PaddingBottom.Offset):toBe(15)
				Verify.expect(padding.PaddingLeft.Offset):toBe(16)
				Verify.expect((target:HasTag("facet-skinned"))):toBe(true)
				Verify.expect((target:HasTag("facet-skin-caption"))):toBe(true)
				local shadow = target:FindFirstChild("ChromeShadow") :: FixtureShadow
				Verify.expect(shadow ~= nil):toBe(true)
				Verify.expect(shadow.BlurRadius):toBe(T.UDim.new(0, 14))
				Verify.expect(shadow.Transparency):toBe(0.35)
				stop()
				Verify.expect((plaque.isDestroyed())):toBe(true)
				Verify.expect((shadow.isDestroyed())):toBe(true)
				runtime:dispose()
			end,
		})
	end)

	local function layeredPackage(layers: { any }): any
		local package = themes.neutralPackage()
		package.assets = {
			plate = { content = "rbxassetid://11", sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 24 } },
			frame = { content = "rbxassetid://12", sliceCenter = { x0 = 4, y0 = 4, x1 = 12, y1 = 12 } },
			pattern = { content = "rbxassetid://13" },
			rail = { content = "rbxassetid://14" },
			side = { content = "rbxassetid://15" },
			gold = { content = "rbxassetid://16" },
			ornament = { content = "rbxassetid://17" },
			banner = { content = "rbxassetid://18" },
		} :: any
		assert(package.chrome).panel = { kind = "layered", layers = layers } :: any
		return package
	end

	local FULL_STACK: { FixtureThemeTypes.SkinLayer } = {
		{ kind = "fill" :: "fill", asset = "plate" },
		{ kind = "frame" :: "frame", asset = "frame" },
		{ kind = "tile" :: "tile", asset = "pattern", tileSize = { w = 32, h = 24 } },
		{
			kind = "edges" :: "edges",
			asset = "rail",
			sides = { "top", "bottom" } :: { "top" | "bottom" | "left" | "right" },
			thickness = 8,
			margin = 24,
		},
		{
			kind = "edges" :: "edges",
			asset = "side",
			sides = { "left", "right" } :: { "top" | "bottom" | "left" | "right" },
			thickness = 6,
			margin = 12,
		},
		{ kind = "corners" :: "corners", asset = "ornament", size = 24, topLeft = "gold" },
		{
			kind = "plaque" :: "plaque",
			asset = "banner",
			size = { w = 140, h = 36 },
			edge = "top" :: "top",
			overhang = 18,
			text = true,
			textInsets = { top = 6, right = 12, bottom = 4, left = 10 },
		},
		{
			kind = "plaque" :: "plaque",
			asset = "banner",
			size = { w = 60, h = 20 },
			edge = "bottom" :: "bottom",
			overhang = 10,
		},
		{
			kind = "plaque" :: "plaque",
			asset = "banner",
			size = { w = 20, h = 60 },
			edge = "left" :: "left",
			overhang = 5,
		},
		{
			kind = "plaque" :: "plaque",
			asset = "banner",
			size = { w = 20, h = 60 },
			edge = "right" :: "right",
			overhang = 7,
		},
	}

	local function expectBox(engine: any, image: any, size: { number }, position: { number }, anchor: { number })
		Verify.expect(`{image.Name} size {image.Size}`)
			:toBe(`{image.Name} size {D2(engine, size[1], size[2], size[3], size[4])}`)
		Verify.expect(`{image.Name} position {image.Position}`)
			:toBe(`{image.Name} position {D2(engine, position[1], position[2], position[3], position[4])}`)
		Verify.expect(`{image.Name} anchor {image.AnchorPoint}`)
			:toBe(`{image.Name} anchor {V2(engine, anchor[1], anchor[2])}`)
	end

	verifyHarness:suite("theme layer boxes", function()
		verifyHarness:case("places full-bleed layers, four anchored corners, per-side rails and overhanging plaques", {
			id = "native_parity_strength_themepkg::theme layer boxes::places full-bleed layers, four anchored corners, per-side rails and overhanging plaques",
			run = function()
				local engine, runtime = world()
				local T = engine.types
				local package = layeredPackage(FULL_STACK)
				local skin, stop = skinOf(engine, runtime, package, "panel", { label = "Title", ZIndex = 3 })
				local layers = images(skin)
				Verify.expect(#layers):toBe(15)
				for index = 1, 3 do
					expectBox(engine, skin:FindFirstChild("panel" .. index), { 1, 0, 1, 0 }, { 0, 0, 0, 0 }, { 0, 0 })
				end
				Verify.expect(skin:FindFirstChild("panel1").ScaleType):toBe(T.Enum.ScaleType.Slice)
				Verify.expect(skin:FindFirstChild("panel1").SliceCenter):toBe(T.Rect.new(8, 8, 24, 24))
				Verify.expect(skin:FindFirstChild("panel2").Image):toBe("rbxassetid://12")
				Verify.expect(skin:FindFirstChild("panel2").SliceCenter):toBe(T.Rect.new(4, 4, 12, 12))
				Verify.expect(skin:FindFirstChild("panel3").ScaleType):toBe(T.Enum.ScaleType.Tile)
				Verify.expect(skin:FindFirstChild("panel3").TileSize):toBe(D2(engine, 0, 32, 0, 24))
				expectBox(engine, skin:FindFirstChild("panel4top"), { 1, -48, 0, 8 }, { 0, 24, 0, 0 }, { 0, 0 })
				expectBox(engine, skin:FindFirstChild("panel4bottom"), { 1, -48, 0, 8 }, { 0, 24, 1, 0 }, { 0, 1 })
				expectBox(engine, skin:FindFirstChild("panel5left"), { 0, 6, 1, -24 }, { 0, 0, 0, 12 }, { 0, 0 })
				expectBox(engine, skin:FindFirstChild("panel5right"), { 0, 6, 1, -24 }, { 1, 0, 0, 12 }, { 1, 0 })
				Verify.expect(skin:FindFirstChild("panel4top").Image):toBe("rbxassetid://14")
				Verify.expect(skin:FindFirstChild("panel5left").Image):toBe("rbxassetid://15")
				for corner, point in
					{ topLeft = { 0, 0 }, topRight = { 1, 0 }, bottomLeft = { 0, 1 }, bottomRight = { 1, 1 } } :: {
						[string]: { number },
					}
				do
					local image = skin:FindFirstChild("panel6" .. corner)
					expectBox(engine, image, { 0, 24, 0, 24 }, { point[1], 0, point[2], 0 }, point)
					Verify.expect(`{corner} {image.Image}`)
						:toBe(`{corner} {if corner == "topLeft" then "rbxassetid://16" else "rbxassetid://17"}`)
				end
				expectBox(engine, skin:FindFirstChild("panel7"), { 0, 140, 0, 36 }, { 0.5, 0, 0, 0 }, { 0.5, 0.5 })
				expectBox(engine, skin:FindFirstChild("panel8"), { 0, 60, 0, 20 }, { 0.5, 0, 1, 0 }, { 0.5, 0.5 })
				expectBox(engine, skin:FindFirstChild("panel9"), { 0, 20, 0, 60 }, { 0, 5, 0.5, 0 }, { 0.5, 0.5 })
				expectBox(engine, skin:FindFirstChild("panel10"), { 0, 20, 0, 60 }, { 1, -3, 0.5, 0 }, { 0.5, 0.5 })
				local caption = skin:FindFirstChild("panel7"):FindFirstChild("PlaqueCaption")
				Verify.expect(caption.Text):toBe("Title")
				Verify.expect(caption.Size):toBe(D2(engine, 1, 0, 1, 0))
				local padding = caption:FindFirstChildWhichIsA("UIPadding")
				Verify.expect(padding.PaddingTop):toBe(T.UDim.new(0, 6))
				Verify.expect(padding.PaddingRight):toBe(T.UDim.new(0, 12))
				Verify.expect(padding.PaddingBottom):toBe(T.UDim.new(0, 4))
				Verify.expect(padding.PaddingLeft):toBe(T.UDim.new(0, 10))
				for _, other in { "panel8", "panel9", "panel10", "panel1" } do
					Verify.expect((skin:FindFirstChild(other):FindFirstChild("PlaqueCaption"))):toBe(nil)
				end
				for _, image in layers do
					Verify.expect(image.ZIndex):toBe(3)
					Verify.expect(image.BackgroundTransparency):toBe(1)
				end
				Verify.expect((names({ layers[1], layers[2], layers[3], layers[4], layers[5], layers[6], layers[7] })))
					:toBe("panel1 panel2 panel3 panel4top panel4bottom panel5left panel5right")
				Verify.expect((names({ layers[12], layers[13], layers[14], layers[15] })))
					:toBe("panel7 panel8 panel9 panel10")
				stop()
				for _, image in layers do
					Verify.expect((image.isDestroyed())):toBe(true)
				end
				runtime:dispose()
			end,
		})

		verifyHarness:case("retargets the mounted art to a changed ladder shape and hides the surplus", {
			id = "native_parity_strength_themepkg::theme layer boxes::retargets the mounted art to a changed ladder shape and hides the surplus",
			run = function()
				local engine, runtime = world()
				local T = engine.types
				local shapeA = layeredPackage({
					{ kind = "fill" :: "fill", asset = "plate" },
					{ kind = "corners" :: "corners", asset = "ornament", size = 12 },
				})
				local shapeB = layeredPackage({
					{
						kind = "edges" :: "edges",
						asset = "side",
						sides = { "left", "right" } :: { "top" | "bottom" | "left" | "right" },
						thickness = 6,
						margin = 12,
					},
					{
						kind = "plaque" :: "plaque",
						asset = "banner",
						size = { w = 60, h = 20 },
						edge = "bottom" :: "bottom",
						overhang = 10,
					},
				})
				local shapeC = layeredPackage({
					{ kind = "tile" :: "tile", asset = "pattern", tileSize = { w = 16, h = 16 } },
					{ kind = "frame" :: "frame", asset = "frame" },
					{ kind = "corners" :: "corners", asset = "ornament", size = 20 },
					{ kind = "edges" :: "edges", asset = "rail", thickness = 4, margin = 2 },
				})
				local native = themes.neutralPackage()
				assert(native.chrome).panel = { kind = "native" } :: any
				local selected = Compose.cell(shapeA)
				local target, skin
				local stop = runtime.mount(function()
					target = ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({})
					skin =
						themes.skin(runtime, selected, "panel", { types = engine.types, target = target :: GuiObject })
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({ target :: unknown, skin })
				end, engine.new("Folder"))
				skin = find(skin, "Skin")
				local first = images(skin)
				Verify.expect(#first):toBe(5)
				Verify.expect((target:HasTag("facet-skinned"))):toBe(true)
				selected:set(shapeB)
				local second = images(skin)
				Verify.expect(#second):toBe(3)
				Verify.expect(#skin:GetChildren()):toBe(5)
				Verify.expect((names(second))):toBe("panel1left panel1right panel2")
				for index = 1, 3 do
					Verify.expect(second[index]):toBe(first[index])
				end
				Verify.expect(first[4].Visible):toBe(false)
				Verify.expect(first[5].Visible):toBe(false)
				expectBox(engine, second[1], { 0, 6, 1, -24 }, { 0, 0, 0, 12 }, { 0, 0 })
				expectBox(engine, second[2], { 0, 6, 1, -24 }, { 1, 0, 0, 12 }, { 1, 0 })
				expectBox(engine, second[3], { 0, 60, 0, 20 }, { 0.5, 0, 1, 0 }, { 0.5, 0.5 })
				Verify.expect(second[1].Image):toBe("rbxassetid://15")
				Verify.expect(second[1].ScaleType):toBe(T.Enum.ScaleType.Stretch)
				Verify.expect(second[1].SliceCenter):toBe(T.Rect.new(0, 0, 0, 0))
				Verify.expect((target:HasTag("facet-skinned"))):toBe(true)
				selected:set(shapeC)
				local third = images(skin)
				Verify.expect(#third):toBe(10)
				for index = 1, 5 do
					Verify.expect(third[index]):toBe(first[index])
				end
				Verify.expect(third[1].Name):toBe("panel1")
				Verify.expect(third[1].ScaleType):toBe(T.Enum.ScaleType.Tile)
				Verify.expect(third[1].TileSize):toBe(D2(engine, 0, 16, 0, 16))
				expectBox(engine, third[1], { 1, 0, 1, 0 }, { 0, 0, 0, 0 }, { 0, 0 })
				Verify.expect(third[2].Name):toBe("panel2")
				Verify.expect(third[2].ScaleType):toBe(T.Enum.ScaleType.Slice)
				Verify.expect(third[2].SliceCenter):toBe(T.Rect.new(4, 4, 12, 12))
				expectBox(engine, third[2], { 1, 0, 1, 0 }, { 0, 0, 0, 0 }, { 0, 0 })
				for _, image in { third[3], third[4], third[5], third[6] } do
					Verify.expect((string.sub(image.Name, 1, 6))):toBe("panel3")
					Verify.expect(image.Size):toBe(D2(engine, 0, 20, 0, 20))
				end
				Verify.expect((names({ third[7], third[8], third[9], third[10] })))
					:toBe("panel4top panel4right panel4bottom panel4left")
				expectBox(engine, third[8], { 0, 4, 1, -4 }, { 1, 0, 0, 2 }, { 1, 0 })
				expectBox(engine, third[9], { 1, -4, 0, 4 }, { 0, 2, 1, 0 }, { 0, 1 })
				selected:set(native)
				Verify.expect(#images(skin)):toBe(0)
				Verify.expect(#skin:GetChildren()):toBe(10)
				Verify.expect((target:HasTag("facet-skinned"))):toBe(false)
				selected:set(shapeA)
				local again = images(skin)
				Verify.expect(#again):toBe(5)
				Verify.expect(again[1]):toBe(first[1])
				Verify.expect(again[1].ScaleType):toBe(T.Enum.ScaleType.Slice)
				Verify.expect(again[1].TileSize):toBe(D2(engine, 1, 0, 1, 0))
				Verify.expect((target:HasTag("facet-skinned"))):toBe(true)
				stop()
				for _, image in third do
					Verify.expect((image.isDestroyed())):toBe(true)
				end
				runtime:dispose()
			end,
		})
	end)

	local function stateArt(): any
		local package = themes.neutralPackage()
		package.assets = {
			a = { content = "rbxassetid://21", sliceCenter = { x0 = 4, y0 = 4, x1 = 12, y1 = 12 }, sliceScale = 2 },
			b = { content = "rbxassetid://22" },
			c = { content = "rbxassetid://23", sliceCenter = { x0 = 2, y0 = 2, x1 = 6, y1 = 6 } },
			d = { content = "rbxassetid://24" },
			e = { content = "rbxassetid://25" },
			f = { content = "rbxassetid://26" },
		} :: any
		return package
	end

	local function imageProperties(image: any): string
		local out = {}
		for _, key in
			{
				"Name",
				"Image",
				"Size",
				"Position",
				"AnchorPoint",
				"ScaleType",
				"TileSize",
				"SliceCenter",
				"SliceScale",
				"ResampleMode",
				"ZIndex",
				"BackgroundTransparency",
				"Visible",
			}
		do
			table.insert(out, key .. "=" .. tostring(image[key]))
		end
		return table.concat(out, ";")
	end

	verifyHarness:suite("theme layer values and states", function()
		verifyHarness:case(
			"gives every layer its own package values and lets the skinned tag suppress the native plate",
			{
				id = "native_parity_strength_themepkg::theme layer values and states::gives every layer its own package values and lets the skinned tag suppress the native plate",
				run = function()
					local package = stateArt()
					package.chrome.control = {
						kind = "layered",
						layers = {
							{ kind = "fill", asset = { default = "a", pressed = "b" } } :: FixtureThemeTypes.SkinLayer,
							{ kind = "frame" :: "frame", asset = "c" },
							{ kind = "tile" :: "tile", asset = "d", tileSize = { w = 16, h = 8 } },
							{ kind = "corners", asset = { default = "e", pressed = "f" }, size = 10 },
						},
					} :: any
					local neutral = themes.neutralPackage()
					local theme = Compose.cell(package)
					local engine, runtime, UI = world({ theme = theme })
					local T = engine.types
					local stop, node: any = runtime.mount(function()
						return UI.Button({ label = "Save" })
					end, engine.new("Folder"))
					local skin = find(node, "Skin")
					local layers = images(skin)
					Verify.expect(#layers):toBe(7)
					Verify.expect((names({ layers[1], layers[2], layers[3] }))):toBe("control1 control2 control3")
					Verify.expect(layers[1].Image):toBe("rbxassetid://21")
					Verify.expect(layers[1].ScaleType):toBe(T.Enum.ScaleType.Slice)
					Verify.expect(layers[1].SliceCenter):toBe(T.Rect.new(4, 4, 12, 12))
					Verify.expect(layers[1].SliceScale):toBe(2)
					Verify.expect(layers[2].Image):toBe("rbxassetid://23")
					Verify.expect(layers[2].SliceCenter):toBe(T.Rect.new(2, 2, 6, 6))
					Verify.expect(layers[2].SliceScale):toBe(1)
					Verify.expect(layers[3].Image):toBe("rbxassetid://24")
					Verify.expect(layers[3].ScaleType):toBe(T.Enum.ScaleType.Tile)
					Verify.expect(layers[3].TileSize):toBe(D2(engine, 0, 16, 0, 8))
					for index = 4, 7 do
						Verify.expect(layers[index].Image):toBe("rbxassetid://25")
						Verify.expect(layers[index].Size):toBe(D2(engine, 0, 10, 0, 10))
					end
					Verify.expect((node:HasTag("facet-skinned"))):toBe(true)
					node.GuiState = T.Enum.GuiState.Press
					Verify.expect(layers[1].Image):toBe("rbxassetid://22")
					Verify.expect(layers[1].ScaleType):toBe(T.Enum.ScaleType.Stretch)
					Verify.expect(layers[1].SliceScale):toBe(1)
					Verify.expect(layers[2].Image):toBe("rbxassetid://23")
					Verify.expect(layers[3].Image):toBe("rbxassetid://24")
					for index = 4, 7 do
						Verify.expect(layers[index].Image):toBe("rbxassetid://26")
					end
					node.GuiState = T.Enum.GuiState.Idle
					Verify.expect(layers[1].Image):toBe("rbxassetid://21")
					Verify.expect(layers[1].SliceScale):toBe(2)
					local sheet, stopSheet = sheetFor(engine, runtime, package)
					local skinned = ruleNode(sheet, ".facet-skinned")
					Verify.expect(skinned:GetProperties().BackgroundTransparency):toBe(1)
					for _, selector in
						{
							".facet-button",
							".facet-control",
							".facet-panel",
							".facet-field",
							".facet-badge",
							".facet-surface",
						}
					do
						local plate
						for _, rule in sheet:GetChildren() do
							if rule.Selector == selector and rule:GetProperties().BackgroundTransparency ~= nil then
								plate = rule
							end
						end
						Verify.expect(plate:GetProperties().BackgroundTransparency):toBe(0)
						Verify.expect(`{selector}: {skinned.Priority > plate.Priority}`):toBe(`{selector}: true`)
					end
					for _, selector in
						{ ".facet-appearance-utility:Hover", ".facet-segment-current", ".facet-tab-filled" }
					do
						Verify.expect(`{selector}: {skinned.Priority > ruleNode(sheet, selector).Priority}`)
							:toBe(`{selector}: true`)
					end
					stopSheet()
					theme:set(neutral)
					Verify.expect((node:HasTag("facet-skinned"))):toBe(false)
					Verify.expect(#images(skin)):toBe(0)
					theme:set(package)
					Verify.expect((node:HasTag("facet-skinned"))):toBe(true)
					Verify.expect(images(skin)[1]):toBe(layers[1])
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("selects state art with one grammar on a recipe and on a layer", {
			id = "native_parity_strength_themepkg::theme layer values and states::selects state art with one grammar on a recipe and on a layer",
			run = function()
				local engine, runtime = world()
				local full = { default = "a", hover = "b", pressed = "c", selected = "d", disabled = "e" }
				local partial = { default = "a", pressed = "c" }
				local expected = {
					default = "rbxassetid://21",
					hover = "rbxassetid://22",
					pressed = "rbxassetid://23",
					selected = "rbxassetid://24",
					disabled = "rbxassetid://25",
				}
				for _, map in { full, partial } :: { { [string]: string } } do
					local package = stateArt()
					package.chrome.control = { kind = "nineSlice", asset = map } :: any
					package.chrome.field = { kind = "layered", layers = { { kind = "fill", asset = map } } } :: any
					local definedPackage, report = themes.define(assert(package))
					Verify.expect(report.ok):toBe(true)
					for _, state in STATES do
						local want = if map == full
								or state == "pressed"
								or state == "default"
							then expected[state]
							else expected.default
						local recipe, stopRecipe = skinOf(engine, runtime, definedPackage, "control", { state = state })
						local layer, stopLayer = skinOf(engine, runtime, definedPackage, "field", { state = state })
						Verify.expect(`recipe {state}: {recipe:FindFirstChild("control1").Image}`)
							:toBe(`recipe {state}: {want}`)
						Verify.expect(`layer {state}: {layer:FindFirstChild("field1").Image}`)
							:toBe(`layer {state}: {want}`)
						Verify.expect(
							imageProperties(recipe:FindFirstChild("control1"))
								== string.gsub(imageProperties(layer:FindFirstChild("field1")), "field1", "control1")
						):toBe(true)
						stopRecipe()
						stopLayer()
					end
				end
				runtime:dispose()
				local package = stateArt()
				package.chrome.control = { kind = "nineSlice", asset = full } :: any
				local enabled, selected = Compose.cell(true), Compose.cell(false)
				local buttonEngine, buttonRuntime, UI = world({ theme = package })
				local T = buttonEngine.types
				local stop, node = buttonRuntime.mount(function()
					return UI.Button({ label = "Go", enabled = enabled, selected = selected })
				end, buttonEngine.new("Folder"))
				local image = find(node, "control1")
				Verify.expect(image.Image):toBe(expected.default)
				selected:set(true)
				Verify.expect(image.Image):toBe(expected.selected)
				node.GuiState = T.Enum.GuiState.Hover
				Verify.expect(image.Image):toBe(expected.hover)
				node.GuiState = T.Enum.GuiState.Press
				Verify.expect(image.Image):toBe(expected.pressed)
				enabled:set(false)
				Verify.expect(image.Image):toBe(expected.disabled)
				enabled:set(true)
				Verify.expect(image.Image):toBe(expected.pressed)
				stop()
				buttonRuntime:dispose()
			end,
		})

		verifyHarness:case("compiles a bare-string recipe unchanged and draws it like its default-only map", {
			id = "native_parity_strength_themepkg::theme layer values and states::compiles a bare-string recipe unchanged and draws it like its default-only map",
			run = function()
				local engine, runtime = world()
				local function variant(asset: any): any
					local package = stateArt()
					package.chrome.control = { kind = "nineSlice", asset = asset, contentInsets = { left = 4 } } :: any
					package.chrome.field = { kind = "layered", layers = { { kind = "fill", asset = asset } } } :: any
					return package
				end
				local bareDefinition = variant("a")
				local bare, bareReport = themes.define(bareDefinition)
				local mapped = themes.define(variant({ default = "a" }))
				Verify.expect(bareReport.ok):toBe(true)
				Verify.expect((assert(bare).chrome :: any).control.asset):toBe("a")
				Verify.expect((type((assert(bare).chrome :: any).field.layers[1].asset))):toBe("string")
				Verify.expect((assert(bare).chrome :: any).control.contentInsets.left):toBe(4)
				Verify.expect((assert(bare).assets :: any).a.sliceScale):toBe(2)
				Verify.expect((assert(bare).assets :: any).a.content):toBe("rbxassetid://21")
				for _, slot in { "control", "field" } do
					for _, state in STATES do
						local left, stopLeft = skinOf(engine, runtime, bare, slot, { state = state })
						local right, stopRight = skinOf(engine, runtime, mapped, slot, { state = state })
						Verify.expect(#images(left)):toBe(1)
						Verify.expect((imageProperties(images(left)[1]))):toBe(imageProperties(images(right)[1]))
						Verify.expect(images(left)[1].Image):toBe("rbxassetid://21")
						stopLeft()
						stopRight()
					end
				end
				local neutralSheet, stopNeutral = sheetFor(engine, runtime, mapped)
				local bareSheet, stopBare = sheetFor(engine, runtime, bare)
				local secondSheet, stopSecond = sheetFor(engine, runtime, themes.define(variant("a")))
				local expected = rulesSignature(neutralSheet)
				local signatures = { rulesSignature(bareSheet), rulesSignature(secondSheet) }
				for _, signature in signatures do
					Verify.expect(#signature):toBe(#expected)
					for index, line in expected do
						Verify.expect(signature[index]):toBe(line)
					end
				end
				for index, line in signatures[1] do
					Verify.expect(signatures[2][index]):toBe(line)
				end
				stopNeutral()
				stopBare()
				stopSecond()
				runtime:dispose()
			end,
		})

		verifyHarness:case("dresses a circle Button from the ordinary control slot with zero padding", {
			id = "native_parity_strength_themepkg::theme layer values and states::dresses a circle Button from the ordinary control slot with zero padding",
			run = function()
				local package = stateArt()
				package.chrome.control = {
					kind = "nineSlice",
					asset = { default = "a", pressed = "b" },
					contentInsets = { left = 20, right = 20 },
				} :: any
				local engine, runtime, UI = world({ theme = package })
				local T = engine.types
				local circle, rect
				local stop = runtime.mount(function()
					circle = UI.Button({ label = "...", shape = "circle" :: "circle" })
					rect = UI.Button({ label = "Save" })
					return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({ circle :: unknown, rect })
				end, engine.new("Folder"))
				for _, node in { circle, rect } do
					local skin = find(node, "Skin")
					Verify.expect(skin ~= nil):toBe(true)
					Verify.expect((names(images(skin)))):toBe("control1")
					Verify.expect(images(skin)[1].Image):toBe("rbxassetid://21")
					Verify.expect((node:HasTag("facet-skinned"))):toBe(true)
				end
				Verify.expect((circle:HasTag("facet-shape-circle"))):toBe(true)
				Verify.expect((rect:HasTag("facet-shape-circle"))):toBe(false)
				Verify.expect(circle.Size.X.Offset):toBe(circle.Size.Y.Offset)
				Verify.expect(circle:FindFirstChildWhichIsA("UICorner").CornerRadius):toBe(T.UDim.new(1, 0))
				circle.GuiState = T.Enum.GuiState.Press
				Verify.expect(images(find(circle, "Skin"))[1].Image):toBe("rbxassetid://22")
				Verify.expect(images(find(rect, "Skin"))[1].Image):toBe("rbxassetid://21")
				local sheet, stopSheet = sheetFor(engine, runtime, package)
				for _, suffix in { "::UIPadding", " > UIPadding" } do
					local circleRule = ruleNode(sheet, ".facet-shape-circle" .. suffix)
					local buttonRule = ruleNode(sheet, ".facet-button" .. suffix)
					for _, side in { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" } do
						Verify.expect(circleRule:GetProperties()[side]):toBe(T.UDim.new(0, 0))
					end
					Verify.expect(buttonRule:GetProperties().PaddingLeft):toBe(T.UDim.new(0, 32))
					Verify.expect(circleRule.Priority > buttonRule.Priority):toBe(true)
				end
				stopSheet()
				stop()
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("theme sheet paint", function()
		verifyHarness:case("paints a translucent scrim from every shipped palette onto a presented modal", {
			id = "native_parity_strength_themepkg::theme sheet paint::paints a translucent scrim from every shipped palette onto a presented modal",
			run = function()
				Verify.expect(#SHIPPED):toBe(8)
				local neutralOpacity = (themes.neutralPackage().style.themes[1].extra :: any).scrimOpacity
				for _, name in SHIPPED do
					local package = built(name)
					local engine, runtime, UI = world({ theme = package })
					for _, palette in package.style.themes do
						local sheet, stop = sheetFor(engine, runtime, package, { theme = palette.name })
						local scrim = style(sheet, ".facet-scrim")
						local opacity = (palette.extra :: any).scrimOpacity or neutralOpacity
						Verify.expect(`{name}/{palette.name}: {scrim.BackgroundTransparency}`)
							:toBe(`{name}/{palette.name}: {1 - opacity}`)
						Verify.expect(scrim.BackgroundTransparency > 0 and scrim.BackgroundTransparency < 1):toBe(true)
						Verify.expect(scrim.BackgroundColor3):toBe(engine.types.Color3.new(0, 0, 0))
						stop()
					end
					local presented = Compose.cell(true)
					local stop, screen: any = runtime.mount(function()
						return ((runtime.constructors.ScreenGui :: unknown) :: ScreenGuiConstructor)({
							UI.Alert({
								isPresented = presented,
								title = "Leave?",
								actions = {
									{ id = "stay", label = "Stay", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
								},
							}),
						})
					end, engine.new("Folder"))
					local catcher = find(screen, "DismissOutside")
					Verify.expect(`{name}: {catcher:HasTag("facet-scrim")}`):toBe(`{name}: true`)
					Verify.expect(catcher.BackgroundTransparency):toBe(engine.new("TextButton").BackgroundTransparency)
					stop()
					runtime:dispose()
				end
			end,
		})

		verifyHarness:case("selects each declared palette by name and the default without one on a single sheet", {
			id = "native_parity_strength_themepkg::theme sheet paint::selects each declared palette by name and the default without one on a single sheet",
			run = function()
				local engine, runtime = world()
				for _, name in { "classic_desktop", "fantasy_ornate", "fantasy_parchment" } do
					local package = built(name)
					Verify.expect(#package.style.themes):toBe(2)
					local selection = Compose.cell(nil :: string?)
					local sheet, stop = sheetFor(engine, runtime, package, { theme = selection })
					local rules = sheet:GetChildren()
					local surfaces: { [string]: any } = {}
					local defaultSurface
					for _, palette in package.style.themes do
						surfaces[palette.name] = color(engine, palette.colors.surface)
						if palette.name == package.style.defaultTheme then
							defaultSurface = surfaces[palette.name]
						end
					end
					Verify.expect(style(sheet, ".facet-surface").BackgroundColor3):toBe(defaultSurface)
					for _, palette in package.style.themes do
						selection:set(palette.name)
						Verify.expect(style(sheet, ".facet-surface").BackgroundColor3):toBe(surfaces[palette.name])
						Verify.expect(style(sheet, ".facet-text").TextColor3)
							:toBe(color(engine, palette.colors.content))
						Verify.expect(style(sheet, ".facet-accent").BackgroundColor3)
							:toBe(color(engine, palette.colors.accent))
					end
					Verify.expect(surfaces[package.style.themes[1].name] ~= surfaces[package.style.themes[2].name])
						:toBe(true)
					selection:set(nil)
					Verify.expect(style(sheet, ".facet-surface").BackgroundColor3):toBe(defaultSurface)
					selection:set("Sepia")
					local fallback = style(sheet, ".facet-surface").BackgroundColor3
					Verify.expect(
						fallback == surfaces[package.style.themes[1].name]
							or fallback == surfaces[package.style.themes[2].name]
					):toBe(true)
					Verify.expect(#sheet:GetChildren()):toBe(#rules)
					for index, rule in sheet:GetChildren() do
						Verify.expect(rule):toBe(rules[index])
					end
					stop()
				end
				runtime:dispose()
			end,
		})

		verifyHarness:case("carries chrome contentInsets into panel, field, badge and button padding rules", {
			id = "native_parity_strength_themepkg::theme sheet paint::carries chrome contentInsets into panel, field, badge and button padding rules",
			run = function()
				local engine, runtime = world()
				local T = engine.types
				local package = stateArt()
				package.chrome.panel = {
					kind = "nineSlice",
					asset = "c",
					contentInsets = { top = 4, right = 6, bottom = 8, left = 10 },
				} :: any
				package.chrome.field = {
					kind = "nineSlice",
					asset = "c",
					contentInsets = { top = 3, right = 14, bottom = 5, left = 16 },
				} :: any
				package.chrome.badge = {
					kind = "nineSlice",
					asset = "c",
					contentInsets = { top = 2, right = 11, bottom = 6, left = 4 },
				} :: any
				package.chrome.control = {
					kind = "nineSlice",
					asset = "c",
					contentInsets = { top = 12, right = 9, bottom = 13, left = 18 },
				} :: any
				local sheet, stop = sheetFor(engine, runtime, package)
				local expected: { [string]: { number } } = {
					panel = { 16, 16, 16, 16 },
					field = { 16, 14, 3, 5 },
					badge = { 8, 11, 3, 6 },
					button = { 30, 21, 12, 13 },
				}
				for role, sides in expected do
					for _, selector in { ".facet-" .. role .. "::UIPadding", ".facet-" .. role .. " > UIPadding" } do
						local padding = style(sheet, selector)
						Verify.expect(
							`{selector} {padding.PaddingLeft} {padding.PaddingRight} {padding.PaddingTop} {padding.PaddingBottom}`
						):toBe(
							`{selector} {T.UDim.new(0, sides[1])} {T.UDim.new(0, sides[2])} {T.UDim.new(0, sides[3])} {T.UDim.new(
								0,
								sides[4]
							)}`
						)
					end
				end
				Verify.expect(style(sheet, ".facet-button-described::UIPadding").PaddingTop):toBe(T.UDim.new(0, 22))
				Verify.expect(style(sheet, ".facet-button-described::UIPadding").PaddingBottom):toBe(T.UDim.new(0, 23))
				Verify.expect(style(sheet, ".facet-busy::UIPadding").PaddingRight):toBe(T.UDim.new(0, 41))
				Verify.expect(style(sheet, ".facet-disclosure::UIPadding").PaddingRight):toBe(T.UDim.new(0, 41))
				stop()
				local ornate, stopOrnate = sheetFor(engine, runtime, built("fantasy_ornate"))
				Verify.expect(style(ornate, ".facet-panel::UIPadding").PaddingTop):toBe(T.UDim.new(0, 30))
				Verify.expect(style(ornate, ".facet-field > UIPadding").PaddingLeft):toBe(T.UDim.new(0, 12))
				Verify.expect(style(ornate, ".facet-badge::UIPadding").PaddingTop):toBe(T.UDim.new(0, 5))
				Verify.expect(style(ornate, ".facet-button::UIPadding").PaddingLeft):toBe(T.UDim.new(0, 26))
				stopOrnate()
				local plain, stopPlain = sheetFor(engine, runtime, themes.neutralPackage())
				Verify.expect(style(plain, ".facet-panel::UIPadding").PaddingLeft):toBe(T.UDim.new(0, 16))
				Verify.expect(style(plain, ".facet-badge::UIPadding").PaddingTop):toBe(T.UDim.new(0, 3))
				Verify.expect(style(plain, ".facet-button::UIPadding").PaddingLeft):toBe(T.UDim.new(0, 12))
				stopPlain()
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("theme package data", function()
		verifyHarness:case("keeps accepted packages recursively frozen and independent of neutral copies", {
			id = "native_parity_strength_themepkg::theme package data::keeps accepted packages recursively frozen and independent of neutral copies",
			run = function()
				local first, second = themes.neutralPackage(), themes.neutralPackage()
				Verify.expect(first ~= second):toBe(true)
				Verify.expect(first.style ~= second.style):toBe(true)
				Verify.expect(first.style.themes[1].colors ~= second.style.themes[1].colors):toBe(true)
				Verify.expect(first.metrics.typography.body ~= second.metrics.typography.body):toBe(true)
				Verify.expect((table.isfrozen(first))):toBe(false)
				first.metrics.typography.body.size = 40
				(first.style.themes[1].colors :: any).accent = { r = 0, g = 0, b = 0 }
				first.metrics.controlSizes.regular.height = 99
				Verify.expect(second.metrics.typography.body.size):toBe(16)
				Verify.expect(themes.neutralPackage().metrics.typography.body.size):toBe(16)
				Verify.expect(themes.neutralPackage().metrics.controlSizes.regular.height):toBe(44)
				local fromDefault = themes.define({ identity = { id = "fresh" } } :: any)
				Verify.expect(assert(fromDefault).metrics.typography.body.size):toBe(16)
				Verify.expect(assert(fromDefault).metrics.controlSizes.regular.height):toBe(44)
				local definition = themes.neutralPackage()
				definition.rules = { { selector = ".game", properties = { BackgroundTransparency = 0.5 } } } :: any
				assert(definition.chrome).panel = { kind = "native", contentInsets = { top = 4 } } :: any
				local package = themes.define(definition)
				Verify.expect(frozenPath(package, "package", {}) or "frozen"):toBe("frozen")
				Verify.expect(themes.define(definition) ~= package):toBe(true)
				for _, write in
					{
						function()
							(package :: any).identity.id = "changed"
						end,
						function()
							(assert(package).style.themes[1].colors :: any).accent = { r = 1, g = 0, b = 0 }
						end,
						function()
							(assert(package).rules :: any)[1].properties.BackgroundTransparency = 0
						end,
						function()
							(assert(package).chrome :: any).panel.contentInsets.top = 9
						end,
						function()
							table.insert(assert(package).style.themes, assert(package).style.themes[1])
						end,
					}
				do
					Verify.expect((pcall(write))):toBe(false)
				end
				(definition.rules :: any)[1].properties.BackgroundTransparency = 0.9
				(definition.chrome :: any).panel.contentInsets.top = 20
				definition.style.themes[1].colors.content = { r = 0.5, g = 0.5, b = 0.5 }
				Verify.expect((assert(package).rules :: any)[1].properties.BackgroundTransparency):toBe(0.5)
				Verify.expect((assert(package).chrome :: any).panel.contentInsets.top):toBe(4)
				Verify.expect(assert(package).style.themes[1].colors.content.r):toBe(236 / 255)
				local derived = themes.define({ base = package, identity = { id = "derived" } } :: any)
				Verify.expect(assert(derived).identity.id):toBe("derived")
				Verify.expect(assert(package).identity.id):toBe("facet-neutral")
				Verify.expect(frozenPath(derived, "derived", {}) or "frozen"):toBe("frozen")
				Verify.expect(assert(derived).rules ~= assert(package).rules):toBe(true)
			end,
		})
	end)

	local function descendants(root: any): { any }
		return root:GetDescendants()
	end

	verifyHarness:suite("theme package install and swap", function()
		verifyHarness:case(
			"installs a package with one caller-owned sheet and StyleLink and removes every rule on teardown",
			{
				id = "native_parity_strength_themepkg::theme package install and swap::installs a package with one caller-owned sheet and StyleLink and removes every rule on teardown",
				run = function()
					local definition = themes.neutralPackage()
					definition.identity.id = "harbor"
					definition.metrics.controlSizes.regular.height = 52
					(definition.style.themes[1].colors :: any).surface = { r = 0.05, g = 0.1, b = 0.2 }
					local package = themes.define(definition)
					local engine, runtime, UI = world({ theme = package })
					local Host = (runtime.constructors :: unknown) :: RobloxHost
					local baseline = engine.census()
					local outerSheet: any, outerLink
					local stopOuter, outer: any = runtime.mount(function()
						outerSheet = themes.createStyleSheet(runtime, themes.neutralPackage(), { types = engine.types })
						outerLink = Host.StyleLink({ StyleSheet = Compose.static(outerSheet) })
						return Host.Frame({ outerSheet :: unknown, outerLink })
					end, engine.new("Folder"))
					local outerRules = outerSheet:GetChildren()
					local before = engine.census()
					local sheet: any, link, button
					local stop, root: any = runtime.mount(function()
						sheet = themes.createStyleSheet(
							runtime,
							package,
							{ types = engine.types, name = "FacetTheme harbor" }
						)
						link = Host.StyleLink({ StyleSheet = Compose.static(sheet) })
						button = UI.Button({ label = "Continue" })
						return Host.Frame({ sheet :: unknown, link, button })
					end, engine.new("Folder"))
					local links = {}
					for _, node in root:GetDescendants() do
						if node.ClassName == "StyleLink" then
							table.insert(links, node)
						end
					end
					Verify.expect(#links):toBe(1)
					Verify.expect(links[1].StyleSheet):toBe(sheet)
					Verify.expect(sheet.Parent):toBe(root)
					Verify.expect(sheet.Name):toBe("FacetTheme harbor")
					Verify.expect(style(sheet, ".facet-surface").BackgroundColor3)
						:toBe(engine.types.Color3.new(0.05, 0.1, 0.2))
					Verify.expect(button.Size.Y.Offset):toBe(52)
					local rules = sheet:GetChildren()
					Verify.expect(#rules > 30):toBe(true)
					Verify.expect(outerLink.StyleSheet):toBe(outerSheet)
					stop()
					Verify.expect((sheet.isDestroyed())):toBe(true)
					Verify.expect((((link :: unknown) :: Destroyable).isDestroyed())):toBe(true)
					Verify.expect((button.isDestroyed())):toBe(true)
					for _, rule in rules do
						Verify.expect((rule.isDestroyed())):toBe(true)
					end
					Verify.expect((outerSheet.isDestroyed())):toBe(false)
					Verify.expect((((outerLink :: unknown) :: Destroyable).isDestroyed())):toBe(false)
					Verify.expect(outerLink.StyleSheet):toBe(outerSheet)
					Verify.expect(outerSheet.Parent):toBe(outer)
					Verify.expect(#outerSheet:GetChildren()):toBe(#outerRules)
					for index, rule in outerSheet:GetChildren() do
						Verify.expect(rule):toBe(outerRules[index])
					end
					local after = engine.census()
					Verify.expect(after.live):toBe(before.live + 1)
					Verify.expect(after.connections):toBe(before.connections)
					stopOuter()
					for _, rule in outerRules do
						Verify.expect((rule.isDestroyed())):toBe(true)
					end
					Verify.expect(engine.census().live):toBe(baseline.live + 2)
					Verify.expect(engine.census().connections):toBe(baseline.connections)
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("retargets control metrics and paint from one package readable without rebuilding", {
			id = "native_parity_strength_themepkg::theme package install and swap::retargets control metrics and paint from one package readable without rebuilding",
			run = function()
				local theme = Compose.cell(themes.neutralPackage())
				local engine, runtime, UI = world({ theme = theme })
				local T, Host = engine.types, runtime.constructors
				local text = Compose.cell("Initial")
				local on = Compose.cell(true)
				local setups = 0
				local sheet: any, button, field, scroller
				local stop, root: any = runtime.mount(function()
					setups += 1
					sheet = themes.createStyleSheet(runtime, theme, { types = T, motionLevel = "none" })
					button = UI.Button({ label = "Save" })
					field = UI.TextInput({ value = text })
					scroller = Host.ScrollingFrame({ CanvasSize = T.UDim2.fromOffset(0, 2000) })
					return Host.Frame({
						sheet :: unknown,
						Host.StyleLink({ StyleSheet = Compose.static(sheet) }),
						button,
						field,
						UI.Toggle({ label = "Sound", value = on }),
						scroller,
					})
				end, engine.new("Folder"))
				scroller.CanvasPosition = T.Vector2.new(0, 137)
				field:CaptureFocus()
				field.Text = "Typed and uncommitted"
				local nodes = descendants(root)
				local rules = sheet:GetChildren()
				local byName: { [string]: any } = {}
				local priorityOf: { [string]: number } = {}
				for _, rule in rules do
					byName[rule.Name] = rule
					priorityOf[rule.Name] = rule.Priority
				end
				local made = #engine.made
				local function expectRetained(package: any, label: string)
					local palette = package.style.themes[1]
					for _, candidate in package.style.themes do
						if candidate.name == package.style.defaultTheme then
							palette = candidate
						end
					end
					Verify.expect(`{label}: {button.Size.Y.Offset}`)
						:toBe(`{label}: {package.metrics.controlSizes.regular.height}`)
					Verify.expect(style(sheet, ".facet-surface").BackgroundColor3)
						:toBe(color(engine, palette.colors.surface))
					Verify.expect(style(sheet, ".facet-text").TextColor3):toBe(color(engine, palette.colors.content))
					Verify.expect(style(sheet, ".facet-button").TextSize):toBe(package.metrics.typography.control.size)
					Verify.expect(setups):toBe(1)
					for _, rule in rules do
						Verify.expect(`{label} {rule.Name}: {rule.isDestroyed()}`):toBe(`{label} {rule.Name}: false`)
						Verify.expect(rule.Parent):toBe(sheet)
					end
					for _, node in nodes do
						Verify.expect((node.isDestroyed())):toBe(false)
						Verify.expect((node:IsDescendantOf(root))):toBe(true)
					end
					Verify.expect((field:IsFocused())):toBe(true)
					Verify.expect(field.Text):toBe("Typed and uncommitted")
					Verify.expect((text:peek())):toBe("Typed and uncommitted")
					Verify.expect(scroller.CanvasPosition.Y):toBe(137)
					Verify.expect((on:peek())):toBe(true)
				end
				local classic = built("classic_desktop")
				theme:set(classic)
				expectRetained(classic, "classic_desktop")
				Verify.expect(#engine.made):toBe(made)
				local current = descendants(root)
				Verify.expect(#current):toBe(#nodes)
				for index, node in nodes do
					Verify.expect(current[index]):toBe(node)
				end
				for index, rule in sheet:GetChildren() do
					Verify.expect(rule):toBe(rules[index])
				end
				local scifi = built("scifi_hud")
				theme:set(scifi)
				expectRetained(scifi, "scifi_hud")
				local created: { string } = {}
				for index = made + 1, #engine.made do
					local node = engine.made[index]
					if node.ClassName == "StyleRule" then
						table.insert(created, node.Selector)
					end
				end
				Verify.expect(#created):toBe(#sheet:GetChildren() - #rules)
				Verify.expect(#created > 0):toBe(true)
				for _, selector in created do
					Verify.expect(string.find(selector, "::UIGradient", 1, true) ~= nil):toBe(true)
				end
				for _, rule in sheet:GetChildren() do
					local previous = byName[rule.Name]
					if previous then
						Verify.expect(rule):toBe(previous)
						Verify.expect(rule.Priority % 10):toBe(0)
					end
				end
				local priorities: { [number]: boolean } = {}
				for _, rule in sheet:GetChildren() do
					Verify.expect(priorities[rule.Priority]):toBe(nil)
					priorities[rule.Priority] = true
				end
				Verify.expect(ruleNode(sheet, ".facet-skinned").Priority > ruleNode(sheet, ".facet-surface").Priority)
					:toBe(true)
				theme:set(classic)
				expectRetained(classic, "classic_desktop again")
				Verify.expect(#sheet:GetChildren()):toBe(#rules)
				for _, rule in sheet:GetChildren() do
					Verify.expect(rule):toBe(byName[rule.Name])
					Verify.expect(rule.Priority):toBe(priorityOf[rule.Name])
				end
				stop()
				for _, node in nodes do
					Verify.expect((node.isDestroyed())):toBe(true)
				end
				runtime:dispose()
			end,
		})
	end)

	local function galleryWorld(refused: { [string]: () -> (any, any) }): any
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local target, gui = engine.new("Folder"), engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
		function input:GetFocusedTextBox()
			return nil
		end
		local modules = {}
		for _, name in themePackages.files() do
			table.insert(modules, {
				Name = name,
				IsA = function(_, class: string)
					return class == "ModuleScript"
				end,
			})
		end
		for name in refused do
			table.insert(modules, {
				Name = name,
				IsA = function(_, class: string)
					return class == "ModuleScript"
				end,
			})
		end
		local packages = gallery.themePackages(themes, modules, function(module: any)
			if refused[module.Name] then
				return { build = refused[module.Name] }
			end
			return load(module.Name)
		end)
		local activations = 0
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
			theme = Compose.cell(themes.neutralPackage()),
			themeMode = Compose.cell("Dark"),
			demos = { { id = "first", title = "First", kind = "fixture" :: "fixture", module = "first" } },
		}
		local loaded = {}
		for name, package in packages do
			loaded[name] = package
		end
		ctx.packages = table.clone(packages)
		ctx.packages.Neutral = ctx.theme:peek()
		ctx.load = function()
			return {
				build = function(page: any)
					return {
						screen = function()
							return page.UI.Button({
								Name = "DemoAction",
								label = "Act",
								onActivate = function()
									activations += 1
								end,
							})
						end,
					}
				end,
			}
		end
		local sheet: any
		local stop, root: any = runtime.mount(function()
			gallery.configure(ctx)
			ctx.UI = Facet.controls(runtime, {
				types = engine.types,
				viewport = ctx.viewport,
				inputParent = target,
				services = { GuiService = gui, UserInputService = input },
				theme = ctx.theme,
				motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
					return if ctx.reducedMotion and use(ctx.reducedMotion) then "none" else "normal"
				end) :: unknown) :: MotionLevel,
			})
			sheet = themes.createStyleSheet(runtime, ctx.theme, { types = engine.types, theme = ctx.themeMode })
			return ctx.Host.ScreenGui "GalleryTest" {
				sheet :: unknown,
				ctx.Host.StyleLink({ StyleSheet = Compose.static(sheet) }),
				gallery.build(ctx),
			}
		end, target)
		return {
			engine = engine,
			ctx = ctx,
			root = root,
			sheet = sheet,
			loaded = loaded,
			activations = function()
				return activations
			end,
			stop = function()
				stop()
				runtime:dispose()
			end,
		}
	end

	local function refusedDefinition(): (any, any)
		local definition = themes.neutralPackage()
		definition.identity.id = "refused"
		definition.style.themes[1].colors.content = table.clone(definition.style.themes[1].colors.surface)
		return themes.define(definition)
	end

	verifyHarness:suite("gallery theme packages", function()
		verifyHarness:case("swaps through every shipped package and reports each new identity and palette", {
			id = "native_parity_strength_themepkg::gallery theme packages::swaps through every shipped package and reports each new identity and palette",
			run = function()
				local g = galleryWorld({})
				local ctx = g.ctx
				local loadedNames = {}
				for name in g.loaded do
					table.insert(loadedNames, name)
				end
				table.sort(loadedNames)
				Verify.expect((table.concat(loadedNames, " "))):toBe(table.concat(SHIPPED, " "))
				local demo = find(g.root, "DemoAction")
				Verify.expect(demo ~= nil):toBe(true)
				local rules = g.sheet:GetChildren()
				for round = 1, 2 do
					for _, name in SHIPPED do
						local result = gallery.dispatch(ctx, "theme", name)
						local package = ctx.theme:peek()
						Verify.expect(`{round} {name}: {result.ok} {result.theme}`):toBe(`{round} {name}: true {name}`)
						Verify.expect(result.palette):toBe(package.style.defaultTheme)
						Verify.expect(package.identity.id):toBe(load(name).id)
						Verify.expect(package):toBe(g.loaded[name])
						Verify.expect((ctx.themeName:peek())):toBe(name)
						local palette
						for _, candidate in package.style.themes do
							if candidate.name == package.style.defaultTheme then
								palette = candidate
							end
						end
						Verify.expect(style(g.sheet, ".facet-surface").BackgroundColor3)
							:toBe(color(g.engine, palette.colors.surface))
						Verify.expect((find(g.root, "DemoAction"))):toBe(demo)
						Verify.expect(result.error):toBe(nil)
					end
				end
				Verify.expect(g.sheet:GetChildren()[1]):toBe(rules[1])
				g.stop()
			end,
		})

		verifyHarness:case("refuses a package that fails its gate and keeps the running screen, theme and input", {
			id = "native_parity_strength_themepkg::gallery theme packages::refuses a package that fails its gate and keeps the running screen, theme and input",
			run = function()
				local refusedPackage, refusedReport = refusedDefinition()
				Verify.expect(refusedPackage):toBe(nil)
				Verify.expect(refusedReport.ok):toBe(false)
				local g = galleryWorld({
					refused_theme = refusedDefinition,
					throwing_theme = function(): (any, any)
						error("broken build")
					end,
				})
				local ctx = g.ctx
				Verify.expect(g.loaded.refused_theme):toBe(nil)
				Verify.expect(g.loaded.throwing_theme):toBe(nil)
				Verify.expect(g.loaded.fantasy_parchment_stub):toBe(nil)
				Verify.expect(gallery.dispatch(ctx, "theme", "classic_desktop").ok):toBe(true)
				local active = ctx.theme:peek()
				local demo = find(g.root, "DemoAction")
				local surface = style(g.sheet, ".facet-surface").BackgroundColor3
				local rules = g.sheet:GetChildren()
				demo.Activated.fire()
				Verify.expect((g.activations())):toBe(1)
				for _, name in { "refused_theme", "throwing_theme", "fantasy_parchment_stub", "missing" } do
					local result = gallery.dispatch(ctx, "theme", name)
					Verify.expect(`{name}: {result.ok}`):toBe(`{name}: false`)
					Verify.expect(result.theme):toBe("classic_desktop")
					Verify.expect(result.palette):toBe(active.style.defaultTheme)
					Verify.expect((ctx.theme:peek())):toBe(active)
					Verify.expect((ctx.themeName:peek())):toBe("classic_desktop")
					Verify.expect(style(g.sheet, ".facet-surface").BackgroundColor3):toBe(surface)
					Verify.expect((find(g.root, "DemoAction"))):toBe(demo)
					Verify.expect((ctx.errorMessage:peek())):toBe(nil)
				end
				for index, rule in g.sheet:GetChildren() do
					Verify.expect(rule):toBe(rules[index])
				end
				demo.Activated.fire()
				Verify.expect((g.activations())):toBe(2)
				Verify.expect(gallery.dispatch(ctx, "theme", "scifi_hud").ok):toBe(true)
				Verify.expect(ctx.theme:peek().identity.id):toBe("scifi-hud")
				Verify.expect((find(g.root, "DemoAction"))):toBe(demo)
				g.stop()
			end,
		})

		verifyHarness:case(
			"every skinned package keeps pictures inside the art carve, an art-less glyph unpadded and calendar choices tight",
			{
				id = "native_parity_strength_themepkg::gallery theme packages::every skinned package keeps pictures inside the art carve, an art-less glyph unpadded and calendar choices tight",
				run = function()
					local checked = 0
					for _, name in SHIPPED do
						local package = built(name)
						local skin = package.chrome and package.chrome.control
						if skin and skin.kind ~= "native" and skin.kind ~= "none" then
							checked += 1
							local carve = skin.contentInsets or {}
							local engine, runtime = world({ theme = package })
							local sheet, stop = sheetFor(engine, runtime, package)
							local padding = ruleNode(sheet, ".facet-button-media::UIPadding"):GetProperties()
							Verify.expect(
								`{name} {padding.PaddingLeft.Offset} {padding.PaddingRight.Offset} {padding.PaddingTop.Offset}`
							):toBe(`{name} {carve.left or 0} {carve.right or 0} {carve.top or 0}`)
							local glyph =
								ruleNode(sheet, ".facet-button-glyph.facet-appearance-utility::UIPadding"):GetProperties()
							Verify.expect(`{name} glyph {glyph.PaddingTop.Offset} {glyph.PaddingLeft.Offset}`)
								:toBe(`{name} glyph 0 0`)
							local choice = ruleNode(sheet, ".facet-calendar-choice::UIPadding"):GetProperties()
							local xs = (package.metrics.space or {}).xs or 4
							Verify.expect(`{name} choice {choice.PaddingLeft.Offset}`):toBe(`{name} choice {xs}`)
							stop()
							runtime:dispose()
						end
					end
					Verify.expect(checked > 0):toBe(true)
				end,
			}
		)

		verifyHarness:case("every package with panel art dresses a standard Notice in that art", {
			id = "native_parity_strength_themepkg::gallery theme packages::every package with panel art dresses a standard Notice in that art",
			run = function()
				local checked = 0
				for _, name in SHIPPED do
					local package = built(name)
					local art = package.chrome and package.chrome.panel
					if art and art.kind ~= "native" and art.kind ~= "none" then
						checked += 1
						local engine, runtime, UI = world({ theme = package })
						local stop, node: any = runtime.mount(function()
							return UI.Notice("Update")({ title = "Update", message = "A new track pack is ready." })
						end, engine.new("Folder"))
						local dressed = false
						for _, part in node:GetDescendants() do
							if part:HasTag("facet-skin-art-panel") then
								dressed = true
							end
						end
						Verify.expect(`{name} {dressed}`):toBe(`{name} true`)
						stop()
						runtime:dispose()
					end
				end
				Verify.expect(checked > 0):toBe(true)
			end,
		})

		verifyHarness:case("a filled tab paints its accent plate over the selected art, so its ink matches its plate", {
			id = "native_parity_strength_themepkg::gallery theme packages::a filled tab paints its accent plate over the selected art, so its ink matches its plate",
			run = function()
				local checked = 0
				for _, name in SHIPPED do
					local package = built(name)
					local plate = package.chrome and package.chrome.control
					local layers = if plate and plate.kind == "layered" then plate.layers or {} else { plate }
					local art = false
					for _, layer in layers do
						if layer and type(layer.asset) == "table" and layer.asset.selected ~= nil then
							art = true
						end
					end
					if art then
						checked += 1
						local engine, runtime = world({ theme = package })
						local sheet, stop = sheetFor(engine, runtime, package)
						local hidden = ruleNode(sheet, ".facet-tab-filled > #SkinBoundary")
						local shown = ruleNode(sheet, ".facet-skinned.facet-selected > #SkinBoundary")
						Verify.expect(`{name} {hidden.Priority > shown.Priority}`):toBe(`{name} true`)
						stop()
						runtime:dispose()
					end
				end
				Verify.expect(checked > 0):toBe(true)
			end,
		})
	end)

	verifyHarness:suite("transparent native chrome", function()
		verifyHarness:case("hides the shadow when a native control has no opaque plate", {
			id = "native_parity_strength_themepkg::transparent native chrome::hides the shadow when a native control has no opaque plate",
			run = function()
				local engine, runtime, UI = world({ theme = built("glossy_mobile") })
				local stop, node = runtime.mount(function()
					return UI.Button { label = "Choice" }
				end, engine.new("ScreenGui"))
				local shadow = node:FindFirstChild("ChromeShadow")
				Verify.expect(shadow ~= nil):toBe(true)
				node.BackgroundTransparency = 1
				Verify.expect(shadow.Transparency):toBe(1)
				node.BackgroundTransparency = 0
				Verify.expect(shadow.Transparency):toBe(0.35)
				stop()
				runtime:dispose()
			end,
		})
	end)
end
