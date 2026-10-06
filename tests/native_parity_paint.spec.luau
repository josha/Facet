--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local ThemeTypes = require("../src/ui/theme_types")
	local FixtureNavigationTypes = require("../src/ui/navigation_types")

	local fs = require("@lune/fs")
	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
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

	local function hasRule(sheet: any, selector: string): boolean
		for _, node in sheet:GetChildren() do
			if node.Selector == selector then
				return true
			end
		end
		return false
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

	local function tagged(root: any, tag: string): { any }
		local out = {}
		if root:HasTag(tag) then
			table.insert(out, root)
		end
		for _, node in root:GetDescendants() do
			if node:HasTag(tag) then
				table.insert(out, node)
			end
		end
		return out
	end

	local function color(engine: any, value: any): any
		return engine.types.Color3.new(value.r, value.g, value.b)
	end

	local function neutralColors(): ({ [string]: any }, { [string]: any })
		local palette = themes.neutralPackage().style.themes[1]
		return palette.colors, assert(palette.extra)
	end

	local SHIPPED = {
		"classic_desktop",
		"compact_pointer",
		"fantasy_ornate",
		"fantasy_parchment",
		"glossy_mobile",
		"glossy_touch",
		"pixel_quest",
		"scifi_hud",
	}

	local function shipped(name: string): (any, any)
		local module: any = (require :: any)("../examples/themes/" .. name)
		local package, report = module.build(themes)
		assert(report.ok, name .. " did not build")
		return package, module
	end

	local function paletteOf(package: any, palette: any): ({ [string]: any }, { [string]: any })
		local colors, extra = neutralColors()
		local mergedColors, mergedExtra = table.clone(colors), table.clone(extra)
		for key, value in palette.colors or {} do
			mergedColors[key] = value
		end
		for key, value in palette.extra or {} do
			mergedExtra[key] = value
		end
		return mergedColors, mergedExtra
	end

	local SCANNED_CALLS: { [string]: number? } = { styled = nil, paintedPart = 3 }

	local function scanTags(
		source: string,
		literals: { [string]: boolean },
		prefixes: { [string]: boolean }
	): { string }
		local dynamic = {}
		for literal in string.gmatch(source, '"(facet%-[%w%-]*)"') do
			if string.sub(literal, -1) == "-" then
				prefixes[literal] = true
			else
				literals[literal] = true
			end
		end
		for name in { styled = true, paintedPart = true } :: { [string]: boolean } do
			local position = 1
			while true do
				local start, finish = string.find(source, "[%.%s%(]" .. name .. "%(", position)
				if not start then
					break
				end
				local depth, index, args, current = 1, assert(finish) + 1, {}, ""
				while depth > 0 do
					local char = string.sub(source, index, index)
					if char == '"' then
						local close = assert(string.find(source, '"', index + 1, true))
						current ..= string.sub(source, index, close)
						index = close + 1
						continue
					end
					if char == "(" or char == "{" or char == "[" then
						depth += 1
					elseif char == ")" or char == "}" or char == "]" then
						depth -= 1
					end
					if depth == 1 and char == "," then
						table.insert(args, current)
						current = ""
					elseif depth > 0 then
						current ..= char
					end
					index += 1
				end
				table.insert(args, current)
				local argument = args[SCANNED_CALLS[name] or #args]
				position = assert(finish) + 1
				if argument == nil or string.sub(source, math.max(1, start - 8), start) == "function " then
					continue
				end
				local strings = {}
				for value in string.gmatch(argument, '"([^"]*)"') do
					table.insert(strings, value)
				end
				if #strings == 0 then
					table.insert(dynamic, (string.gsub(string.gsub(argument, "%s+", " "), "^ ", "")))
				elseif string.find(argument, "..", 1, true) then
					prefixes["facet-" .. string.lower(strings[1])] = true
				else
					for _, value in strings do
						literals["facet-" .. string.lower(value)] = true
					end
				end
			end
		end
		return dynamic
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

	verifyHarness:suite("native parity paint", function()
		verifyHarness:case(
			"compiles the button role and appearance vocabulary to palette rules above their base states",
			{
				id = "native_parity_paint::native parity paint::compiles the button role and appearance vocabulary to palette rules above their base states",
				run = function()
					local h = harness()
					local colors, extra = neutralColors()
					local package = Compose.cell(themes.neutralPackage())
					local sheet, stop = sheetFor(h, package)
					local function expectColor(selector: string, property: string, value: any)
						Verify.expect(style(sheet, selector)[property]):toBe(color(h.engine, value))
					end
					expectColor(".facet-role-destructive", "BackgroundColor3", colors.danger)
					expectColor(".facet-role-destructive", "TextColor3", colors.onDanger)
					expectColor(".facet-role-destructive:Hover", "BackgroundColor3", colors.danger)
					expectColor(".facet-role-destructive:Press", "BackgroundColor3", colors.danger)
					expectColor(".facet-role-destructive >> .facet-button-caption", "TextColor3", colors.onDanger)
					expectColor(".facet-role-cancel >> .facet-button-caption", "TextColor3", extra.contentSecondary)
					expectColor(".facet-role-onIndicator >> .facet-button-caption", "TextColor3", colors.onAccent)
					expectColor(".facet-accent", "BackgroundColor3", colors.accent)
					expectColor(".facet-accent", "TextColor3", colors.onAccent)
					expectColor(".facet-accent >> .facet-button-caption", "TextColor3", colors.onAccent)
					expectColor(".facet-appearance-soft", "BackgroundColor3", colors.accent)
					Verify.expect(style(sheet, ".facet-appearance-soft").BackgroundTransparency):toBe(0.8)
					Verify.expect(style(sheet, ".facet-appearance-soft:Hover").BackgroundTransparency):toBe(0.7)
					Verify.expect(style(sheet, ".facet-appearance-soft:Press").BackgroundTransparency):toBe(0.6)
					expectColor(".facet-appearance-soft >> .facet-button-caption", "TextColor3", colors.accent)
					expectColor(".facet-appearance-soft >> .facet-icon", "ImageColor3", colors.accent)
					Verify.expect(style(sheet, ".facet-appearance-utility").BackgroundTransparency):toBe(1)
					expectColor(".facet-appearance-utility:Hover", "BackgroundColor3", extra.controlHover)
					Verify.expect(style(sheet, ".facet-appearance-utility:Hover").BackgroundTransparency):toBe(0)
					expectColor(".facet-appearance-utility:Press", "BackgroundColor3", extra.controlPressed)
					Verify.expect(style(sheet, ".facet-appearance-link").BackgroundTransparency):toBe(1)
					expectColor(".facet-appearance-link", "TextColor3", colors.accent)
					expectColor(".facet-appearance-link >> .facet-button-caption", "TextColor3", colors.accent)
					expectColor(".facet-appearance-link >> .facet-icon", "ImageColor3", colors.accent)
					Verify.expect(style(sheet, ".facet-appearance-link::UIPadding").PaddingLeft)
						:toBe(h.engine.types.UDim.new(0, 0))
					expectColor(".facet-quiet-destructive", "TextColor3", colors.danger)
					expectColor(".facet-quiet-destructive >> .facet-button-caption", "TextColor3", colors.danger)
					expectColor(".facet-selected", "BackgroundColor3", extra.controlSelected)
					expectColor(".facet-selected", "TextColor3", colors.content)
					Verify.expect(style(sheet, ".facet-disabled").TextTransparency):toBe(extra.disabledContentOpacity)
					Verify.expect(style(sheet, ".facet-disabled >> .facet-button-caption").TextTransparency)
						:toBe(extra.disabledContentOpacity)
					expectColor(".facet-button:Hover", "BackgroundColor3", extra.controlHover)
					expectColor(".facet-button:Press", "BackgroundColor3", extra.controlPressed)
					local function priority(selector: string): number
						return ruleNode(sheet, selector).Priority
					end
					for _, base in
						{
							".facet-role-destructive",
							".facet-appearance-soft",
							".facet-appearance-utility",
							".facet-appearance-link",
						}
					do
						for _, state in { ":Hover", ":Press" } do
							Verify.expect(priority(base .. state) > priority(base)):toBe(true)
							Verify.expect(priority(base .. state) > priority(".facet-button" .. state)):toBe(true)
						end
					end
					Verify.expect(priority(".facet-button:Hover") > priority(".facet-button")):toBe(true)
					Verify.expect(priority(".facet-quiet-destructive") > priority(".facet-appearance-utility"))
						:toBe(true)
					Verify.expect(
						priority(".facet-quiet-destructive >> .facet-button-caption")
							> priority(".facet-appearance-link >> .facet-button-caption")
					):toBe(true)
					local destructive = ruleNode(sheet, ".facet-role-destructive")
					local retuned = themes.neutralPackage()
					retuned.style.themes[1].colors.danger = { r = 0.5, g = 0, b = 0.1 }
					package:set(retuned)
					Verify.expect((ruleNode(sheet, ".facet-role-destructive"))):toBe(destructive)
					Verify.expect(destructive:GetProperties().BackgroundColor3)
						:toBe(h.engine.types.Color3.new(0.5, 0, 0.1))
					stop()
					h.dispose()
				end,
			}
		)

		verifyHarness:case("tags each button role, appearance and corner choice for the matching rule", {
			id = "native_parity_paint::native parity paint::tags each button role, appearance and corner choice for the matching rule",
			run = function()
				local h = harness()
				local role, appearance = Compose.cell("destructive"), Compose.cell("standard")
				local root, stop = mount(h, function()
					return h.Host.Frame({
						h.UI.Button({ Name = "Reactive", label = "Delete", role = role, appearance = appearance }) :: unknown,
						h.UI.Button({ Name = "Pill", label = "Pill", corners = "pill" :: "pill" }),
						h.UI.Button({ Name = "Square", label = "Square", corners = "square" :: "square" }),
					})
				end)
				local button = find(root, "Reactive")
				Verify.expect((button:HasTag("facet-button"))):toBe(true)
				Verify.expect((button:HasTag("facet-role-destructive"))):toBe(true)
				Verify.expect((button:HasTag("facet-role-default"))):toBe(false)
				local expected = {
					standard = {},
					emphasis = { "facet-accent" },
					soft = { "facet-appearance-soft" },
					utility = { "facet-appearance-utility", "facet-quiet-destructive" },
					link = { "facet-appearance-link", "facet-quiet-destructive" },
				}
				local all = {
					"facet-accent",
					"facet-appearance-soft",
					"facet-appearance-utility",
					"facet-appearance-link",
					"facet-quiet-destructive",
				}
				for _, name in { "emphasis", "soft", "utility", "link", "standard" } do
					appearance:set(name)
					for _, tag in all do
						Verify.expect((button:HasTag(tag))):toBe(table.find(expected[name], tag) ~= nil)
					end
				end
				appearance:set("utility")
				role:set("cancel")
				Verify.expect((button:HasTag("facet-role-cancel"))):toBe(true)
				Verify.expect((button:HasTag("facet-role-destructive"))):toBe(false)
				Verify.expect((button:HasTag("facet-quiet-destructive"))):toBe(false)
				role:set("onIndicator")
				Verify.expect((button:HasTag("facet-role-onIndicator"))):toBe(true)
				Verify.expect((button:HasTag("facet-role-cancel"))):toBe(false)
				Verify.expect(find(root, "Pill"):FindFirstChildWhichIsA("UICorner").CornerRadius)
					:toBe(h.engine.types.UDim.new(1, 0))
				Verify.expect(find(root, "Square"):FindFirstChildWhichIsA("UICorner").CornerRadius)
					:toBe(h.engine.types.UDim.new(0, 0))
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("moves the picker current-option tags with the selection and the indicator choice", {
			id = "native_parity_paint::native parity paint::moves the picker current-option tags with the selection and the indicator choice",
			run = function()
				local h = harness()
				local colors = neutralColors()
				local segmented, inline = Compose.cell("a"), Compose.cell("a")
				local indicator = Compose.cell("automatic")
				local options = { { value = "a", label = "A" }, { value = "b", label = "B" } }
				local root, stop = mount(h, function()
					return h.Host.Frame({
						h.Host.Frame({
							Name = "Segmented",
							h.UI.Picker({
								selected = segmented,
								style = "segmented" :: "segmented",
								indicator = indicator,
								options = options,
							}),
						}) :: unknown,
						h.Host.Frame({
							Name = "Inline",
							h.UI.Picker({ selected = inline, style = "inline" :: "inline", options = options }),
						}),
					})
				end)
				local a, b = find(find(root, "Segmented"), "a"), find(find(root, "Segmented"), "b")
				Verify.expect((a:HasTag("facet-segment"))):toBe(true)
				Verify.expect((a:HasTag("facet-segment-current"))):toBe(true)
				Verify.expect((a:HasTag("facet-selected"))):toBe(true)
				Verify.expect((b:HasTag("facet-segment-current"))):toBe(false)
				Verify.expect((b:HasTag("facet-selected"))):toBe(false)
				segmented:set("b")
				Verify.expect((find(find(root, "Segmented"), "a"))):toBe(a)
				Verify.expect((a:HasTag("facet-segment-current"))):toBe(false)
				Verify.expect((a:HasTag("facet-selected"))):toBe(false)
				Verify.expect((b:HasTag("facet-segment-current"))):toBe(true)
				Verify.expect((b:HasTag("facet-selected"))):toBe(true)
				indicator:set("none")
				Verify.expect((b:HasTag("facet-segment-current"))):toBe(true)
				Verify.expect((b:HasTag("facet-selected"))):toBe(true)
				Verify.expect((find(root, "SelectionIndicator"))):toBe(nil)
				indicator:set("underline")
				Verify.expect((b:HasTag("facet-segment-current"))):toBe(false)
				Verify.expect((b:HasTag("facet-selected"))):toBe(false)
				Verify.expect((find(b, "SelectionIndicator"):HasTag("facet-selection-indicator"))):toBe(true)
				indicator:set("pill")
				Verify.expect((b:HasTag("facet-segment-current"))):toBe(true)
				Verify.expect((find(root, "SelectionIndicator"))):toBe(nil)
				local inlineA, inlineB = find(find(root, "Inline"), "a"), find(find(root, "Inline"), "b")
				Verify.expect((inlineA:HasTag("facet-choice"))):toBe(true)
				Verify.expect((inlineA:HasTag("facet-choice-current"))):toBe(true)
				Verify.expect((inlineA:HasTag("facet-segment-current"))):toBe(false)
				Verify.expect((inlineB:HasTag("facet-choice-current"))):toBe(false)
				inline:set("b")
				Verify.expect((inlineA:HasTag("facet-choice-current"))):toBe(false)
				Verify.expect((inlineB:HasTag("facet-choice-current"))):toBe(true)
				local sheet, stopSheet = sheetFor(h, themes.neutralPackage())
				Verify.expect(style(sheet, ".facet-segment-current").BackgroundColor3)
					:toBe(color(h.engine, colors.accent))
				Verify.expect(style(sheet, ".facet-segment-current").BackgroundTransparency):toBe(0)
				Verify.expect(style(sheet, ".facet-segment-current >> .facet-button-caption").TextColor3)
					:toBe(color(h.engine, colors.onAccent))
				Verify.expect(style(sheet, ".facet-choice-current").BackgroundColor3)
					:toBe(color(h.engine, colors.accent))
				Verify.expect(style(sheet, ".facet-choice-current >> .facet-button-caption").TextColor3)
					:toBe(color(h.engine, colors.accent))
				Verify.expect(style(sheet, ".facet-selection-indicator").BackgroundColor3)
					:toBe(color(h.engine, colors.accent))
				Verify.expect(
					ruleNode(sheet, ".facet-segment-current").Priority
						> ruleNode(sheet, ".facet-segment:Hover").Priority
				)
					:toBe(true)
				stopSheet()
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("keeps the picker menu catcher invisible at every background preference", {
			id = "native_parity_paint::native parity paint::keeps the picker menu catcher invisible at every background preference",
			run = function()
				local h = harness()
				local presented = Compose.cell(false)
				local _, stop = mount(h, function()
					return h.UI.Picker({
						selected = Compose.cell("a"),
						style = "menu" :: "menu",
						isPresented = presented,
						options = {
							{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
							{ value = "b", label = "B" } :: FixtureNavigationTypes.PickerOption<any>,
						},
					})
				end)
				presented:set(true)
				local catchers = {}
				for _, node in h.engine.made do
					if node.Name == "DismissOutside" and not node:isDestroyed() then
						table.insert(catchers, node)
					end
				end
				Verify.expect(#catchers):toBe(1)
				local catcher = catchers[1]
				Verify.expect((catcher:HasTag("facet-scrim"))):toBe(false)
				for _, preference in { 1, 0, 0.5, 0 / 0 } do
					h.gui.PreferredTransparency = preference
					Verify.expect(catcher.BackgroundTransparency):toBe(1)
				end
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("marks the selected tab by placement and indicator choice", {
			id = "native_parity_paint::native parity paint::marks the selected tab by placement and indicator choice",
			run = function()
				local h = harness()
				local selection, indicator, placement =
					Compose.cell("one"), Compose.cell("automatic"), Compose.cell("topBar")
				local root, stop = mount(h, function()
					return h.UI.TabView({
						selection = selection,
						indicator = indicator,
						placement = placement,
						tabs = {
							{
								id = "one",
								label = "One",
								content = function(): Instance
									return h.Host.Frame({})
								end,
							} :: FixtureNavigationTypes.Tab,
							{
								id = "two",
								label = "Two",
								content = function(): Instance
									return h.Host.Frame({})
								end,
							} :: FixtureNavigationTypes.Tab,
						},
					})
				end)
				local function tab(id: string): any
					for _, node in root:GetDescendants() do
						if
							node:HasTag("facet-tab-item")
							and node:GetAttribute("FacetLabel") == (if id == "one" then "One" else "Two")
						then
							return node
						end
					end
					error("no tab " .. id)
				end
				local one, two = tab("one"), tab("two")
				Verify.expect((one:HasTag("facet-tab-current"))):toBe(true)
				Verify.expect((two:HasTag("facet-tab-current"))):toBe(false)
				Verify.expect((find(one, "SelectionIndicator"):HasTag("facet-selection-indicator"))):toBe(true)
				Verify.expect((find(two, "SelectionIndicator"))):toBe(nil)
				Verify.expect((one:HasTag("facet-tab-filled"))):toBe(false)
				selection:set("two")
				Verify.expect((find(one, "SelectionIndicator"))):toBe(nil)
				Verify.expect(find(two, "SelectionIndicator") ~= nil):toBe(true)
				Verify.expect((two:HasTag("facet-tab-current"))):toBe(true)
				indicator:set("pill")
				Verify.expect((find(root, "SelectionIndicator"))):toBe(nil)
				Verify.expect((two:HasTag("facet-selected"))):toBe(true)
				indicator:set("none")
				Verify.expect((find(root, "SelectionIndicator"))):toBe(nil)
				Verify.expect((two:HasTag("facet-selected"))):toBe(false)
				indicator:set("automatic")
				placement:set("bottomBar")
				Verify.expect((find(root, "SelectionIndicator"))):toBe(nil)
				Verify.expect((two:HasTag("facet-tab-filled"))):toBe(true)
				Verify.expect((one:HasTag("facet-tab-filled"))):toBe(false)
				placement:set("sidebar")
				Verify.expect((two:HasTag("facet-tab-filled"))):toBe(true)
				indicator:set("none")
				Verify.expect((two:HasTag("facet-tab-filled"))):toBe(false)
				Verify.expect((two:HasTag("facet-tab-current"))):toBe(true)
				local colors = neutralColors()
				local sheet, stopSheet = sheetFor(h, themes.neutralPackage())
				Verify.expect(style(sheet, ".facet-tab-filled").BackgroundColor3):toBe(color(h.engine, colors.accent))
				Verify.expect(style(sheet, ".facet-tab-filled >> .facet-button-caption").TextColor3)
					:toBe(color(h.engine, colors.onAccent))
				Verify.expect(style(sheet, ".facet-tab-current >> .facet-button-caption").TextColor3)
					:toBe(color(h.engine, colors.content))
				stopSheet()
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("paints every value-control own slot solid in every shipped package and palette", {
			id = "native_parity_paint::native parity paint::paints every value-control own slot solid in every shipped package and palette",
			run = function()
				local h = harness()
				local accentSlots = { "slider-thumb", "slider-fill", "toggle-mark", "selection-indicator", "fill" }
				local controlSlots =
					{ "slider-rail", "slider-track", "toggle", "toggle-indicator", "stepper-track", "track", "badge" }
				for _, name in SHIPPED do
					local package = shipped(name)
					for _, palette in package.style.themes do
						local colors, extra = paletteOf(package, palette)
						local sheet, stop = sheetFor(h, package, { theme = palette.name })
						for _, slot in accentSlots do
							local properties = style(sheet, ".facet-" .. slot)
							Verify.expect(properties.BackgroundTransparency):toBe(0)
							Verify.expect(properties.BackgroundColor3):toBe(color(h.engine, colors.accent))
						end
						for _, slot in controlSlots do
							local properties = style(sheet, ".facet-" .. slot)
							Verify.expect(properties.BackgroundTransparency):toBe(0)
							Verify.expect(properties.BackgroundColor3):toBe(color(h.engine, extra.control))
						end
						Verify.expect(style(sheet, ".facet-toggle-on").BackgroundColor3)
							:toBe(color(h.engine, colors.accent))
						Verify.expect(style(sheet, ".facet-toggle-on >> .facet-toggle-mark").BackgroundColor3)
							:toBe(color(h.engine, colors.onAccent))
						Verify.expect(style(sheet, ".facet-toggle-check").ImageColor3)
							:toBe(color(h.engine, colors.onAccent))
						Verify.expect(style(sheet, ".facet-level-on").BackgroundColor3)
							:toBe(color(h.engine, colors.accent))
						Verify.expect(style(sheet, ".facet-stepper-track::UICorner").CornerRadius)
							:toBe(h.engine.types.UDim.new(0, package.metrics.radii.control))
						Verify.expect(
							ruleNode(sheet, ".facet-toggle-on").Priority
								> ruleNode(sheet, ".facet-toggle-indicator").Priority
						):toBe(true)
						stop()
					end
				end
				h.dispose()
			end,
		})

		verifyHarness:case("tags unskinned value-control slots for their own paint and keeps the tags when skinned", {
			id = "native_parity_paint::native parity paint::tags unskinned value-control slots for their own paint and keeps the tags when skinned",
			run = function()
				local function build(h: Harness)
					return mount(h, function()
						return h.Host.Frame({
							h.UI.Slider({ Name = "Slider", value = Compose.cell(0.5) }) :: unknown,
							h.UI.Toggle({ Name = "Switch", value = Compose.cell(true), label = "On" }),
							h.UI.Toggle({
								Name = "Box",
								value = Compose.cell(true),
								label = "Box",
								presentation = "checkbox" :: "checkbox",
							}),
							h.UI.Stepper({ Name = "Stepper", value = Compose.cell(2), min = 0, max = 5 }),
							h.UI.ProgressView({ Name = "Progress", value = 0.5 }),
						})
					end)
				end
				local plain = harness()
				local root, stop = build(plain)
				local slider = find(root, "Slider")
				Verify.expect((slider:HasTag("facet-slider"))):toBe(true)
				Verify.expect((find(slider, "Track"):HasTag("facet-slider-track"))):toBe(true)
				Verify.expect((find(slider, "Rail"):HasTag("facet-slider-rail"))):toBe(true)
				Verify.expect((find(slider, "Fill"):HasTag("facet-slider-fill"))):toBe(true)
				Verify.expect((find(slider, "Thumb"):HasTag("facet-slider-thumb"))):toBe(true)
				local switch = find(root, "Switch")
				local indicator = find(switch, "Indicator")
				Verify.expect((switch:HasTag("facet-toggle"))):toBe(true)
				Verify.expect((indicator:HasTag("facet-toggle-indicator"))):toBe(true)
				Verify.expect((indicator:HasTag("facet-toggle-switch"))):toBe(true)
				Verify.expect((indicator:HasTag("facet-toggle-on"))):toBe(true)
				Verify.expect((find(indicator, "Mark"):HasTag("facet-toggle-mark"))):toBe(true)
				Verify.expect((find(find(root, "Box"), "Indicator"):HasTag("facet-toggle-checkbox"))):toBe(true)
				Verify.expect((find(find(root, "Stepper"), "Controls"):HasTag("facet-stepper-track"))):toBe(true)
				Verify.expect((find(root, "Stepper"):HasTag("facet-stepper"))):toBe(true)
				Verify.expect((find(find(root, "Progress"), "Track"):HasTag("facet-track"))):toBe(true)
				Verify.expect(#tagged(find(root, "Progress"), "facet-fill")):toBe(1)
				Verify.expect(#tagged(root, "facet-skinned")):toBe(0)
				stop()
				plain.dispose()

				local package = themes.neutralPackage()
				package.assets = { art = { content = "rbxassetid://41" } }
				for _, slot in
					{ "sliderTrack", "sliderThumb", "barFill", "barTrack", "toggleTrack", "toggleKnob", "stepperPlate" }
				do
					assert(package.chrome)[slot] = { kind = "fill" :: "fill", asset = "art" }
				end
				local skinned = harness({ theme = package })
				local skinnedRoot, stopSkinned = build(skinned)
				local sheet, stopSheet = sheetFor(skinned, package)
				local expectations = {
					{ find(find(skinnedRoot, "Slider"), "Rail"), "facet-slider-rail" },
					{ find(find(skinnedRoot, "Slider"), "Thumb"), "facet-slider-thumb" },
					{ find(find(skinnedRoot, "Slider"), "Fill"), "facet-slider-fill" },
					{ find(find(skinnedRoot, "Switch"), "Indicator"), "facet-toggle-indicator" },
					{ find(find(skinnedRoot, "Switch"), "Mark"), "facet-toggle-mark" },
					{ find(find(skinnedRoot, "Progress"), "Track"), "facet-track" },
					{ find(skinnedRoot, "Stepper"), "facet-stepper" },
				}
				for _, entry in expectations do
					Verify.expect((entry[1]:HasTag(entry[2]))):toBe(true)
					Verify.expect((entry[1]:HasTag("facet-skinned"))):toBe(true)
				end
				local skinnedPriority = ruleNode(sheet, ".facet-skinned").Priority
				Verify.expect(style(sheet, ".facet-skinned").BackgroundTransparency):toBe(1)
				local checked = 0
				for _, node in tagged(skinnedRoot, "facet-skinned") do
					for _, tag in node:GetTags() do
						for _, rule in sheet:GetChildren() do
							if
								rule.Selector == "." .. tag
								and rule:GetProperties().BackgroundTransparency ~= nil
								and tag ~= "facet-skinned"
							then
								checked += 1
								Verify.expect(skinnedPriority > rule.Priority):toBe(true)
							end
						end
					end
				end
				Verify.expect(checked >= #expectations):toBe(true)
				stopSheet()
				stopSkinned()
				skinned.dispose()
			end,
		})

		verifyHarness:case("repaints corner radii and type roles in place when package metrics change", {
			id = "native_parity_paint::native parity paint::repaints corner radii and type roles in place when package metrics change",
			run = function()
				local h = harness()
				local UDim = h.engine.types.UDim
				local package = Compose.cell(themes.neutralPackage())
				local sheet, stop = sheetFor(h, package)
				local control, panel, sheetCorner =
					ruleNode(sheet, ".facet-button::UICorner"),
					ruleNode(sheet, ".facet-panel::UICorner"),
					ruleNode(sheet, ".facet-sheet::UICorner")
				local body, button = ruleNode(sheet, ".facet-type-body"), ruleNode(sheet, ".facet-button")
				local count = #sheet:GetChildren()
				Verify.expect(control:GetProperties().CornerRadius):toBe(UDim.new(0, 8))
				Verify.expect(panel:GetProperties().CornerRadius):toBe(UDim.new(0, 12))
				for _, role in
					{ "surface", "control", "field", "button", "badge", "track", "skeleton", "avatar", "tab" } :: { "avatar" | "badge" | "button" | "control" | "field" | "skeleton" | "surface" | "tab" | "track" }
				do
					Verify.expect(style(sheet, ".facet-" .. role .. "::UICorner").CornerRadius):toBe(UDim.new(0, 8))
				end
				Verify.expect(style(sheet, ".facet-sheet::UICorner").CornerRadius):toBe(UDim.new(0, 12))
				Verify.expect(style(sheet, ".facet-menu::UICorner").CornerRadius):toBe(UDim.new(0, 12))
				Verify.expect(style(sheet, ".facet-segmented::UICorner").CornerRadius):toBe(UDim.new(0, 10))
				local retuned = themes.neutralPackage()
				retuned.metrics.radii.control = 14
				retuned.metrics.typography.body.size = 19
				retuned.metrics.typography.control.size = 21
				package:set(retuned)
				Verify.expect((ruleNode(sheet, ".facet-button::UICorner"))):toBe(control)
				Verify.expect(control:GetProperties().CornerRadius):toBe(UDim.new(0, 14))
				Verify.expect(style(sheet, ".facet-stepper-track::UICorner").CornerRadius):toBe(UDim.new(0, 14))
				Verify.expect(style(sheet, ".facet-segmented::UICorner").CornerRadius):toBe(UDim.new(0, 16))
				Verify.expect(panel:GetProperties().CornerRadius):toBe(UDim.new(0, 12))
				Verify.expect((ruleNode(sheet, ".facet-type-body"))):toBe(body)
				Verify.expect(body:GetProperties().TextSize):toBe(19)
				Verify.expect(style(sheet, ".facet-text").TextSize):toBe(19)
				Verify.expect(button:GetProperties().TextSize):toBe(21)
				Verify.expect(style(sheet, ".facet-button-caption").TextSize):toBe(21)
				local panels = themes.neutralPackage()
				panels.metrics.radii.panel = 20
				package:set(panels)
				Verify.expect(panel:GetProperties().CornerRadius):toBe(UDim.new(0, 20))
				Verify.expect(sheetCorner:GetProperties().CornerRadius):toBe(UDim.new(0, 20))
				Verify.expect(control:GetProperties().CornerRadius):toBe(UDim.new(0, 8))
				panels = themes.neutralPackage()
				panels.metrics.radii.panel = 0
				package:set(panels)
				Verify.expect(panel:GetProperties().CornerRadius):toBe(UDim.new(0, 0))
				Verify.expect(#sheet:GetChildren()):toBe(count)
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("compiles every type role to native font rules and tags labels with their role", {
			id = "native_parity_paint::native parity paint::compiles every type role to native font rules and tags labels with their role",
			run = function()
				local h = harness()
				local _, extra = neutralColors()
				local package = Compose.cell(themes.neutralPackage())
				local sheet, stop = sheetFor(h, package)
				local sizes = {
					caption = 12,
					label = 14,
					body = 16,
					heading = 20,
					title = 24,
					control = 18,
					strong = 16,
					numeral = 18,
				}
				local weights = { strong = "SemiBold", numeral = "Bold", heading = "Bold", title = "Bold" }
				for _, role in themes.TYPE_ROLES do
					local properties = style(sheet, ".facet-type-" .. role)
					Verify.expect(properties.TextSize):toBe(sizes[role])
					Verify.expect(properties.LineHeight):toBe(1.2)
					Verify.expect(properties.FontFace):toBe(
						h.engine.types.Font.new(
							"rbxasset://fonts/families/BuilderSans.json",
							(h.engine.types.Enum.FontWeight :: any)[weights[role] or "Regular"],
							h.engine.types.Enum.FontStyle.Normal
						)
					)
					Verify.expect(properties.TextColor3)
						:toBe(if role == "caption" then color(h.engine, extra.contentSecondary) else nil)
				end
				Verify.expect(style(sheet, ".facet-button").TextSize):toBe(18)
				Verify.expect(style(sheet, ".facet-button-caption").FontFace)
					:toBe(style(sheet, ".facet-type-control").FontFace)
				Verify.expect(style(sheet, ".facet-validation").TextSize):toBe(12)
				Verify.expect(style(sheet, ".facet-shortcut-hint").TextSize):toBe(12)
				local edited = themes.neutralPackage()
				edited.metrics.typography.title = {
					size = 31,
					lineHeight = 1.4,
					font = { family = "rbxassetid://777", weight = "Heavy" :: "Heavy", style = "Italic" :: "Italic" } :: ThemeTypes.FontSpec,
				}
				edited.metrics.typography.caption.size = 11
				package:set(edited)
				local title = style(sheet, ".facet-type-title")
				Verify.expect(title.TextSize):toBe(31)
				Verify.expect(title.LineHeight):toBe(1.4)
				Verify.expect(title.FontFace):toBe(
					h.engine.types.Font.new(
						"rbxassetid://777",
						h.engine.types.Enum.FontWeight.Heavy,
						h.engine.types.Enum.FontStyle.Italic
					)
				)
				Verify.expect(style(sheet, ".facet-validation").TextSize):toBe(11)
				local role = Compose.cell("title")
				local root, stopLabels = mount(h, function()
					return h.Host.Frame({
						h.UI.Text({ Name = "Plain", text = "a" }) :: unknown,
						h.UI.Text({ Name = "Bound", text = "b", textRole = role }),
						h.UI.Text({ Name = "Fixed", text = "c", textRole = "numeral" :: "numeral" }),
					})
				end)
				Verify.expect((find(root, "Plain"):HasTag("facet-type-body"))):toBe(true)
				Verify.expect((find(root, "Plain"):HasTag("facet-text"))):toBe(true)
				Verify.expect((find(root, "Fixed"):HasTag("facet-type-numeral"))):toBe(true)
				local bound = find(root, "Bound")
				for _, next in themes.TYPE_ROLES do
					role:set(next)
					for _, other in themes.TYPE_ROLES do
						Verify.expect((bound:HasTag("facet-type-" .. other))):toBe(other == next)
					end
					Verify.expect((hasRule(sheet, ".facet-type-" .. next))):toBe(true)
				end
				Verify.expect(ruleNode(sheet, ".facet-type-title").Priority > ruleNode(sheet, ".facet-text").Priority)
					:toBe(true)
				stopLabels()
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("compiles palette chrome gradients to UIGradient rules and removes them with the palette", {
			id = "native_parity_paint::native parity paint::compiles palette chrome gradients to UIGradient rules and removes them with the palette",
			run = function()
				local h = harness()
				local package = themes.neutralPackage()
				local dark = package.style.themes[1]
				local light = table.clone(dark)
				light.name = "Light"
				dark.extra = table.clone(assert(dark.extra))
				assert(dark.extra).chromeGradient = {
					panel = {
						rotation = 45,
						stops = { { t = 0, r = 1, g = 0, b = 0 }, { t = 1, r = 0, g = 0, b = 1 } },
						alpha = { { t = 0, v = 0 }, { t = 1, v = 0.5 } },
					},
					control = { stops = { { t = 0, r = 1, g = 1, b = 1 }, { t = 1, r = 0, g = 0, b = 0 } } },
					badge = { stops = { { t = 0, r = 1, g = 1, b = 1 } } },
				}
				table.insert(package.style.themes, light)
				local defined = assert(themes.define(package))
				local palette = Compose.cell("Dark")
				local sheet, stop = sheetFor(h, defined, { theme = palette })
				local panel = style(sheet, ".facet-panel::UIGradient")
				Verify.expect(typeof(panel.Color)):toBe("ColorSequence")
				Verify.expect(#panel.Color.Keypoints):toBe(2)
				Verify.expect(panel.Color.Keypoints[1].Value):toBe(h.engine.types.Color3.new(1, 0, 0))
				Verify.expect(panel.Color.Keypoints[2].Value):toBe(h.engine.types.Color3.new(0, 0, 1))
				Verify.expect(panel.Rotation):toBe(45)
				Verify.expect(typeof(panel.Transparency)):toBe("NumberSequence")
				Verify.expect(panel.Transparency.Keypoints[2].Value):toBe(0.5)
				local control = style(sheet, ".facet-control::UIGradient")
				Verify.expect(control.Rotation):toBe(90)
				Verify.expect(control.Transparency):toBe(nil)
				Verify.expect((hasRule(sheet, ".facet-badge::UIGradient"))):toBe(false)
				local node = ruleNode(sheet, ".facet-panel::UIGradient")
				palette:set("Light")
				Verify.expect((node:isDestroyed())):toBe(true)
				Verify.expect((hasRule(sheet, ".facet-panel::UIGradient"))):toBe(false)
				Verify.expect((hasRule(sheet, ".facet-control::UIGradient"))):toBe(false)
				palette:set("Dark")
				Verify.expect(style(sheet, ".facet-panel::UIGradient").Rotation):toBe(45)
				stop()
				for _, name in { "scifi_hud", "glossy_mobile" } do
					local shipped, _ = shipped(name)
					for _, entry in shipped.style.themes do
						local gradients = (entry.extra or {}).chromeGradient
						Verify.expect(gradients ~= nil):toBe(true)
						local shippedSheet, stopShipped = sheetFor(h, shipped, { theme = entry.name })
						local compiled = 0
						for _, rule in shippedSheet:GetChildren() do
							if string.sub(rule.Selector, -12) == "::UIGradient" then
								compiled += 1
								Verify.expect(typeof(rule:GetProperties().Color)):toBe("ColorSequence")
							end
						end
						local declared = 0
						for _, gradient in gradients do
							declared += 1
							for _, stop in gradient.alpha or {} do
								Verify.expect(stop.v >= 0 and stop.v <= 0.35):toBe(true)
							end
						end
						Verify.expect(compiled):toBe(declared)
						Verify.expect(compiled >= if name == "scifi_hud" then 3 else 1):toBe(true)
						stopShipped()
					end
				end
				h.dispose()
			end,
		})

		verifyHarness:case("orders rule priority by declaration with states after rests and package rules last", {
			id = "native_parity_paint::native parity paint::orders rule priority by declaration with states after rests and package rules last",
			run = function()
				local h = harness()
				local package = themes.neutralPackage()
				package.rules = {
					{
						selector = ".game-x",
						properties = { BackgroundTransparency = 0.3 } :: ThemeTypes.RuleProperties,
					},
					{
						selector = ".facet-button",
						properties = { BackgroundColor3 = h.engine.types.Color3.new(1, 0, 1) } :: ThemeTypes.RuleProperties,
					},
				}
				local sheet, stop = sheetFor(h, package)
				local previous = -1
				local builtIn = 0
				for _, rule in sheet:GetChildren() do
					Verify.expect(rule.Priority > previous):toBe(true)
					previous = rule.Priority
					if
						rule.Selector ~= ".game-x"
						and not (
							rule.Selector == ".facet-button"
							and rule:GetProperties().BackgroundColor3 == h.engine.types.Color3.new(1, 0, 1)
						)
					then
						builtIn = math.max(builtIn, rule.Priority)
					end
				end
				local children = sheet:GetChildren()
				Verify.expect(children[#children - 1].Selector):toBe(".game-x")
				Verify.expect(children[#children].Selector):toBe(".facet-button")
				Verify.expect(children[#children - 1].Priority > builtIn):toBe(true)
				Verify.expect(ruleNode(sheet, ".facet-button").Priority):toBe(children[#children].Priority)
				local function first(selector: string): any
					for _, rule in children do
						if rule.Selector == selector then
							return rule
						end
					end
					return nil
				end
				Verify.expect(first(".facet-button:Hover").Priority > first(".facet-button").Priority):toBe(true)
				Verify.expect(first(".facet-skinned").Priority > first(".facet-button").Priority):toBe(true)
				Verify.expect(first(".facet-skinned").Priority > first(".facet-surface").Priority):toBe(true)
				Verify.expect(first(".facet-type-body").Priority > first(".facet-text").Priority):toBe(true)
				Verify.expect(first(".facet-selected").Priority > first(".facet-button:Press").Priority):toBe(true)
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("keeps an icon badge icon through reactive status paint and switches badge appearances", {
			id = "native_parity_paint::native parity paint::keeps an icon badge icon through reactive status paint and switches badge appearances",
			run = function()
				local h = harness()
				local colors, extra = neutralColors()
				local status, appearance = Compose.cell("neutral"), Compose.cell("status")
				local root, stop = mount(h, function()
					return h.Host.Frame({
						h.UI.Badge({ Name = "Iconic", label = "Ready", icon = "checkmark", status = status }) :: unknown,
						h.UI.Badge({ Name = "Live", label = "Live", status = "error", appearance = appearance }),
					})
				end)
				local pill = find(root, "Iconic")
				local icon = pill:FindFirstChildWhichIsA("ImageLabel")
				Verify.expect((icon:HasTag("facet-icon"))):toBe(true)
				Verify.expect((pill:HasTag("facet-badge"))):toBe(true)
				local statuses = { "neutral", "info", "success", "warning", "error", "accent" }
				for _, next in statuses do
					status:set(next)
					for _, other in statuses do
						Verify.expect((pill:HasTag("facet-status-" .. other))):toBe(other == next)
					end
					Verify.expect((pill:FindFirstChildWhichIsA("ImageLabel"))):toBe(icon)
					Verify.expect(icon.Image ~= ""):toBe(true)
				end
				local live = find(root, "Live")
				Verify.expect((live:HasTag("facet-badge-status"))):toBe(true)
				Verify.expect((find(live, "Status"):HasTag("facet-status-error"))):toBe(true)
				appearance:set("utility")
				Verify.expect((live:HasTag("facet-badge-utility"))):toBe(true)
				Verify.expect((live:HasTag("facet-badge-status"))):toBe(false)
				Verify.expect((find(live, "Status"))):toBe(nil)
				appearance:set("standard")
				Verify.expect((live:HasTag("facet-badge-standard"))):toBe(true)
				Verify.expect((live:HasTag("facet-badge-utility"))):toBe(false)
				local sheet, stopSheet = sheetFor(h, themes.neutralPackage())
				local partners: {
					[string]: { typeof(extra.contentSecondary) | typeof(colors.surface) }
						| { typeof(colors.accent) | typeof(colors.onAccent) }
						| { typeof(colors.success) | typeof(colors.onSuccess) }
						| { typeof(colors.warning) | typeof(colors.onWarning) }
						| { typeof(colors.danger) | typeof(colors.onDanger) },
				} =
					{
						neutral = { extra.contentSecondary, colors.surface },
						info = { colors.accent, colors.onAccent },
						success = { colors.success, colors.onSuccess },
						warning = { colors.warning, colors.onWarning },
						error = { colors.danger, colors.onDanger },
						accent = { colors.accent, colors.onAccent },
					}
				for name, pair in partners do
					Verify.expect(style(sheet, ".facet-status-" .. name).BackgroundColor3)
						:toBe(color(h.engine, pair[1]))
					Verify.expect(style(sheet, ".facet-status-" .. name .. " > .facet-icon").ImageColor3)
						:toBe(color(h.engine, pair[2]))
					Verify.expect(style(sheet, ".facet-status-" .. name .. " > .facet-text").TextColor3)
						:toBe(color(h.engine, pair[2]))
					Verify.expect(
						ruleNode(sheet, ".facet-status-" .. name).Priority > ruleNode(sheet, ".facet-badge").Priority
					)
						:toBe(true)
				end
				Verify.expect(style(sheet, ".facet-badge-utility").BackgroundTransparency):toBe(1)
				Verify.expect(style(sheet, ".facet-badge-utility > .facet-text").TextColor3)
					:toBe(color(h.engine, extra.contentSecondary))
				Verify.expect(style(sheet, ".facet-badge-status").BackgroundColor3):toBe(color(h.engine, extra.control))
				Verify.expect(
					ruleNode(sheet, ".facet-badge-utility").Priority > ruleNode(sheet, ".facet-status-error").Priority
				)
					:toBe(true)
				Verify.expect(style(sheet, ".facet-badge").BackgroundTransparency):toBe(0)
				stopSheet()
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("skins the badge seal from the package badge slot and removes it with the package", {
			id = "native_parity_paint::native parity paint::skins the badge seal from the package badge slot and removes it with the package",
			run = function()
				local package = themes.neutralPackage()
				package.assets = { seal = { content = "rbxassetid://77" } }
				assert(package.chrome).badge = {
					kind = "nineSlice" :: "nineSlice",
					asset = "seal",
					contentInsets = { top = 5, right = 5, bottom = 5, left = 5 },
				}
				local selected = Compose.cell(package)
				local h = harness({ theme = selected })
				local root, stop = mount(h, function()
					return h.UI.Badge({ Name = "Seal", label = "3" })
				end)
				local badge = find(root, "Seal")
				Verify.expect(find(badge, "badge1").Image):toBe("rbxassetid://77")
				Verify.expect(find(badge, "badge1").Visible):toBe(true)
				Verify.expect((badge:HasTag("facet-skinned"))):toBe(true)
				local sheet, stopSheet = sheetFor(h, package)
				Verify.expect(style(sheet, ".facet-badge::UIPadding").PaddingTop):toBe(h.engine.types.UDim.new(0, 5))
				Verify.expect(style(sheet, ".facet-badge::UIPadding").PaddingLeft):toBe(h.engine.types.UDim.new(0, 8))
				stopSheet()
				selected:set(themes.neutralPackage())
				Verify.expect((badge:HasTag("facet-skinned"))):toBe(false)
				local art = find(badge, "badge1")
				Verify.expect(art == nil or art.Visible == false):toBe(true)
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("blends a bound dimmed async image and restores it", {
			id = "native_parity_paint::native parity paint::blends a bound dimmed async image and restores it",
			run = function()
				local h = harness()
				local dimmed = Compose.cell(false)
				local root, stop = mount(h, function()
					return h.UI.AsyncImage({ Name = "Art", image = "rbxassetid://1", dimmed = dimmed })
				end)
				local image = find(find(root, "Art"), "Image")
				Verify.expect(image.ImageTransparency):toBe(0)
				dimmed:set(true)
				Verify.expect(image.ImageTransparency):toBe(0.35)
				dimmed:set(false)
				Verify.expect(image.ImageTransparency):toBe(0)
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("lets per-view slider images replace the theme skin on that node only", {
			id = "native_parity_paint::native parity paint::lets per-view slider images replace the theme skin on that node only",
			run = function()
				local package = themes.neutralPackage()
				package.assets = { thumb = { content = "rbxassetid://5" }, rail = { content = "rbxassetid://6" } }
				assert(package.chrome).sliderThumb = { kind = "nineSlice" :: "nineSlice", asset = "thumb" }
				assert(package.chrome).sliderTrack = { kind = "nineSlice" :: "nineSlice", asset = "rail" }
				for _, theme in { package, themes.neutralPackage() } do
					local h = harness({ theme = theme })
					local root, stop = mount(h, function()
						return h.Host.Frame({
							h.UI.Slider({
								Name = "Both",
								value = Compose.cell(0.5),
								thumbImage = "rbxassetid://9",
								trackImage = "rbxassetid://8",
							}) :: unknown,
							h.UI.Slider({
								Name = "ThumbOnly",
								value = Compose.cell(0.5),
								thumbImage = "rbxassetid://9",
							}),
						})
					end)
					local both = find(root, "Both")
					Verify.expect(find(find(both, "Thumb"), "Artwork").Image):toBe("rbxassetid://9")
					Verify.expect(find(find(both, "Rail"), "Artwork").Image):toBe("rbxassetid://8")
					Verify.expect((find(both, "sliderThumb1"))):toBe(nil)
					Verify.expect((find(both, "sliderTrack1"))):toBe(nil)
					Verify.expect((find(both, "Thumb"):HasTag("facet-slider-thumb"))):toBe(true)
					local thumbOnly = find(root, "ThumbOnly")
					Verify.expect(find(find(thumbOnly, "Thumb"), "Artwork").Image):toBe("rbxassetid://9")
					Verify.expect((find(thumbOnly, "sliderThumb1"))):toBe(nil)
					Verify.expect((find(find(thumbOnly, "Rail"), "Artwork"))):toBe(nil)
					if theme == package then
						Verify.expect(find(find(thumbOnly, "Rail"), "sliderTrack1").Image):toBe("rbxassetid://6")
						Verify.expect((find(thumbOnly, "Rail"):HasTag("facet-skinned"))):toBe(true)
					else
						Verify.expect((find(thumbOnly, "sliderTrack1"))):toBe(nil)
					end
					stop()
					h.dispose()
				end
			end,
		})

		verifyHarness:case("leaves icon tint and transparency to the style sheet", {
			id = "native_parity_paint::native parity paint::leaves icon tint and transparency to the style sheet",
			run = function()
				local writes: { string } = {}
				local package = themes.neutralPackage()
				local h = harness({ theme = package })
				local original = h.engine.new
				h.engine.onWrite(function(self, key, value)
					if self.ClassName == "ImageLabel" then
						table.insert(writes, key)
					end
				end)
				h.engine.new = function(className: string)
					local node = original(className)
					return node
				end
				local root, stop = mount(h, function()
					return h.Host.Frame({
						h.UI.Label({ title = "Close", icon = "close" }) :: unknown,
						h.UI.Button({ label = "Go", icon = "checkmark", role = "destructive" :: "destructive" }),
						h.UI.Badge({ label = "New", icon = "checkmark", status = "success" }),
					})
				end)
				local icons = tagged(root, "facet-icon")
				Verify.expect(#icons >= 3):toBe(true)
				Verify.expect(#writes > 0):toBe(true)
				Verify.expect((table.find(writes, "ImageColor3"))):toBe(nil)
				Verify.expect((table.find(writes, "ImageTransparency"))):toBe(nil)
				local colors = neutralColors()
				local sheet, stopSheet = sheetFor(h, package)
				Verify.expect(style(sheet, ".facet-icon").ImageColor3):toBe(color(h.engine, colors.content))
				Verify.expect(style(sheet, ".facet-icon").BackgroundTransparency):toBe(1)
				stopSheet()
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("tints framework icons with the content role of each palette and never leaves them white", {
			id = "native_parity_paint::native parity paint::tints framework icons with the content role of each palette and never leaves them white",
			run = function()
				local h = harness()
				local package = themes.neutralPackage()
				local dark = package.style.themes[1]
				local light = table.clone(dark)
				light.name = "Light"
				light.colors = table.clone(dark.colors)
				light.colors.content = { r = 0.1, g = 0.15, b = 0.2 }
				package.style.themes = { dark, light }
				local white = h.engine.types.Color3.new(1, 1, 1)
				for _, palette in package.style.themes do
					local colors = paletteOf(package, palette)
					local sheet, stop = sheetFor(h, package, { theme = palette.name })
					local tint = style(sheet, ".facet-icon").ImageColor3
					Verify.expect(tint):toBe(color(h.engine, colors.content))
					Verify.expect(tint == white):toBe(false)
					stop()
				end
				for _, name in SHIPPED do
					local shippedPackage = shipped(name)
					for _, palette in shippedPackage.style.themes do
						local colors = paletteOf(shippedPackage, palette)
						local sheet, stop = sheetFor(h, shippedPackage, { theme = palette.name })
						Verify.expect(style(sheet, ".facet-icon").ImageColor3):toBe(color(h.engine, colors.content))
						stop()
					end
				end
				h.dispose()
			end,
		})

		verifyHarness:case("re-letters the icon on a status plate with the plate partner color as a direct child", {
			id = "native_parity_paint::native parity paint::re-letters the icon on a status plate with the plate partner color as a direct child",
			run = function()
				local partners: { [string]: string } = {
					neutral = "surface",
					info = "onAccent",
					success = "onSuccess",
					warning = "onWarning",
					error = "onDanger",
					accent = "onAccent",
				}
				local h = harness({ theme = themes.neutralPackage() })
				local package = themes.neutralPackage()
				for _, palette in package.style.themes do
					local colors, extra = paletteOf(package, palette)
					local sheet, stop = sheetFor(h, package, { theme = palette.name })
					local base = ruleNode(sheet, ".facet-icon").Priority
					for status, partner in partners do
						local selector = ".facet-status-" .. status .. " > .facet-icon"
						local expected = colors[partner] or extra[partner]
						Verify.expect(expected ~= nil):toBe(true)
						Verify.expect(style(sheet, selector).ImageColor3):toBe(color(h.engine, expected))
						Verify.expect(ruleNode(sheet, selector).Priority > base):toBe(true)
						Verify.expect(
							ruleNode(sheet, selector).Priority > ruleNode(sheet, ".facet-icon-" .. status).Priority
						)
							:toBe(true)
					end
					stop()
				end
				local status = Compose.cell("warning")
				local root, stop = mount(h, function()
					return h.Host.Frame({
						h.UI.Badge({ Name = "Warn", label = "!", icon = "status.warning", status = status }) :: unknown,
						h.UI.Badge({ Name = "Fail", label = "!", icon = "status.error", status = "error" }),
					})
				end)
				for name, tag in { Warn = "facet-status-warning", Fail = "facet-status-error" } :: { [string]: string } do
					local plate = find(root, name)
					Verify.expect((plate:HasTag(tag))):toBe(true)
					local icons = tagged(plate, "facet-icon")
					Verify.expect(#icons):toBe(1)
					Verify.expect(icons[1].Parent):toBe(plate)
					Verify.expect(icons[1].ClassName):toBe("ImageLabel")
				end
				local warn = find(root, "Warn")
				local icon = tagged(warn, "facet-icon")[1]
				status:set("error")
				Verify.expect((warn:HasTag("facet-status-error"))):toBe(true)
				Verify.expect((warn:HasTag("facet-status-warning"))):toBe(false)
				Verify.expect(tagged(warn, "facet-icon")[1]):toBe(icon)
				Verify.expect(icon.Parent):toBe(warn)
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case(
			"keeps the selected label readable on the selection fill and its sampled art in every shipped theme",
			{
				id = "native_parity_paint::native parity paint::keeps the selected label readable on the selection fill and its sampled art in every shipped theme",
				run = function()
					local h = harness()
					for _, name in SHIPPED do
						local package = shipped(name)
						for _, palette in package.style.themes do
							local colors, extra = paletteOf(package, palette)
							local label = extra.onSelected or colors.content
							Verify.expect(contrast(label, extra.controlSelected) >= 4.5):toBe(true)
							local sheet, stop = sheetFor(h, package, { theme = palette.name })
							Verify.expect(style(sheet, ".facet-selected").TextColor3):toBe(color(h.engine, label))
							Verify.expect(style(sheet, ".facet-selected >> .facet-text").TextColor3)
								:toBe(color(h.engine, label))
							Verify.expect(style(sheet, ".facet-selected >> .facet-icon").ImageColor3)
								:toBe(color(h.engine, label))
							Verify.expect(style(sheet, ".facet-selected").BackgroundColor3)
								:toBe(color(h.engine, extra.controlSelected))
							stop()
						end
					end
					local serde = require("@lune/serde")
					local samples = serde.decode("json", fs.readFile("assets/themes/plate-samples.json")).samples
					local checked = 0
					for key, entry in samples do
						for _, sample in entry do
							Verify.expect((serde.hash("sha256", fs.readFile(sample.file)))):toBe(sample.sha256)
						end
						local plate = entry.selected
						if plate then
							local package = shipped((string.gsub(key, "-", "_")))
							local asset = package.chrome.control.asset
							local link = if type(asset) == "table" then asset.selected else nil
							local tint = if type(link) == "table" and link.tint
								then link.tint
								else { r = 1, g = 1, b = 1 }
							local art =
								{ r = plate.r / 255 * tint.r, g = plate.g / 255 * tint.g, b = plate.b / 255 * tint.b }
							for _, palette in package.style.themes do
								local colors, extra = paletteOf(package, palette)
								Verify.expect(contrast(extra.onSelected or colors.content, art) >= 4.5):toBe(true)
								checked += 1
							end
						end
					end
					Verify.expect(checked >= 4):toBe(true)
					h.dispose()
				end,
			}
		)

		verifyHarness:case("keeps a selected toggle row label on the content color over its clear row", {
			id = "native_parity_paint::native parity paint::keeps a selected toggle row label on the content color over its clear row",
			run = function()
				local h = harness()
				for _, name in SHIPPED do
					local package = shipped(name)
					for _, palette in package.style.themes do
						local colors = paletteOf(package, palette)
						local sheet, stop = sheetFor(h, package, { theme = palette.name })
						local row = style(sheet, ".facet-toggle-row")
						Verify.expect(row.BackgroundTransparency):toBe(1)
						Verify.expect(style(sheet, ".facet-toggle-row.facet-selected").TextColor3)
							:toBe(color(h.engine, colors.content))
						Verify.expect(style(sheet, ".facet-toggle-row.facet-selected >> .facet-text").TextColor3)
							:toBe(color(h.engine, colors.content))
						stop()
					end
				end
				h.dispose()
			end,
		})

		verifyHarness:case(
			"drops hover paint while touch is the preferred input, so a tapped control does not keep a hover tint",
			{
				id = "native_parity_paint::native parity paint::drops hover paint while touch is the preferred input, so a tapped control does not keep a hover tint",
				run = function()
					local h = harness()
					local hover = Compose.cell(true)
					local sheet, stop = sheetFor(h, themes.neutralPackage(), { hover = hover })
					Verify.expect((hasRule(sheet, ".facet-button:Hover"))):toBe(true)
					Verify.expect((hasRule(sheet, ".facet-button:Press"))):toBe(true)
					hover:set(false)
					for _, node in sheet:GetChildren() do
						Verify.expect((string.find(node.Selector, ":Hover", 1, true))):toBe(nil)
					end
					Verify.expect((hasRule(sheet, ".facet-button:Press"))):toBe(true)
					Verify.expect((hasRule(sheet, ".facet-button"))):toBe(true)
					hover:set(true)
					Verify.expect((hasRule(sheet, ".facet-button:Hover"))):toBe(true)
					stop()
					h.dispose()
				end,
			}
		)

		verifyHarness:case(
			"keeps touch hover rules out while only a modifier key is down, then follows a real key or the mouse",
			{
				id = "native_parity_paint::native parity paint::keeps touch hover rules out while only a modifier key is down, then follows a real key or the mouse",
				run = function()
					local h = harness()
					local E = h.engine.types.Enum
					local environment = (getfenv :: any)(0)
					local gui = h.engine.new("GuiService")
					local input = h.engine.new("UserInputService")
					local pressed = {}
					input.GetKeysPressed = function()
						return pressed
					end
					input.GetMouseButtonsPressed = function()
						return {}
					end
					input.PreferredInput = E.PreferredInput.Touch
					environment.game = {
						GetService = function(_, name: string)
							return if name == "UserInputService" then input else gui
						end,
					}
					local sheet, stop = sheetFor(h, themes.neutralPackage())
					environment.game = nil
					local function hovering(): boolean
						return hasRule(sheet, ".facet-button:Hover")
					end
					Verify.expect((hovering())):toBe(false)
					pressed = { { KeyCode = E.KeyCode.LeftSuper } }
					input.PreferredInput = E.PreferredInput.KeyboardAndMouse
					Verify.expect((hovering())):toBe(false)
					pressed = {}
					input.InputChanged:Fire({ UserInputType = E.UserInputType.MouseMovement })
					Verify.expect((hovering())):toBe(true)
					input.PreferredInput = E.PreferredInput.Touch
					Verify.expect((hovering())):toBe(false)
					pressed = { { KeyCode = E.KeyCode.LeftShift } }
					input.PreferredInput = E.PreferredInput.KeyboardAndMouse
					Verify.expect((hovering())):toBe(false)
					pressed = { { KeyCode = E.KeyCode.LeftShift }, { KeyCode = E.KeyCode.C } }
					input.InputBegan:Fire({ UserInputType = E.UserInputType.Keyboard, KeyCode = E.KeyCode.C })
					Verify.expect((hovering())):toBe(true)
					stop()
					h.dispose()
				end,
			}
		)

		verifyHarness:case("builds its hover source while a modifier is held and follows the next mouse move", {
			id = "native_parity_paint::native parity paint::builds its hover source while a modifier is held and follows the next mouse move",
			run = function()
				local h = harness()
				local E = h.engine.types.Enum
				local environment = (getfenv :: any)(0)
				local gui = h.engine.new("GuiService")
				local input = h.engine.new("UserInputService")
				local pressed = { { KeyCode = E.KeyCode.LeftShift } }
				input.GetKeysPressed = function()
					return pressed
				end
				input.GetMouseButtonsPressed = function()
					return {}
				end
				input.PreferredInput = E.PreferredInput.KeyboardAndMouse
				environment.game = {
					GetService = function(_, name: string)
						return if name == "UserInputService" then input else gui
					end,
				}
				local sheet, stop = sheetFor(h, themes.neutralPackage())
				environment.game = nil
				pressed = {}
				input.InputChanged:Fire({ UserInputType = E.UserInputType.MouseMovement })
				Verify.expect((hasRule(sheet, ".facet-button:Hover"))):toBe(true)
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("treats a garbage transparency preference as the identity", {
			id = "native_parity_paint::native parity paint::treats a garbage transparency preference as the identity",
			run = function()
				local h = harness()
				local preference = Compose.cell(1 :: any)
				local sheet, stop = sheetFor(h, themes.neutralPackage(), { preferredTransparency = preference })
				local authored = style(sheet, ".facet-scrim").BackgroundTransparency
				for _, value in { (0 / 0 :: any), "x", false, math.huge / math.huge } do
					preference:set(value)
					Verify.expect(style(sheet, ".facet-scrim").BackgroundTransparency):toBe(authored)
				end
				preference:set(-3)
				Verify.expect(style(sheet, ".facet-scrim").BackgroundTransparency):toBe(0)
				preference:set(7)
				Verify.expect(style(sheet, ".facet-scrim").BackgroundTransparency):toBe(authored)
				stop()
				local presented = Compose.cell(true)
				local root, stopAlert = mount(h, function()
					return h.UI.Alert({
						isPresented = presented,
						title = "Title",
						message = "Message",
						actions = {
							{ id = "ok", label = "OK", role = "default" :: "default" } :: FixtureNavigationTypes.AlertAction<any>,
						},
					})
				end)
				local catcher
				for _, node in h.engine.made do
					if node.Name == "DismissOutside" and not node:isDestroyed() then
						catcher = node
					end
				end
				Verify.expect(catcher ~= nil):toBe(true)
				h.gui.PreferredTransparency = 0 / 0
				local value = catcher.BackgroundTransparency
				Verify.expect(value == value):toBe(true)
				Verify.expect(root ~= nil):toBe(true)
				stopAlert()
				h.dispose()
			end,
		})

		verifyHarness:case("scales only the scrim backdrop by the transparency preference", {
			id = "native_parity_paint::native parity paint::scales only the scrim backdrop by the transparency preference",
			run = function()
				local h = harness()
				local package = themes.neutralPackage()
				package.rules = {
					{
						selector = ".game-glass",
						properties = { BackgroundTransparency = 0.5 } :: ThemeTypes.RuleProperties,
					},
				}
				local preference = Compose.cell(1)
				local sheet, stop = sheetFor(h, package, { preferredTransparency = preference })
				local before: { [any]: any } = {}
				for _, rule in sheet:GetChildren() do
					before[rule] = rule:GetProperties()
				end
				for _, value in { 0.5, 0 } do
					preference:set(value)
					local changed = {}
					for _, rule in sheet:GetChildren() do
						local properties = rule:GetProperties()
						for key, previous in before[rule] do
							if properties[key] ~= previous then
								table.insert(changed, rule.Selector .. "." .. key)
							end
						end
					end
					table.sort(changed)
					Verify.expect(changed):toEqual({
						".facet-scrim.BackgroundTransparency",
						".facet-scrim.facet-radial-scrim.BackgroundTransparency",
					})
					for _, selector in { ".facet-scrim", ".facet-scrim.facet-radial-scrim" } do
						Verify.expect(style(sheet, selector).BackgroundTransparency)
							:toBe(before[ruleNode(sheet, selector)].BackgroundTransparency * value)
					end
				end
				Verify.expect(style(sheet, ".facet-divider").BackgroundTransparency):toBe(0.92)
				Verify.expect(style(sheet, ".facet-appearance-soft").BackgroundTransparency):toBe(0.8)
				Verify.expect(style(sheet, ".facet-choice-current").BackgroundTransparency):toBe(0.82)
				Verify.expect(style(sheet, ".game-glass").BackgroundTransparency):toBe(0.5)
				Verify.expect(style(sheet, ".facet-disabled").TextTransparency):toBe(0.4)
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("insets and paints the recipe dividers from the installed theme", {
			id = "native_parity_paint::native parity paint::insets and paints the recipe dividers from the installed theme",
			run = function()
				local engine: any = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local gui = engine.new("GuiService")
				local theme = Compose.cell(themes.neutralPackage())
				local ctx: any = {
					Facet = Facet,
					Compose = Compose,
					runtime = runtime,
					Host = (runtime.constructors :: unknown) :: RobloxHost,
					types = engine.types,
					viewport = Compose.cell({ width = 1280, height = 720 }),
					inputTarget = engine.new("Folder"),
					guiService = gui,
					runService = { Heartbeat = engine.heartbeat },
					theme = theme,
					UI = Facet.controls(
						runtime,
						{
							types = engine.types,
							guiService = gui,
							services = { GuiService = gui },
							theme = theme,
							motionLevel = "none",
						} :: any
					),
				}
				local recipes: any = (require :: any)("../examples/gallery/scenarios/recipes_common")
				local built
				local stop, root: any = runtime.mount(function()
					built = recipes.build(ctx)
					return ctx.Host.ScreenGui("DemoScreen")({ built.screen() })
				end, engine.new("Folder"))
				local UDim = engine.types.UDim
				local Vector2 = engine.types.Vector2
				local function check(package: any, textAt: number)
					local hairline = package.metrics.strokes.hairline
					local expected: {
						[string]: { number }
							| { typeof(textAt) | number }
							| { number | typeof(textAt) }
							| { typeof(textAt) },
					} =
						{
							DividerFull = { 0, 0 },
							DividerLeading = { textAt, 0 },
							DividerTrailing = { 0, textAt },
							DividerBoth = { textAt, textAt },
							DividerHeavy = { 0, 0 },
						}
					for name, sides in expected do
						local divider = find(root, name)
						local row = find(divider, "Row")
						Verify.expect(find(row, "Icon") ~= nil):toBe(true)
						local title = find(row, "Title")
						row.AbsolutePosition = Vector2.new(40, 100)
						title.AbsolutePosition = Vector2.new(40 + textAt, 100)
						local padding = find(divider, "Pad"):FindFirstChildWhichIsA("UIPadding")
						Verify.expect(`{name} {padding.PaddingLeft.Offset},{padding.PaddingRight.Offset}`)
							:toBe(`{name} {sides[1]},{sides[2]}`)
						Verify.expect(padding.PaddingTop):toBe(UDim.new(0, 0))
						local line = find(divider, "Line")
						Verify.expect((line:HasTag("facet-divider"))):toBe(true)
						Verify.expect(line.Size.Y.Offset)
							:toBe(if name == "DividerHeavy" then 3 * hairline else hairline)
					end
					local card = find(root, "Dividers")
					Verify.expect(card:FindFirstChildWhichIsA("UISizeConstraint").MaxSize.X):toBe(360)
					Verify.expect((card:HasTag("facet-panel"))):toBe(true)
				end
				check(theme:peek(), 28)
				local pointer = shipped("compact_pointer")
				theme:set(pointer)
				check(pointer, 24)
				local thick = themes.neutralPackage()
				thick.metrics.strokes.hairline = 2
				theme:set(thick)
				check(thick, 30)
				local sheet, stopSheet = sheetFor(harness(), thick)
				Verify.expect(style(sheet, ".facet-divider").BackgroundTransparency):toBe(0.92)
				stopSheet()
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("marks the active word row and pending crossword tiles without relying on color", {
			id = "native_parity_paint::native parity paint::marks the active word row and pending crossword tiles without relying on color",
			run = function()
				local function world(): any
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local target = engine.new("Folder")
					local viewport = Compose.cell({ width = 800, height = 600 })
					return {
						Facet = Facet,
						Compose = Compose,
						runtime = runtime,
						Host = (runtime.constructors :: unknown) :: RobloxHost,
						types = engine.types,
						inputTarget = target,
						worldTarget = engine.new("Folder"),
						guiService = engine.new("GuiService"),
						viewport = viewport,
						runService = { Heartbeat = engine.heartbeat },
						target = target,
						engine = engine,
						UI = Facet.controls(runtime, { types = engine.types, viewport = viewport } :: any),
					}
				end
				local function start(ctx: any, definition: any): (any, any, () -> ())
					local game
					local stop, node = ctx.runtime.mount(function()
						game = definition.build(ctx)
						return ctx.Host.ScreenGui("GameScreen")({ game.screen() })
					end, ctx.target)
					return game, node, function()
						stop()
						ctx.runtime:dispose()
					end
				end
				local word: any = (require :: any)("../examples/gallery/examples/05_word_game")
				local seed
				for candidate = 1, 100000 do
					if word.rules.solutionForSeed(candidate) == "READER" then
						seed = candidate
						break
					end
				end
				local ctx = world()
				local game, node, stop = start(ctx, word)
				game.restart(seed)
				local function outlined(row: number): boolean
					local count = 0
					for column = 1, word.rules.COLS do
						local tile = find(node, `tile{row}_{column}`)
						local outline = find(tile, "Cursor")
						Verify.expect(outline.ClassName):toBe("UIStroke")
						Verify.expect((outline:HasTag("facet-status-ring"))):toBe(true)
						if outline.Enabled then
							count += 1
							Verify.expect((game.mark(row, column))):toBe("_")
						end
						Verify.expect(find(tile, "Typed").Visible)
							:toBe(column <= #game.row(row) and game.activeRow() == row)
					end
					Verify.expect(count <= 1):toBe(true)
					return count == 1
				end
				Verify.expect((outlined(1))):toBe(true)
				Verify.expect((outlined(2))):toBe(false)
				Verify.expect((game.mark(1, 1))):toBe("_")
				game.press("R")
				Verify.expect((outlined(1))):toBe(true)
				for _, letter in { "U", "L", "E", "R", "S" } do
					game.press(letter)
				end
				Verify.expect((outlined(1))):toBe(false)
				local function key(letter: string): any
					return find(node, "key_" .. letter)
				end
				Verify.expect((key("R"):HasTag("facet-status-success"))):toBe(false)
				game.press("Return")
				Verify.expect((game.keyState("R"))):toBe("correct")
				Verify.expect((game.keyState("U"))):toBe("absent")
				Verify.expect((game.keyState("E"))):toBe("present")
				Verify.expect((key("R"):HasTag("facet-status-success"))):toBe(true)
				Verify.expect((key("U"):HasTag("facet-status-neutral"))):toBe(true)
				Verify.expect((key("E"):HasTag("facet-status-warning"))):toBe(true)
				Verify.expect((find(find(node, "tile1_1"), "fill"):HasTag("facet-status-success"))):toBe(true)
				Verify.expect((game.activeRow())):toBe(2)
				Verify.expect((outlined(1))):toBe(false)
				Verify.expect((outlined(2))):toBe(true)
				for _, letter in { "R", "E", "A", "D", "E", "R" } do
					game.press(letter)
				end
				game.press("Return")
				Verify.expect((game.phase())):toBe("won")
				for row = 1, word.rules.ROWS do
					Verify.expect((outlined(row))):toBe(false)
				end
				stop()

				local tile: any = (require :: any)("../examples/gallery/examples/06_tile_game")
				local tileCtx = world()
				local board, boardNode, stopBoard = start(tileCtx, tile)
				for _, move in { { 1, 4, 1 }, { 3, 4, 2 }, { 5, 4, 3 }, { 6, 4, 4 }, { 2, 4, 5 } } do
					board.select(move[1])
					board.place(move[2], move[3])
				end
				board.submit()
				Verify.expect((board.turn())):toBe(2)
				board.select(4)
				board.place(2, 5)
				Verify.expect((board.cellState(4, 1))):toBe("committed")
				Verify.expect((board.cellState(2, 5))):toBe("pending")
				local committed = find(find(boardNode, "cell4_1"), "tap")
				local pending = find(find(boardNode, "cell2_5"), "tap")
				Verify.expect((board.cellSurface(4, 1))):toBe("raised")
				Verify.expect((board.cellSurface(2, 5))):toBe("chip")
				Verify.expect((string.find(committed.Text, "~", 1, true))):toBe(nil)
				Verify.expect((string.sub(pending.Text, -1))):toBe("~")
				Verify.expect(find(committed, "Outline").Enabled):toBe(false)
				Verify.expect(find(pending, "Outline").Enabled):toBe(true)
				board.undo()
				Verify.expect(find(pending, "Outline").Enabled):toBe(false)
				stopBoard()
			end,
		})

		verifyHarness:case("selects every tag the framework emits with a rule in every shipped sheet", {
			id = "native_parity_paint::native parity paint::selects every tag the framework emits with a rule in every shipped sheet",
			run = function()
				local literals, prefixes, dynamic = {}, {}, {}
				for _, entry in fs.readDir("src/ui") do
					if entry ~= "themes.luau" and string.sub(entry, -5) == ".luau" then
						for _, site in scanTags(fs.readFile("src/ui/" .. entry), literals, prefixes) do
							table.insert(dynamic, entry .. ":" .. site)
						end
					end
				end
				Verify.expect(dynamic):toEqual({ "inputs.luau:role" })
				Verify.expect(string.find(fs.readFile("src/ui/nav_menu.luau"), 'family .. "-current"', 1, true) ~= nil)
					:toBe(true)
				literals["facet-segment-current"] = true
				literals["facet-choice-current"] = true
				local expanded: { [string]: { string } } = {
					["facet-"] = {},
					["facet-role-"] = { "default", "cancel", "destructive", "onIndicator" },
					["facet-status-"] = {
						"neutral",
						"info",
						"success",
						"warning",
						"error",
						"accent",
						"voice",
						"contrast",
					},
					["facet-avatar-background-"] = {
						"surface",
						"surfaceStrong",
						"control",
						"contentStrong",
						"accent",
						"success",
						"warning",
						"danger",
					},
					["facet-type-"] = table.clone(themes.TYPE_ROLES) :: any,
					["facet-badge-"] = { "standard", "status", "utility" },
					["facet-disclosure-"] = { "plain", "contained", "divided" },
					["facet-size-"] = { "xsmall", "compact", "regular", "large" },
					["facet-path-"] = { "content", "secondary", "accent" },
				}
				local found = {}
				for prefix in prefixes do
					table.insert(found, prefix)
				end
				table.sort(found)
				local declared = {}
				for prefix in expanded do
					table.insert(declared, prefix)
				end
				table.sort(declared)
				Verify.expect(found):toEqual(declared)
				for prefix, values in expanded do
					for _, value in values do
						literals[prefix .. value] = true
					end
				end
				local hooks: { [string]: boolean } = {
					["facet-adjustable"] = true,
					["facet-alert"] = true,
					["facet-callout"] = true,
					["facet-collection"] = true,
					["facet-dialog"] = true,
					["facet-level-picker"] = true,
					["facet-notice"] = true,
					["facet-popover"] = true,
					["facet-rating"] = true,
					["facet-rowactions"] = true,
					["facet-slider"] = true,
					["facet-snackbar"] = true,
					["facet-stepper"] = true,
					["facet-table"] = true,
					["facet-tablecell"] = true,
					["facet-tableheader"] = true,
					["facet-role-default"] = true,
					["facet-badge-standard"] = true,
					["facet-disclosure-plain"] = true,
					["facet-disclosure-contained"] = true,
					["facet-disclosure-divided"] = true,
					["facet-disclosure-group"] = true,
				}
				for hook in hooks do
					Verify.expect(literals[hook]):toBe(true)
				end
				local h = harness()
				local probes, stopProbes = mount(h, function()
					return h.Host.Frame({
						h.UI.Slider({ value = Compose.cell(0.5) }) :: unknown,
						h.UI.Toggle({ value = Compose.cell(true), label = "T" }),
						h.UI.Toggle({
							value = Compose.cell(false),
							label = "C",
							presentation = "checkbox" :: "checkbox",
						}),
						h.UI.Stepper({ value = Compose.cell(2), min = 0, max = 5 }),
						h.UI.ProgressView({ value = 0.5 }),
						h.UI.ProgressView({ value = 0.5, presentation = "circular" :: "circular" }),
						h.UI.Badge({ label = "B", icon = "checkmark", status = "warning", appearance = "status" }),
						h.UI.Button({
							label = "Go",
							appearance = "soft",
							role = "destructive" :: "destructive",
							subtitle = "More",
						}),
						h.UI.Text({ text = "L", textRole = "heading" :: "heading", role = "secondary" :: "secondary" }),
						h.UI.Picker({
							selected = Compose.cell("a"),
							style = "segmented" :: "segmented",
							options = {
								{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "B" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						}),
						h.UI.Picker({
							selected = Compose.cell("a"),
							style = "inline" :: "inline",
							options = {
								{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "B" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						}),
						h.UI.TextInput({ value = Compose.cell("") }),
						h.UI.Chip({ label = "Chip", selected = Compose.cell(true) }),
						h.UI.Rating({ value = Compose.cell(2) }),
						h.UI.LevelPicker({ value = Compose.cell(2) }),
						h.UI.Avatar({ name = "Ada Lovelace" }),
						h.UI.AvatarGroup({ items = { { id = "a", name = "Ada" }, { id = "b", name = "Bo" } } }),
						h.UI.StatusIndicator({ status = "info", form = "ring" }),
						h.UI.Skeleton({}),
						h.UI.ShortcutHint({ keys = { { "Ctrl", "K" } } }),
						h.UI.DisclosureGroup({
							expanded = Compose.cell(true),
							appearance = "contained",
							label = "More",
							content = function(): Instance
								return h.Host.Frame({})
							end,
						}),
					})
				end)
				local mounted = 0
				for _, node in probes:GetDescendants() do
					for _, tag in node:GetTags() do
						if string.sub(tag, 1, 6) == "facet-" then
							mounted += 1
							if not literals[tag] then
								error("scan missed emitted tag " .. tag)
							end
						end
					end
				end
				Verify.expect(mounted > 60):toBe(true)
				stopProbes()
				local packages = { themes.neutralPackage() }
				for _, name in SHIPPED do
					table.insert(packages, (shipped(name)))
				end
				for _, package in packages do
					for _, palette in package.style.themes do
						local sheet, stop = sheetFor(h, package, { theme = palette.name })
						local selected = {}
						for _, rule in sheet:GetChildren() do
							for class in string.gmatch(rule.Selector, "%.([%w%-]+)") do
								selected[class] = true
							end
						end
						for tag in literals do
							if hooks[tag] then
								Verify.expect(selected[tag] == true):toBe(false)
							elseif not selected[tag] then
								error(`{package.identity.id}/{palette.name} has no rule for emitted tag {tag}`)
							end
						end
						stop()
					end
				end
				h.dispose()
			end,
		})
	end)
end
