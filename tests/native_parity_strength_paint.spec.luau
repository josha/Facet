--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local FixtureRadialTypes = require("../src/ui/radial_types")
	local FixtureCollectionTypes = require("../src/ui/collection_types")
	local FixtureThemeTypes = require("../src/ui/theme_types")
	local FixtureNavigationTypes = require("../src/ui/navigation_types")

	local transitionOf = require("./lib/transition")
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
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
		input: any,
		dispose: () -> (),
	}

	local function harness(options: { [string]: any }?): Harness
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		local config: { [string]: any } =
			{ types = engine.types, guiService = gui, services = { GuiService = gui, UserInputService = input } }
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
			input = input,
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

	local function facetTags(node: any): { string }
		local out = {}
		for _, tag in node:GetTags() do
			if string.sub(tag, 1, 6) == "facet-" then
				table.insert(out, tag)
			end
		end
		table.sort(out)
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
		return package, report
	end

	local function paletteOf(palette: any): ({ [string]: any }, { [string]: any })
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

	type Compound = { class: string?, name: string?, tags: { string }, state: string? }
	type Selector = { parts: { Compound }, combinators: { string }, pseudo: string? }

	local function compound(text: string): Compound
		local tags = {}
		for tag in string.gmatch(text, "%.([%w%-]+)") do
			table.insert(tags, tag)
		end
		return {
			class = string.match(text, "^(%a%w*)"),
			name = string.match(text, "#([%w_]+)"),
			tags = tags,
			state = string.match(text, ":(%a+)$"),
		}
	end

	local parsed: { [string]: Selector } = {}

	local function parse(selector: string): Selector
		local cached = parsed[selector]
		if cached then
			return cached
		end
		local pseudo = string.match(selector, "::(%a+)$")
		local rest = if pseudo then string.sub(selector, 1, -(#pseudo + 3)) else selector
		local parts, combinators = {}, {}
		while true do
			local first, last, combinator = string.find(rest, " (>>?) ")
			if not first then
				table.insert(parts, compound(rest))
				break
			end
			table.insert(parts, compound(string.sub(rest, 1, first - 1)))
			table.insert(combinators, combinator :: string)
			rest = string.sub(rest, (last :: number) + 1)
		end
		local result = { parts = parts, combinators = combinators, pseudo = pseudo }
		parsed[selector] = result
		return result
	end

	local function matchesPart(part: Compound, node: any): boolean
		if part.class and not node:IsA(part.class) then
			return false
		end
		if part.name and node.Name ~= part.name then
			return false
		end
		for _, tag in part.tags do
			if not node:HasTag(tag) then
				return false
			end
		end
		if part.state then
			local ok, state = pcall(function()
				return node.GuiState
			end)
			if not ok or state == nil or state.Name ~= part.state then
				return false
			end
		end
		return true
	end

	local function matchesAt(selector: Selector, index: number, node: any): boolean
		if not matchesPart(selector.parts[index], node) then
			return false
		end
		if index == 1 then
			return true
		end
		local parent = node.Parent
		if selector.combinators[index - 1] == ">" then
			return parent ~= nil and matchesAt(selector, index - 1, parent)
		end
		while parent do
			if matchesAt(selector, index - 1, parent) then
				return true
			end
			parent = parent.Parent
		end
		return false
	end

	local function resolve(sheet: any, node: any, property: string, pseudo: string?): any
		local best, value = -math.huge, nil
		for _, rule in sheet:GetChildren() do
			local selector = parse(rule.Selector)
			if selector.pseudo == pseudo and matchesAt(selector, #selector.parts, node) then
				local candidate = rule:GetProperties()[property]
				if candidate ~= nil and rule.Priority > best then
					best, value = rule.Priority, candidate
				end
			end
		end
		return value
	end

	local function skinPackage(slots: { [string]: any }): any
		local package = themes.neutralPackage()
		package.assets = package.assets or {}
		for slot, asset in slots do
			assert(package.assets)[slot .. "Art"] = { content = asset }
			assert(package.chrome)[slot] = { kind = "nineSlice" :: "nineSlice", asset = slot .. "Art" }
		end
		return package
	end

	local function ownArt(node: any, slot: string): any
		local children = node:GetChildren()
		local fade = node:FindFirstChild("Fade")
		if fade and fade.ClassName == "CanvasGroup" then
			for _, child in fade:GetChildren() do
				table.insert(children, child)
			end
		end
		for _, child in children do
			if string.sub(child.Name, -8) == "Boundary" or (child.ClassName == "Folder" and child.Name == "Chrome") then
				local art = find(child, slot .. "1")
				if art then
					return art
				end
			end
		end
		return nil
	end

	local function ownSlots(node: any): { string }
		local out = {}
		local children = node:GetChildren()
		local fade = node:FindFirstChild("Fade")
		if fade and fade.ClassName == "CanvasGroup" then
			for _, child in fade:GetChildren() do
				table.insert(children, child)
			end
		end
		for _, child in children do
			if string.sub(child.Name, -8) == "Boundary" or (child.ClassName == "Folder" and child.Name == "Chrome") then
				for _, image in child:GetDescendants() do
					if image.ClassName == "ImageLabel" and image.Visible then
						table.insert(out, (string.gsub(image.Name, "%d+$", "")))
					end
				end
			end
		end
		table.sort(out)
		return out
	end

	local function setState(h: Harness, node: any, state: string)
		node.GuiState = (h.engine.types.Enum.GuiState :: any)[state]
	end

	verifyHarness:suite("native paint strength: button content", function()
		verifyHarness:case(
			"paints rich button titles and icons with the plate text color for every role and appearance",
			{
				id = "native_parity_strength_paint::native paint strength: button content::paints rich button titles and icons with the plate text color for every role and appearance",
				run = function()
					local h = harness()
					local packages = { themes.neutralPackage() }
					for _, name in SHIPPED do
						table.insert(packages, (shipped(name)))
					end
					local role, appearance, selected =
						Compose.cell("default"), Compose.cell("standard"), Compose.cell(false)
					local enabled = Compose.cell(true)
					local root, stop = mount(h, function()
						return h.Host.Frame({
							h.UI.Button({
								Name = "Plain",
								label = "Go",
								role = role,
								appearance = appearance,
								selected = selected,
								enabled = enabled,
							}) :: unknown,
							h.UI.Button({
								Name = "Rich",
								label = "Go",
								icon = "checkmark",
								role = role,
								appearance = appearance,
								selected = selected,
								enabled = enabled,
							}),
						})
					end)
					local plain, rich = find(root, "Plain"), find(root, "Rich")
					local title, icon = find(rich, "Title"), find(rich, "LeadingIcon")
					Verify.expect((title:HasTag("facet-text"))):toBe(true)
					Verify.expect((icon:HasTag("facet-icon"))):toBe(true)
					local checked = 0
					for _, package in packages do
						for _, palette in package.style.themes do
							local colors, extra = paletteOf(palette)
							local sheet, stopSheet = sheetFor(h, package, { theme = palette.name })
							for _, nextAppearance in { "standard", "emphasis", "soft", "utility", "link" } do
								for _, nextRole in { "default", "destructive" } do
									for _, isSelected in { false, true } do
										appearance:set(nextAppearance)
										role:set(nextRole)
										selected:set(isSelected)
										for _, state in { "Idle", "Hover", "Press" } do
											setState(h, plain, state)
											setState(h, rich, state)
											local expected = resolve(sheet, plain, "TextColor3")
											Verify.expect(expected ~= nil):toBe(true)
											Verify.expect((resolve(sheet, rich, "TextColor3"))):toBe(expected)
											Verify.expect((resolve(sheet, title, "TextColor3"))):toBe(expected)
											Verify.expect((resolve(sheet, icon, "ImageColor3"))):toBe(expected)
											local dim = resolve(sheet, plain, "TextTransparency") or 0
											Verify.expect(resolve(sheet, title, "TextTransparency") or 0):toBe(dim)
											Verify.expect(resolve(sheet, icon, "ImageTransparency") or 0):toBe(dim)
											checked += 1
										end
									end
								end
							end
							appearance:set("standard")
							selected:set(false)
							setState(h, plain, "Idle")
							setState(h, rich, "Idle")
							role:set("destructive")
							Verify.expect((resolve(sheet, title, "TextColor3"))):toBe(color(h.engine, colors.onDanger))
							Verify.expect((resolve(sheet, icon, "ImageColor3"))):toBe(color(h.engine, colors.onDanger))
							appearance:set("emphasis")
							Verify.expect((resolve(sheet, icon, "ImageColor3"))):toBe(color(h.engine, colors.onAccent))
							appearance:set("link")
							Verify.expect((resolve(sheet, title, "TextColor3"))):toBe(color(h.engine, colors.danger))
							Verify.expect((resolve(sheet, icon, "ImageColor3"))):toBe(color(h.engine, colors.danger))
							setState(h, rich, "Press")
							Verify.expect((resolve(sheet, title, "TextTransparency"))):toBe(0.3)
							Verify.expect((resolve(sheet, icon, "ImageTransparency"))):toBe(0.3)
							setState(h, rich, "Idle")
							appearance:set("standard")
							role:set("default")
							enabled:set(false)
							Verify.expect((resolve(sheet, plain, "TextTransparency")))
								:toBe(extra.disabledContentOpacity)
							Verify.expect((resolve(sheet, title, "TextTransparency")))
								:toBe(extra.disabledContentOpacity)
							Verify.expect((resolve(sheet, icon, "ImageTransparency")))
								:toBe(extra.disabledContentOpacity)
							Verify.expect(style(sheet, ".facet-disabled >> .facet-button-caption").TextTransparency)
								:toBe(extra.disabledContentOpacity)
							enabled:set(true)
							Verify.expect((resolve(sheet, title, "TextTransparency"))):toBe(nil)
							stopSheet()
						end
					end
					Verify.expect(checked >= 9 * 30):toBe(true)
					stop()
					h.dispose()
				end,
			}
		)

		verifyHarness:case(
			"writes a destructive menu row in content ink and hovers it on the danger plate in onDanger",
			{
				id = "native_parity_strength_paint::native paint strength: button content::writes a destructive menu row in content ink and hovers it on the danger plate in onDanger",
				run = function()
					local h = harness()
					local colors = neutralColors()
					local sheet, stopSheet = sheetFor(h, themes.neutralPackage())
					local root, stop = mount(h, function()
						return h.UI.Button({
							Name = "Delete",
							label = "Delete",
							icon = "trash",
							role = "destructive" :: "destructive",
						})
					end)
					local row = find(root, "Delete")
					row:AddTag("facet-menu-item")
					row:AddTag("facet-menu-destructive")
					local title, icon = find(row, "Title"), find(row, "LeadingIcon")
					setState(h, row, "Idle")
					Verify.expect((resolve(sheet, title, "TextColor3"))):toBe(color(h.engine, colors.content))
					Verify.expect((resolve(sheet, row, "BackgroundTransparency"))):toBe(1)
					Verify.expect((resolve(sheet, row, "CornerRadius", "UICorner"))):toBe(h.engine.types.UDim.new(0, 8))
					for _, state in { "Hover", "Press" } do
						setState(h, row, state)
						Verify.expect((resolve(sheet, row, "BackgroundColor3"))):toBe(color(h.engine, colors.danger))
						Verify.expect((resolve(sheet, title, "TextColor3"))):toBe(color(h.engine, colors.onDanger))
						Verify.expect((resolve(sheet, icon, "ImageColor3"))):toBe(color(h.engine, colors.onDanger))
					end
					stop()
					stopSheet()
					h.dispose()
				end,
			}
		)

		verifyHarness:case("rounds a tag to the theme's pill radius", {
			id = "native_parity_strength_paint::native paint strength: button content::rounds a tag to the theme's pill radius",
			run = function()
				local h = harness()
				local root, stop = mount(h, function()
					return h.UI.Chip({ Name = "Tag", label = "Rain", selected = Compose.cell(false) })
				end)
				local tag = find(root, "Tag")
				for _, case in
					{
						{ package = themes.neutralPackage(), radius = 999 },
						{ package = shipped("pixel_quest"), radius = 0 },
					}
				do
					local sheet, stopSheet = sheetFor(h, case.package)
					Verify.expect((resolve(sheet, tag, "CornerRadius", "UICorner")))
						:toBe(h.engine.types.UDim.new(0, case.radius))
					stopSheet()
				end
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("keeps a hidden plaque caption hidden while its button is disabled", {
			id = "native_parity_strength_paint::native paint strength: button content::keeps a hidden plaque caption hidden while its button is disabled",
			run = function()
				local h = harness()
				local _, extra = neutralColors()
				local sheet, stop = sheetFor(h, themes.neutralPackage())
				local root, stopMount = mount(h, function()
					return h.UI.Button({ Name = "Plaque", label = "Go", enabled = false })
				end)
				local button = find(root, "Plaque")
				button:AddTag("facet-skin-caption")
				local caption = find(button, "LabelBoundary")
				caption = if caption then find(caption, "Label") else nil
				if caption == nil then
					local boundary, bounds = h.engine.new("Frame"), h.engine.new("Frame")
					bounds.Parent, boundary.Parent = boundary, button
					caption = h.engine.new("TextLabel")
					caption:AddTag("facet-text")
					caption:AddTag("facet-button-caption")
					caption.Parent = bounds
				end
				Verify.expect((resolve(sheet, caption, "TextTransparency"))):toBe(1)
				button:RemoveTag("facet-skin-caption")
				Verify.expect((resolve(sheet, caption, "TextTransparency"))):toBe(extra.disabledContentOpacity)
				stopMount()
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case(
			"a skin that paints its own caption hides only its own button caption, not the captions inside it",
			{
				id = "native_parity_strength_paint::native paint strength: button content::a skin that paints its own caption hides only its own button caption, not the captions inside it",
				run = function()
					local h = harness()
					local sheet, stop = sheetFor(h, themes.neutralPackage())
					local panel = h.engine.new("Frame")
					panel:AddTag("facet-skin-caption")
					local function caption(parent: any): any
						local boundary, bounds, label =
							h.engine.new("Frame"), h.engine.new("Frame"), h.engine.new("TextLabel")
						label:AddTag("facet-text")
						label:AddTag("facet-button-caption")
						label.Parent, bounds.Parent, boundary.Parent = bounds, boundary, parent
						return label
					end
					local own = caption(panel)
					local room, actions, apply =
						h.engine.new("Frame"), h.engine.new("Frame"), h.engine.new("TextButton")
					actions.Parent, room.Parent, apply.Parent = room, panel, actions
					local inner = caption(apply)
					Verify.expect((resolve(sheet, own, "TextTransparency"))):toBe(1)
					Verify.expect((resolve(sheet, inner, "TextTransparency"))):toBe(0)
					stop()
					h.dispose()
				end,
			}
		)

		verifyHarness:case("mints one tag per authored appearance word and rung, none for standard or no rung", {
			id = "native_parity_strength_paint::native paint strength: button content::mints one tag per authored appearance word and rung, none for standard or no rung",
			run = function()
				local h = harness()
				local expected: { [string]: { string } } = {
					standard = {},
					emphasis = { "facet-accent" },
					soft = { "facet-appearance-soft" },
					utility = { "facet-appearance-utility" },
					link = { "facet-appearance-link" },
				}
				local bound = Compose.cell("standard")
				local nodes: { [string]: any } = {}
				local root, stop = mount(h, function()
					local children = {}
					for word in expected do
						for _, size in { "compact", "regular", "large" } do
							table.insert(
								children,
								h.UI.Button({
									Name = word .. "-" .. size,
									label = word,
									appearance = word,
									controlSize = size,
								})
							)
						end
					end
					table.insert(children, h.UI.Button({ Name = "Bare", label = "Bare" }))
					table.insert(children, h.UI.Button({ Name = "Bound", label = "Bound", appearance = bound }))
					return h.Host.Frame(children)
				end)
				for word, extra in expected do
					for _, size in { "compact", "regular", "large" } do
						local node = find(root, word .. "-" .. size)
						nodes[word] = node
						local want = { "facet-button", "facet-role-default", "facet-size-" .. size }
						for _, tag in extra do
							table.insert(want, tag)
						end
						table.sort(want)
						Verify.expect((facetTags(node))):toEqual(want)
						Verify.expect((node:GetAttribute("appearance"))):toBe(word)
						Verify.expect((node:GetAttribute("controlSize"))):toBe(size)
					end
				end
				Verify.expect((facetTags(find(root, "Bare")))):toEqual({ "facet-button", "facet-role-default" })
				Verify.expect((find(root, "Bare"):GetAttribute("controlSize"))):toBe("regular")
				local node = find(root, "Bound")
				for _, word in { "emphasis", "soft", "utility", "link", "standard" } do
					bound:set(word)
					local want = { "facet-button", "facet-role-default" }
					for _, tag in expected[word] do
						table.insert(want, tag)
					end
					table.sort(want)
					Verify.expect((facetTags(node))):toEqual(want)
				end
				for _, candidate in root:GetDescendants() do
					for _, tag in candidate:GetTags() do
						local sized = string.sub(tag, 1, 11) == "facet-size-"
						Verify.expect(sized and (candidate.Name == "Bare" or candidate.Name == "Bound")):toBe(false)
						Verify.expect(sized and tag ~= "facet-size-" .. tostring(candidate:GetAttribute("controlSize")))
							:toBe(false)
						Verify.expect(tag == "facet-appearance-standard" or tag == "facet-appearance-emphasis")
							:toBe(false)
					end
				end
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("leaves game-owned tags in place while control state tags come and go", {
			id = "native_parity_strength_paint::native paint strength: button content::leaves game-owned tags in place while control state tags come and go",
			run = function()
				local h = harness()
				local role, appearance, selected =
					Compose.cell("destructive"), Compose.cell("utility"), Compose.cell(true)
				local busy, enabled, value = Compose.cell(true), Compose.cell(false), Compose.cell(true)
				local level, pick, tab = Compose.cell(3), Compose.cell("a"), Compose.cell("one")
				local options = { { value = "a", label = "A" }, { value = "b", label = "B" } }
				local root, stop = mount(h, function()
					return h.Host.Frame({
						h.UI.Button({
							Name = "Action",
							label = "Go",
							role = role,
							appearance = appearance,
							selected = selected,
							busy = busy,
							enabled = enabled,
						}) :: unknown,
						h.UI.Toggle({ Name = "Switch", value = value, label = "On" }),
						h.UI.LevelPicker({ Name = "Level", value = level, count = 5 }),
						h.Host.Frame({
							Name = "Segmented",
							h.UI.Picker({ selected = pick, style = "segmented" :: "segmented", options = options }),
						}),
						h.UI.TabView({
							selection = tab,
							tabs = {
								{
									id = "one",
									label = "One",
									content = function()
										return h.Host.Frame({})
									end,
								} :: FixtureNavigationTypes.Tab,
								{
									id = "two",
									label = "Two",
									content = function()
										return h.Host.Frame({})
									end,
								} :: FixtureNavigationTypes.Tab,
							},
						}),
					})
				end)
				local action = find(root, "Action")
				local indicator = find(find(root, "Switch"), "Indicator")
				local bar = find(find(root, "Level"), "Level1")
				local option = find(find(root, "Segmented"), "a")
				local tabButton = find(root, "one")
				local owned = { action, indicator, bar, option, tabButton }
				for _, node in owned do
					node:AddTag("game-owned")
					node:AddTag("facet-game-mark")
				end
				Verify.expect((action:HasTag("facet-role-destructive"))):toBe(true)
				Verify.expect((action:HasTag("facet-quiet-destructive"))):toBe(true)
				Verify.expect((action:HasTag("facet-selected"))):toBe(true)
				Verify.expect((action:HasTag("facet-busy"))):toBe(true)
				Verify.expect((action:HasTag("facet-disabled"))):toBe(true)
				role:set("cancel")
				appearance:set("emphasis")
				selected:set(false)
				busy:set(false)
				enabled:set(true)
				value:set(false)
				level:set(0)
				pick:set("b")
				tab:set("two")
				Verify.expect((action:HasTag("facet-role-destructive"))):toBe(false)
				Verify.expect((action:HasTag("facet-role-cancel"))):toBe(true)
				Verify.expect((action:HasTag("facet-quiet-destructive"))):toBe(false)
				Verify.expect((action:HasTag("facet-appearance-utility"))):toBe(false)
				Verify.expect((action:HasTag("facet-accent"))):toBe(true)
				Verify.expect((action:HasTag("facet-selected"))):toBe(false)
				Verify.expect((action:HasTag("facet-busy"))):toBe(false)
				Verify.expect((action:HasTag("facet-disabled"))):toBe(false)
				Verify.expect((indicator:HasTag("facet-toggle-on"))):toBe(false)
				Verify.expect((bar:HasTag("facet-level-on"))):toBe(false)
				Verify.expect((option:HasTag("facet-segment-current"))):toBe(false)
				Verify.expect((tabButton:HasTag("facet-tab-current"))):toBe(false)
				for _, node in owned do
					Verify.expect((node:HasTag("game-owned"))):toBe(true)
					Verify.expect((node:HasTag("facet-game-mark"))):toBe(true)
				end
				role:set("destructive")
				value:set(true)
				level:set(5)
				pick:set("a")
				tab:set("one")
				Verify.expect((indicator:HasTag("facet-toggle-on"))):toBe(true)
				Verify.expect((bar:HasTag("facet-level-on"))):toBe(true)
				Verify.expect((option:HasTag("facet-segment-current"))):toBe(true)
				Verify.expect((tabButton:HasTag("facet-tab-current"))):toBe(true)
				for _, node in owned do
					Verify.expect((node:HasTag("game-owned"))):toBe(true)
					Verify.expect((node:HasTag("facet-game-mark"))):toBe(true)
				end
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("replaces the selected plate with the chosen indicator instead of painting both", {
			id = "native_parity_strength_paint::native paint strength: button content::replaces the selected plate with the chosen indicator instead of painting both",
			run = function()
				local h = harness()
				local colors, extra = neutralColors()
				local sheet, stopSheet = sheetFor(h, themes.neutralPackage())
				local segmented, indicator = Compose.cell("b"), Compose.cell("underline")
				local selection, tabIndicator = Compose.cell("two"), Compose.cell("automatic")
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
						h.UI.TabView({
							selection = selection,
							indicator = tabIndicator,
							placement = "topBar" :: "topBar",
							tabs = {
								{
									id = "one",
									label = "One",
									content = function()
										return h.Host.Frame({})
									end,
								} :: FixtureNavigationTypes.Tab,
								{
									id = "two",
									label = "Two",
									content = function()
										return h.Host.Frame({})
									end,
								} :: FixtureNavigationTypes.Tab,
							},
						}),
					})
				end)
				local picker = find(root, "Segmented")
				local a, b = find(picker, "a"), find(picker, "b")
				local function bars(scope: any): number
					return #tagged(scope, "facet-selection-indicator")
				end
				Verify.expect((bars(picker))):toBe(1)
				Verify.expect(find(b, "SelectionIndicator") ~= nil):toBe(true)
				Verify.expect((b:HasTag("facet-selected"))):toBe(false)
				Verify.expect((resolve(sheet, b, "BackgroundTransparency"))):toBe(1)
				Verify.expect((resolve(sheet, b, "BackgroundTransparency")))
					:toBe(resolve(sheet, a, "BackgroundTransparency"))
				Verify.expect((resolve(sheet, b, "BackgroundColor3"))):toBe(resolve(sheet, a, "BackgroundColor3"))
				Verify.expect((resolve(sheet, find(b, "SelectionIndicator"), "BackgroundColor3")))
					:toBe(color(h.engine, colors.accent))
				indicator:set("pill")
				Verify.expect((bars(picker))):toBe(0)
				local fill = find(picker, "SelectionFill")
				Verify.expect(fill.Visible):toBe(true)
				Verify.expect((resolve(sheet, fill, "BackgroundTransparency"))):toBe(0)
				Verify.expect((resolve(sheet, fill, "BackgroundColor3"))):toBe(color(h.engine, colors.accent))
				Verify.expect((resolve(sheet, b, "BackgroundTransparency"))):toBe(1)
				Verify.expect((resolve(sheet, a, "BackgroundTransparency"))):toBe(1)
				local one, two = find(root, "one"), find(root, "two")
				local tabs = one.Parent
				Verify.expect((bars(tabs))):toBe(1)
				Verify.expect(find(two, "SelectionIndicator") ~= nil):toBe(true)
				Verify.expect((two:HasTag("facet-selected"))):toBe(false)
				Verify.expect((resolve(sheet, two, "BackgroundTransparency"))):toBe(1)
				Verify.expect((resolve(sheet, two, "BackgroundColor3"))):toBe(resolve(sheet, one, "BackgroundColor3"))
				tabIndicator:set("underline")
				Verify.expect((bars(tabs))):toBe(1)
				Verify.expect((two:HasTag("facet-selected"))):toBe(false)
				Verify.expect((resolve(sheet, two, "BackgroundTransparency"))):toBe(1)
				tabIndicator:set("pill")
				Verify.expect((bars(tabs))):toBe(0)
				Verify.expect((two:HasTag("facet-selected"))):toBe(true)
				Verify.expect((resolve(sheet, two, "BackgroundTransparency"))):toBe(0)
				Verify.expect((resolve(sheet, two, "BackgroundColor3"))):toBe(color(h.engine, extra.controlSelected))
				setState(h, two, "Hover")
				Verify.expect((resolve(sheet, two, "BackgroundTransparency"))):toBe(0)
				setState(h, two, "Idle")
				Verify.expect((resolve(sheet, one, "BackgroundTransparency"))):toBe(1)
				tabIndicator:set("none")
				Verify.expect((bars(tabs))):toBe(0)
				Verify.expect((two:HasTag("facet-selected"))):toBe(false)
				Verify.expect((resolve(sheet, two, "BackgroundTransparency"))):toBe(1)
				stop()
				stopSheet()
				h.dispose()
			end,
		})

		verifyHarness:case(
			"keeps the radial button plate by default and omits it for every item when the surface is none",
			{
				id = "native_parity_strength_paint::native paint strength: button content::keeps the radial button plate by default and omits it for every item when the surface is none",
				run = function()
					local colors, extra = neutralColors()
					for _, surface in { "native", "none" } do
						local h = harness({ motionLevel = "none" })
						local sheet, stopSheet = sheetFor(h, themes.neutralPackage())
						local items = {}
						for _, id in { "N", "E", "S", "W" } do
							table.insert(items, {
								id = id,
								slot = id,
								label = id,
								icon = if id == "N" then "checkmark" else nil,
								completion = "stay" :: "stay",
								onSelect = function() end,
							})
						end
						local root, stop = mount(h, function()
							return h.UI.RadialMenu({
								isPresented = Compose.cell(true),
								appearance = "buttons",
								buttonSurface = if surface == "none" then "none" else nil,
								distribution = "compass" :: "compass",
								items = items,
							})
						end)
						local screen = root.Parent
						for _, id in { "N", "E", "S", "W" } do
							local button = find(screen, id)
							Verify.expect((button:HasTag("facet-button"))):toBe(true)
							if surface == "none" then
								Verify.expect(button.BackgroundTransparency):toBe(1)
							else
								Verify.expect(button.BackgroundTransparency):toBe(0)
								Verify.expect((resolve(sheet, button, "BackgroundTransparency"))):toBe(0)
								Verify.expect((resolve(sheet, button, "BackgroundColor3"))):toBe(
									color(
										h.engine,
										if button:HasTag("facet-selected") then extra.controlSelected else extra.control
									)
								)
							end
							Verify.expect((resolve(sheet, button, "TextColor3"))):toBe(color(h.engine, colors.content))
						end
						local icon = find(find(screen, "N"), "LeadingIcon")
						Verify.expect((resolve(sheet, icon, "ImageColor3"))):toBe(color(h.engine, colors.content))
						stop()
						stopSheet()
						h.dispose()
					end
					local h = harness({ motionLevel = "none" })
					local root, stop = mount(h, function()
						return h.UI.RadialMenu({
							isPresented = Compose.cell(true),
							distribution = "compass" :: "compass",
							items = {
								{
									id = "N",
									slot = "N" :: "N",
									label = "N",
									completion = "stay" :: "stay",
									onSelect = function() end,
								} :: FixtureRadialTypes.RadialItem<any>,
							},
						})
					end)
					Verify.expect(find(root.Parent, "N").BackgroundTransparency):toBe(1)
					stop()
					h.dispose()
					Verify.expect(function()
						local bad = harness({ motionLevel = "none" })
						mount(bad, function()
							return bad.UI.RadialMenu({
								isPresented = Compose.cell(true),
								buttonSurface = "plate" :: "plate",
								items = {
									{ id = "N", label = "N", onSelect = function() end } :: FixtureRadialTypes.RadialItem<any>,
								},
							})
						end)
					end):toThrow()
				end,
			}
		)

		verifyHarness:case(
			"draws each wedge item as plate-less content inside its own wedge, even in a skinned package",
			{
				id = "native_parity_strength_paint::native paint strength: button content::draws each wedge item as plate-less content inside its own wedge, even in a skinned package",
				run = function()
					for _, package in { themes.neutralPackage(), (shipped("pixel_quest")), (shipped("fantasy_ornate")) } do
						local h = harness({ motionLevel = "none", theme = package })
						local items = {}
						for index = 1, 12 do
							table.insert(items, {
								id = "item" .. index,
								label = "Item " .. index,
								icon = if index % 2 == 0 then "checkmark" else nil,
								onSelect = function() end,
							})
						end
						local root, stop = mount(h, function()
							return h.UI.RadialMenu({ isPresented = Compose.cell(true), items = items })
						end)
						for index = 1, 12 do
							local button = find(root.Parent, "item" .. index)
							local where = `{package.identity.id}/item{index}`
							Verify.expect(#ownSlots(button)):toBe(0)
							Verify.expect((button:HasTag("facet-appearance-utility"))):toBe(true)
							local paint = find(button.Parent, "Paint")
							local left = button.Position.X.Offset - button.Size.X.Offset / 2
							local top = button.Position.Y.Offset - button.Size.Y.Offset / 2
							local inside = left >= paint.Position.X.Offset - 0.5
								and top >= paint.Position.Y.Offset - 0.5
								and left + button.Size.X.Offset <= paint.Position.X.Offset + paint.Size.X.Offset + 0.5
								and top + button.Size.Y.Offset
									<= paint.Position.Y.Offset + paint.Size.Y.Offset + 0.5
							assert(inside, where .. " content leaves its wedge")
						end
						local centre = find(root.Parent, "Center")
						Verify.expect(#ownSlots(centre)):toBe(0)
						stop()
						h.dispose()
					end
				end,
			}
		)

		verifyHarness:case(
			"a dark ring scrim dims the page to at least 80 percent in every shipped package and palette",
			{
				id = "native_parity_strength_paint::native paint strength: button content::a dark ring scrim dims the page to at least 80 percent in every shipped package and palette",
				run = function()
					local packages = { themes.neutralPackage() }
					for _, name in SHIPPED do
						table.insert(packages, (shipped(name)))
					end
					for _, package in packages do
						for _, palette in package.style.themes do
							local h = harness({ motionLevel = "none" })
							local sheet, stopSheet = sheetFor(h, package, { theme = palette.name })
							local root, stop = mount(h, function()
								return h.UI.RadialMenu({
									isPresented = Compose.cell(true),
									scrim = "dark",
									items = {
										{ id = "alpha", label = "Alpha", onSelect = function() end } :: FixtureRadialTypes.RadialItem<any>,
									},
								})
							end)
							local scrim = find(root.Parent, "DismissOutside")
							local where = `{package.identity.id}/{palette.name}`
							local transparency = resolve(sheet, scrim, "BackgroundTransparency")
							assert(
								transparency ~= nil and transparency <= 0.2 + 1e-6,
								`{where} ring scrim {transparency}`
							)
							local tint = resolve(sheet, scrim, "BackgroundColor3")
							local dark = luminance({ r = tint.R, g = tint.G, b = tint.B })
							assert(dark <= 0.05, `{where} ring scrim colour luminance {dark}`)
							stop()
							stopSheet()
							h.dispose()
						end
					end
				end,
			}
		)

		verifyHarness:case(
			"paints each wedge and its label as one readable pair in every shipped package and palette",
			{
				id = "native_parity_strength_paint::native paint strength: button content::paints each wedge and its label as one readable pair in every shipped package and palette",
				run = function()
					local packages = { themes.neutralPackage() }
					for _, name in SHIPPED do
						table.insert(packages, (shipped(name)))
					end
					for _, package in packages do
						for _, palette in package.style.themes do
							local h = harness({ motionLevel = "none" })
							local sheet, stopSheet = sheetFor(h, package, { theme = palette.name })
							local root, stop = mount(h, function()
								return h.UI.RadialMenu({
									isPresented = Compose.cell(true),
									items = {
										{ id = "alpha", label = "Alpha", onSelect = function() end } :: FixtureRadialTypes.RadialItem<any>,
										{ id = "beta", label = "Beta", onSelect = function() end } :: FixtureRadialTypes.RadialItem<any>,
									},
								})
							end)
							local states = {}
							find(root.Parent, "alpha").MouseEnter:Fire()
							for _, id in { "alpha", "beta" } do
								local button = find(root.Parent, id)
								local fill = resolve(sheet, find(button.Parent, "Sector"), "Color3")
								local ink = resolve(sheet, button, "TextColor3")
								local where = `{package.identity.id}/{palette.name}/{id}`
								assert(fill ~= nil and ink ~= nil, where .. " wedge or label has no theme paint")
								local ratio = contrast(
									{ r = fill.R, g = fill.G, b = fill.B },
									{ r = ink.R, g = ink.G, b = ink.B }
								)
								assert(ratio >= 4.5, `{where} label contrast {ratio}`)
								states[button:HasTag("facet-selected")] = true
							end
							Verify.expect(states[true] and states[false]):toBe(true)
							stop()
							stopSheet()
							h.dispose()
						end
					end
				end,
			}
		)
	end)

	verifyHarness:suite("native paint strength: skins", function()
		verifyHarness:case("drives the control skin art from the button's own interaction state", {
			id = "native_parity_strength_paint::native paint strength: skins::drives the control skin art from the button's own interaction state",
			run = function()
				local package = themes.neutralPackage()
				for name, id in
					{ rest = 11, hot = 12, press = 13, chosen = 14, off = 15, bare = 16, pushed = 17 } :: { [string]: number }
				do
					assert(package.assets)[name] = { content = "rbxassetid://" .. id }
				end
				assert(package.chrome).control = {
					kind = "nineSlice" :: "nineSlice",
					asset = {
						default = "rest",
						hover = "hot",
						pressed = "press",
						selected = "chosen",
						disabled = "off",
					},
				}
				local h = harness({ theme = package })
				local sheet, stopSheet = sheetFor(h, package)
				local selected, enabled = Compose.cell(false), Compose.cell(true)
				local root, stop = mount(h, function()
					return h.UI.Button({ Name = "Go", label = "Go", selected = selected, enabled = enabled })
				end)
				local button = find(root, "Go")
				local art = ownArt(button, "control")
				Verify.expect((button:HasTag("facet-skinned"))):toBe(true)
				local function expectArt(state: string, id: number)
					setState(h, button, state)
					Verify.expect((ownArt(button, "control"))):toBe(art)
					Verify.expect(art.Image):toBe("rbxassetid://" .. id)
					Verify.expect((resolve(sheet, button, "BackgroundTransparency"))):toBe(1)
				end
				expectArt("Idle", 11)
				expectArt("Hover", 12)
				expectArt("Press", 13)
				expectArt("Idle", 11)
				selected:set(true)
				expectArt("Idle", 14)
				expectArt("Hover", 12)
				expectArt("Press", 13)
				enabled:set(false)
				expectArt("Press", 15)
				expectArt("NonInteractable", 15)
				expectArt("Idle", 15)
				enabled:set(true)
				selected:set(false)
				expectArt("Idle", 11)
				stop()
				stopSheet()
				h.dispose()
				local partial = themes.neutralPackage()
				assert(partial.assets).bare = { content = "rbxassetid://16" }
				assert(partial.assets).pushed = { content = "rbxassetid://17" }
				assert(partial.chrome).control =
					{ kind = "nineSlice" :: "nineSlice", asset = { default = "bare", pressed = "pushed" } }
				local other = harness({ theme = partial })
				local otherRoot, stopOther = mount(other, function()
					return other.UI.Button({ Name = "Go", label = "Go", selected = true })
				end)
				local plate = find(otherRoot, "Go")
				local image = ownArt(plate, "control")
				for state, id in { Idle = 16, Hover = 16, Press = 17 } :: { [string]: number } do
					setState(other, plate, state)
					Verify.expect(image.Image):toBe("rbxassetid://" .. id)
				end
				stopOther()
				other.dispose()
			end,
		})

		verifyHarness:case("gives a transparent hit-target button no control art over the content beneath it", {
			id = "native_parity_strength_paint::native paint strength: skins::gives a transparent hit-target button no control art over the content beneath it",
			run = function()
				local package = skinPackage({ control = "rbxassetid://21" })
				local h = harness({ theme = package })
				local clear = Compose.cell(1)
				local root, stop = mount(h, function()
					return h.Host.Frame({
						h.UI.Button({ Name = "Hit", label = "", BackgroundTransparency = 1 }) :: unknown,
						h.UI.Button({ Name = "Bound", label = "Go", BackgroundTransparency = clear }),
						h.UI.Button({ Name = "Plate", label = "Go" }),
					})
				end)
				Verify.expect((ownArt(find(root, "Hit"), "control"))):toBe(nil)
				Verify.expect((find(root, "Hit"):HasTag("facet-skinned"))):toBe(false)
				Verify.expect((ownArt(find(root, "Bound"), "control"))):toBe(nil)
				Verify.expect(ownArt(find(root, "Plate"), "control") ~= nil):toBe(true)
				clear:set(0)
				Verify.expect(ownArt(find(root, "Bound"), "control") ~= nil):toBe(true)
				clear:set(1)
				Verify.expect((ownArt(find(root, "Bound"), "control"))):toBe(nil)
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("tints destructive and emphasis plate art with their role and keeps the label readable", {
			id = "native_parity_strength_paint::native paint strength: skins::tints destructive and emphasis plate art with their role and keeps the label readable",
			run = function()
				local samples = serde.decode("json", fs.readFile("assets/themes/plate-samples.json")).samples
				local checked = {}
				for _, name in SHIPPED do
					local package = shipped(name)
					local sample = (samples[(string.gsub(name, "_", "-"))] or {}).control
					local h = harness({ theme = package })
					local root, stop = mount(h, function()
						return h.Host.Frame({
							h.UI.Button({ Name = "Delete", label = "Delete", role = "destructive" :: "destructive" }) :: unknown,
							h.UI.Button({ Name = "Save", label = "Save", appearance = "emphasis" }),
							h.UI.Button({ Name = "Reset", label = "Reset" }),
						})
					end)
					local art = ownArt(find(root, "Reset"), "control")
					if art then
						for _, palette in package.style.themes do
							local colors, extra = paletteOf(palette)
							local sheet, stopSheet = sheetFor(h, package, { theme = palette.name })
							Verify.expect((resolve(sheet, art, "ImageColor3")))
								:toBe(if extra.artTint then color(h.engine, extra.artTint) else nil)
							local shapes = {}
							for button, pair in
								{ Delete = { "danger", "onDanger" }, Save = { "accent", "onAccent" } } :: { [string]: { string } }
							do
								local node, tint = find(root, button), colors[pair[1]]
								local plateArt = ownArt(node, "control")
								local tinted = resolve(sheet, plateArt, "ImageColor3")
								Verify.expect(`{name}/{button}:{resolve(sheet, find(node, "SkinBoundary"), "Visible")}`)
									:toBe(`{name}/{button}:true`)
								Verify.expect((resolve(sheet, node, "BackgroundTransparency"))):toBe(1)
								local pressed = resolve(sheet, plateArt, "Image")
								if pressed then
									local _, extra = paletteOf(palette)
									local control = package.chrome.control
									local layers = if control.kind == "layered" then control.layers else { control }
									local link = layers[1].asset.selected
									link = if type(link) == "string" then { asset = link } else link
									local art = package.assets[link.asset]
									local ink = extra.onSelected or colors.content
									local wash = link.tint or { r = 1, g = 1, b = 1 }
									local picked = samples[(string.gsub(name, "_", "-"))].selected
									Verify.expect(pressed):toBe(art.content or art.contentId)
									Verify.expect((resolve(sheet, plateArt, "Rotation"))):toBe(link.rotation or 0)
									Verify.expect(tinted):toBe(color(h.engine, wash))
									Verify.expect((resolve(sheet, node, "TextColor3"))):toBe(color(h.engine, ink))
									for _, caption in tagged(node, "facet-button-caption") do
										Verify.expect((resolve(sheet, caption, "TextColor3")))
											:toBe(color(h.engine, ink))
									end
									local plate = {
										r = picked.r / 255 * wash.r,
										g = picked.g / 255 * wash.g,
										b = picked.b / 255 * wash.b,
									}
									Verify.expect(contrast(ink, plate) >= 4.5):toBe(true)
									table.insert(shapes, button .. "=pressed")
								else
									Verify.expect(tinted):toBe(color(h.engine, tint))
									local plate = if sample
										then {
											r = sample.r / 255 * tint.r,
											g = sample.g / 255 * tint.g,
											b = sample.b / 255 * tint.b,
										}
										else tint
									Verify.expect(contrast(colors[pair[2]], plate) >= 4.5):toBe(true)
									table.insert(shapes, button .. "=art")
								end
							end
							table.sort(shapes)
							table.insert(checked, `{name}/{palette.name}:{table.concat(shapes, ",")}`)
							stopSheet()
						end
					end
					stop()
					h.dispose()
				end
				Verify.expect((table.concat(checked, " "))):toBe(
					"compact_pointer/Aqua:Delete=art,Save=art fantasy_ornate/Grand Hall:Delete=art,Save=pressed "
						.. "fantasy_ornate/Crypt:Delete=art,Save=pressed fantasy_parchment/Daylight:Delete=art,Save=pressed "
						.. "fantasy_parchment/Candlelight:Delete=art,Save=pressed glossy_touch/Sky:Delete=art,Save=art "
						.. "pixel_quest/Quest:Delete=art,Save=pressed"
				)
			end,
		})

		verifyHarness:case("maps hover and press on each skinned part to that part's state art", {
			id = "native_parity_strength_paint::native paint strength: skins::maps hover and press on each skinned part to that part's state art",
			run = function()
				local package = themes.neutralPackage()
				local ids: { [string]: number } = { default = 1, hover = 2, pressed = 3, selected = 4 }
				for _, slot in { "field", "stepperPlate", "toggleTrack", "toggleKnob", "sliderThumb" } do
					local variants = {}
					for state, id in ids do
						local name = slot .. "-" .. state
						assert(package.assets)[name] = { content = "rbxassetid://" .. slot .. id }
						variants[state] = name
					end
					assert(package.chrome)[slot] = { kind = "nineSlice" :: "nineSlice", asset = variants }
				end
				local h = harness({ theme = package })
				local value = Compose.cell(false)
				local root, stop = mount(h, function()
					return h.Host.Frame({
						h.UI.TextInput({ Name = "Field", value = Compose.cell("Ada"), label = "Name" }) :: unknown,
						h.UI.Stepper({ Name = "Stepper", value = Compose.cell(2), min = 0, max = 5 }),
						h.UI.Toggle({ Name = "Switch", value = value, label = "On" }),
						h.UI.Slider({ Name = "Slider", value = Compose.cell(0.5) }),
					})
				end)
				local switch = find(root, "Switch")
				local parts = {
					{ find(root, "Input"), "field" },
					{ find(root, "Stepper"), "stepperPlate" },
					{ find(switch, "Indicator"), "toggleTrack" },
					{ find(switch, "Mark"), "toggleKnob" },
					{ find(find(root, "Slider"), "Thumb"), "sliderThumb" },
				}
				for _, entry in parts do
					local node, slot = entry[1], entry[2]
					local art = ownArt(node, slot)
					Verify.expect(art ~= nil):toBe(true)
					Verify.expect((node:HasTag("facet-skinned"))):toBe(true)
					for _, step in
						{
							{ state = "Idle", asset = 1 },
							{ state = "Hover", asset = 2 },
							{ state = "Press", asset = 3 },
							{ state = "Idle", asset = 1 },
						}
					do
						setState(h, node, step.state)
						Verify.expect(art.Image):toBe("rbxassetid://" .. slot .. step.asset)
					end
				end
				value:set(true)
				local indicator, mark = find(switch, "Indicator"), find(switch, "Mark")
				Verify.expect(ownArt(indicator, "toggleTrack").Image):toBe("rbxassetid://toggleTrack4")
				Verify.expect(ownArt(mark, "toggleKnob").Image):toBe("rbxassetid://toggleKnob4")
				setState(h, indicator, "Hover")
				Verify.expect(ownArt(indicator, "toggleTrack").Image):toBe("rbxassetid://toggleTrack2")
				setState(h, indicator, "Idle")
				value:set(false)
				Verify.expect(ownArt(indicator, "toggleTrack").Image):toBe("rbxassetid://toggleTrack1")
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("gives each control part the art of its own chrome slot and no other", {
			id = "native_parity_strength_paint::native paint strength: skins::gives each control part the art of its own chrome slot and no other",
			run = function()
				local slots = {
					"control",
					"field",
					"toggleTrack",
					"toggleKnob",
					"stepperPlate",
					"sliderTrack",
					"sliderThumb",
					"barFill",
					"barTrack",
					"badge",
					"panel",
				}
				local assets = {}
				for index, slot in slots do
					assets[slot] = "rbxassetid://" .. (500 + index)
				end
				local package = skinPackage(assets)
				local h = harness({ theme = package })
				local root, stop = mount(h, function()
					return h.Host.Frame({
						h.UI.Button({ Name = "Action", label = "Go" }) :: unknown,
						h.UI.TextInput({ Name = "Field", value = Compose.cell("Ada"), label = "Name" }),
						h.UI.Toggle({ Name = "Switch", value = Compose.cell(true), label = "On" }),
						h.UI.Stepper({ Name = "Stepper", value = Compose.cell(2), min = 0, max = 5 }),
						h.UI.Slider({ Name = "Slider", value = Compose.cell(0.5) }),
						h.UI.ProgressView({ Name = "Progress", value = 0.5 }),
						h.UI.Badge({ Name = "Seal", label = "3" }),
						h.UI.Alert({
							isPresented = Compose.cell(true),
							title = "Leave?",
							actions = {
								{ id = "stay", label = "Stay", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
							},
						}),
					})
				end)
				local slider, progress = find(root, "Slider"), find(root, "Progress")
				local panel = find(root.Parent, "AlertPanel")
				local expected = {
					{ find(root, "Action"), "control" },
					{ find(root, "Input"), "field" },
					{ find(find(root, "Switch"), "Indicator"), "toggleTrack" },
					{ find(find(root, "Switch"), "Mark"), "toggleKnob" },
					{ find(root, "Stepper"), "stepperPlate" },
					{ find(slider, "Rail"), "sliderTrack" },
					{ find(slider, "Thumb"), "sliderThumb" },
					{ find(slider, "Fill"), "barFill" },
					{ find(progress, "Track"), "barTrack" },
					{ tagged(progress, "facet-fill")[1], "barFill" },
					{ find(root, "Seal"), "badge" },
					{ panel, "panel" },
				}
				local seen: { [string]: boolean } = {}
				for _, entry in expected do
					local node, slot = entry[1], entry[2]
					Verify.expect(node ~= nil):toBe(true)
					Verify.expect(`{slot}: {table.concat(ownSlots(node), ",")}`):toBe(`{slot}: {slot}`)
					Verify.expect(ownArt(node, slot) ~= nil or find(node, slot .. "1") ~= nil):toBe(true)
					Verify.expect((ownArt(node, slot) or find(node, slot .. "1")).Image):toBe(assets[slot])
					Verify.expect((node:HasTag("facet-skinned"))):toBe(true)
					seen[slot] = true
				end
				for _, slot in slots do
					Verify.expect(seen[slot]):toBe(true)
				end
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case(
			"suppresses a skinned plate and its outline in every state and restores both when the art goes",
			{
				id = "native_parity_strength_paint::native paint strength: skins::suppresses a skinned plate and its outline in every state and restores both when the art goes",
				run = function()
					local _, extra = neutralColors()
					local art = skinPackage({
						control = "rbxassetid://601",
						toggleTrack = "rbxassetid://602",
						toggleKnob = "rbxassetid://603",
						sliderThumb = "rbxassetid://604",
						sliderTrack = "rbxassetid://605",
						barFill = "rbxassetid://606",
					})
					local selected = Compose.cell(art)
					local h = harness({ theme = selected })
					local sheet, stopSheet = sheetFor(h, selected)
					local options = { { value = "a", label = "A" }, { value = "b", label = "B" } }
					local root, stop = mount(h, function()
						return h.Host.Frame({
							h.UI.Button({ Name = "Soft", label = "Soft", appearance = "soft" }) :: unknown,
							h.UI.Button({ Name = "Utility", label = "Utility", appearance = "utility" }),
							h.UI.Button({
								Name = "Primary",
								label = "Primary",
								appearance = "emphasis",
								selected = true,
							}),
							h.UI.Button({ Name = "Danger", label = "Danger", role = "destructive" :: "destructive" }),
							h.Host.Frame({
								Name = "Segmented",
								h.UI.Picker({
									selected = Compose.cell("a"),
									style = "segmented" :: "segmented",
									options = options,
								}),
							}),
							h.UI.Toggle({
								Name = "Box",
								value = Compose.cell(true),
								label = "Box",
								presentation = "checkbox" :: "checkbox",
							}),
							h.UI.Slider({ Name = "Slider", value = Compose.cell(0.5) }),
						})
					end)
					local box = find(find(root, "Box"), "Indicator")
					local slider = find(root, "Slider")
					local nodes = {
						find(root, "Soft"),
						find(root, "Primary"),
						find(root, "Danger"),
						find(find(root, "Segmented"), "a"),
						find(slider, "Thumb"),
						find(slider, "Rail"),
						find(slider, "Fill"),
					}
					Verify.expect((find(find(root, "Segmented"), "a"):HasTag("facet-segment-current"))):toBe(true)
					Verify.expect((find(root, "Utility"):HasTag("facet-skinned"))):toBe(false)
					Verify.expect((box:HasTag("facet-skinned"))):toBe(false)
					local function sweep(expectSkinned: boolean)
						for _, node in nodes do
							Verify.expect((node:HasTag("facet-skinned"))):toBe(expectSkinned)
							for _, state in { "Idle", "Hover", "Press" } do
								setState(h, node, state)
								local transparency = resolve(sheet, node, "BackgroundTransparency")
								if node:HasTag("facet-segment-current") then
									Verify.expect(transparency):toBe(1)
									Verify.expect(
										(resolve(sheet, find(node.Parent, "SelectionFill"), "BackgroundTransparency"))
									)
										:toBe(0)
								elseif expectSkinned then
									Verify.expect(transparency):toBe(1)
								else
									Verify.expect(transparency ~= 1 or node == find(root, "Utility")):toBe(true)
								end
							end
							setState(h, node, "Idle")
						end
					end
					sweep(true)
					Verify.expect((resolve(sheet, box, "Transparency", "UIStroke"))):toBe(0.2)
					local menu = h.engine.new("Frame")
					menu:AddTag("facet-menu")
					menu:AddTag("facet-skinned")
					Verify.expect((resolve(sheet, menu, "Transparency", "UIStroke"))):toBe(1)
					menu:RemoveTag("facet-skinned")
					Verify.expect((resolve(sheet, menu, "Transparency", "UIStroke"))):toBe(0.3)
					Verify.expect(
						ruleNode(sheet, ".facet-skinned").Priority
							> ruleNode(sheet, ".facet-appearance-utility:Hover").Priority
					):toBe(true)
					Verify.expect(
						ruleNode(sheet, ".facet-skinned").Priority > ruleNode(sheet, ".facet-segment-current").Priority
					)
						:toBe(true)
					selected:set(themes.neutralPackage())
					Verify.expect(#tagged(root, "facet-skinned")):toBe(0)
					sweep(false)
					Verify.expect((resolve(sheet, find(root, "Soft"), "BackgroundTransparency"))):toBe(0.8)
					Verify.expect((resolve(sheet, find(root, "Danger"), "BackgroundTransparency"))):toBe(0)
					Verify.expect((resolve(sheet, find(root, "Primary"), "BackgroundColor3")))
						:toBe(color(h.engine, neutralColors().accent))
					Verify.expect((resolve(sheet, find(slider, "Thumb"), "BackgroundColor3")))
						:toBe(color(h.engine, neutralColors().accent))
					Verify.expect((resolve(sheet, find(slider, "Rail"), "BackgroundColor3")))
						:toBe(color(h.engine, extra.control))
					Verify.expect((resolve(sheet, box, "Transparency", "UIStroke"))):toBe(0.2)
					selected:set(art)
					sweep(true)
					stop()
					stopSheet()
					h.dispose()
				end,
			}
		)

		verifyHarness:case("drops the skinned tag from a field and a button when the package stops drawing their art", {
			id = "native_parity_strength_paint::native paint strength: skins::drops the skinned tag from a field and a button when the package stops drawing their art",
			run = function()
				local art = skinPackage({ field = "rbxassetid://701", control = "rbxassetid://702" })
				local missing = themes.neutralPackage()
				assert(missing.chrome).field = {
					kind = "layered" :: "layered",
					layers = { { kind = "fill" :: "fill", asset = "absent" } :: FixtureThemeTypes.SkinLayer },
				}
				assert(missing.chrome).control = { kind = "native" :: "native" }
				local none = themes.neutralPackage()
				assert(none.chrome).field = { kind = "none" :: "none" }
				assert(none.chrome).control = { kind = "none" :: "none" }
				local selected = Compose.cell(art)
				local h = harness({ theme = selected })
				local sheet, stopSheet = sheetFor(h, selected)
				local root, stop = mount(h, function()
					return h.Host.Frame({
						h.UI.TextInput({ Name = "Framed", value = Compose.cell("Ada"), label = "Name" }) :: unknown,
						h.UI.Button({ Name = "Action", label = "Go" }),
					})
				end)
				local field, action = find(root, "Input"), find(root, "Action")
				Verify.expect(field.ClassName):toBe("Frame")
				local plain = {}
				for _, package in { art, missing, none, art } do
					selected:set(package)
					local drawn = package == art
					for _, node in { field, action } do
						Verify.expect((node:HasTag("facet-skinned"))):toBe(drawn)
						local transparency = resolve(sheet, node, "BackgroundTransparency")
						if drawn then
							Verify.expect(transparency):toBe(1)
						else
							Verify.expect(transparency):toBe(0)
							plain[node] = resolve(sheet, node, "BackgroundColor3")
						end
					end
					local image = ownArt(field, "field")
					Verify.expect(image == nil or image.Visible == drawn):toBe(true)
				end
				Verify.expect(plain[field] ~= nil and plain[action] ~= nil):toBe(true)
				Verify.expect(find(field, "Field").Text):toBe("Ada")
				stop()
				stopSheet()
				h.dispose()
			end,
		})

		verifyHarness:case("marks only the value parts a package actually skins", {
			id = "native_parity_strength_paint::native paint strength: skins::marks only the value parts a package actually skins",
			run = function()
				local _, extra = neutralColors()
				local colors = neutralColors()
				local package = skinPackage({
					sliderThumb = "rbxassetid://801",
					toggleKnob = "rbxassetid://802",
					barFill = "rbxassetid://803",
				})
				local h = harness({ theme = package })
				local sheet, stopSheet = sheetFor(h, package)
				local root, stop = mount(h, function()
					return h.Host.Frame({
						h.UI.Slider({ Name = "Slider", value = Compose.cell(0.5) }) :: unknown,
						h.UI.Toggle({ Name = "Switch", value = Compose.cell(true), label = "On" }),
						h.UI.ProgressView({ Name = "Progress", value = 0.5 }),
						h.UI.Stepper({ Name = "Stepper", value = Compose.cell(2), min = 0, max = 5 }),
					})
				end)
				local slider, switch, progress = find(root, "Slider"), find(root, "Switch"), find(root, "Progress")
				local skinned = {
					find(slider, "Thumb"),
					find(slider, "Fill"),
					find(switch, "Mark"),
					tagged(progress, "facet-fill")[1],
				}
				local bare = {
					{ find(slider, "Rail"), extra.control },
					{ find(switch, "Indicator"), colors.accent },
					{ find(progress, "Track"), extra.control },
					{ find(find(root, "Stepper"), "Controls"), extra.control },
				}
				for _, node in skinned do
					Verify.expect((node:HasTag("facet-skinned"))):toBe(true)
					Verify.expect((resolve(sheet, node, "BackgroundTransparency"))):toBe(1)
				end
				for _, entry in bare do
					local node = entry[1]
					Verify.expect((node:HasTag("facet-skinned"))):toBe(false)
					Verify.expect((resolve(sheet, node, "BackgroundTransparency"))):toBe(0)
					Verify.expect((resolve(sheet, node, "BackgroundColor3"))):toBe(color(h.engine, entry[2]))
				end
				Verify.expect(#tagged(root, "facet-skinned")):toBe(#skinned)
				Verify.expect((find(root, "Stepper"):HasTag("facet-skinned"))):toBe(false)
				stop()
				stopSheet()
				h.dispose()
			end,
		})

		verifyHarness:case("keeps full-bleed art on the plate's own box when the padding changes after mount", {
			id = "native_parity_strength_paint::native paint strength: skins::keeps full-bleed art on the plate's own box when the padding changes after mount",
			run = function()
				local package = skinPackage({ control = "rbxassetid://123" })
				local h = harness({ theme = package })
				local root, stop = mount(h, function()
					return h.UI.Button({ Name = "Plate", label = "Mark read" })
				end)
				local plate = find(root, "Plate")
				local skin, label = find(plate, "SkinBounds"), find(plate, "LabelBounds")
				local UDim = h.engine.types.UDim
				local hostX, hostWidth = 10, 83
				plate.AbsoluteSize = h.engine.types.Vector2.new(hostWidth, 28)
				for _, bounds in { skin, label } do
					bounds.Parent.AbsoluteSize = h.engine.types.Vector2.new(1, 1)
				end
				local padding = plate:FindFirstChildWhichIsA("UIPadding")
				local function painted(bounds: any): (number, number)
					local right = padding.PaddingRight.Offset
					local boundaryLeft = hostX + hostWidth - right - 1
					local rightEdge = boundaryLeft + bounds.Position.X.Offset
					return rightEdge - bounds.Size.X.Offset, rightEdge
				end
				for _, inset in { 12, 8, 0, 8 } do
					padding.PaddingLeft = UDim.new(0, inset)
					padding.PaddingRight = UDim.new(0, inset)
					local left, right = painted(skin)
					Verify.expect(`{left}..{right}`):toBe("10..93")
					local textLeft, textRight = painted(label)
					Verify.expect(`{textLeft}..{textRight}`):toBe(`{10 + inset}..{93 - inset}`)
				end
				padding.PaddingLeft = UDim.new(0, 12)
				padding.PaddingRight = UDim.new(0, 8)
				local left, right = painted(skin)
				Verify.expect(`{left}..{right}`):toBe("10..93")
				local textLeft, textRight = painted(label)
				Verify.expect(`{textLeft}..{textRight}`):toBe("22..85")
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("renders the declared shadow of every shipped package slot and none for flat packages", {
			id = "native_parity_strength_paint::native paint strength: skins::renders the declared shadow of every shipped package slot and none for flat packages",
			run = function()
				local presets = {
					raised = { blur = 14, transparency = 0.35, y = 3 },
				}
				local expectations: { [string]: { [string]: any } } = {
					fantasy_parchment = { panel = "raised", control = "raised" },
					fantasy_ornate = { panel = "raised", control = "raised" },
					glossy_mobile = { panel = "raised", control = "raised" },
					glossy_touch = { panel = "raised" },
					scifi_hud = {
						panel = { blur = 24, transparency = 0.3 },
						control = { blur = 16, transparency = 0.28 },
					},
					classic_desktop = {},
					compact_pointer = {},
					pixel_quest = {},
				}
				local candidates = {}
				for name, slots in expectations do
					table.insert(candidates, { name = name, package = (shipped(name)), slots = slots })
				end
				table.insert(candidates, { name = "neutral", package = themes.neutralPackage(), slots = {} })
				for _, entry in candidates do
					local h = harness({ theme = entry.package })
					for _, slot in { "panel", "control" } do
						local target
						local stop = h.runtime.mount(function()
							target = h.Host.Frame({ Name = "Host" })
							h.runtime.mount(function()
								return themes.skin(
									h.runtime,
									entry.package,
									slot,
									{ types = h.engine.types, target = target }
								)
							end, target)
							return target
						end, h.engine.new("ScreenGui"))
						local shadow = target:FindFirstChild("ChromeShadow")
						local want = entry.slots[slot]
						if want == nil then
							Verify.expect(shadow == nil or shadow.Enabled == false):toBe(true)
						else
							local numbers = if type(want) == "string" then presets[want] else want
							Verify.expect(shadow.ClassName):toBe("UIShadow")
							Verify.expect(shadow.Enabled):toBe(true)
							Verify.expect(shadow.BlurRadius):toBe(h.engine.types.UDim.new(0, numbers.blur))
							Verify.expect(shadow.Transparency):toBe(numbers.transparency)
							Verify.expect(shadow.ZIndex < 0):toBe(true)
							if numbers.y then
								Verify.expect(shadow.Offset):toBe(h.engine.types.UDim2.new(0, 0, 0, numbers.y))
							end
							if entry.name == "scifi_hud" then
								Verify.expect(shadow.Color):toBe(h.engine.types.Color3.new(0.05, 0.42, 0.5))
								Verify.expect(shadow.Color.B > shadow.Color.R):toBe(true)
							end
							if entry.name == "glossy_mobile" then
								Verify.expect(entry.package.chrome[slot].kind):toBe("native")
								local images = 0
								for _, node in target:GetDescendants() do
									if node.ClassName == "ImageLabel" then
										images += 1
									end
								end
								Verify.expect(images):toBe(0)
							end
						end
						stop()
					end
					local root, stopButton = mount(h, function()
						return h.UI.Button({ Name = "Action", label = "Go" })
					end)
					local shadow = find(root, "Action"):FindFirstChild("ChromeShadow")
					Verify.expect(shadow ~= nil and shadow.Enabled):toBe(entry.slots.control ~= nil)
					stopButton()
					h.dispose()
				end
			end,
		})

		verifyHarness:case("resolves the overlay preset and package-named shadows on the native shadow", {
			id = "native_parity_strength_paint::native paint strength: skins::resolves the overlay preset and package-named shadows on the native shadow",
			run = function()
				local definition = themes.neutralPackage()
				definition.style.shadows = {
					lifted = {
						blurRadius = { offset = 9 },
						transparency = 0.2,
						offset = { x = { offset = 2 }, y = { offset = 5 } },
					},
					raised = { blurRadius = { offset = 30 }, transparency = 0.6, color = { r = 0.2, g = 0, b = 0 } },
				}
				assert(definition.chrome).control = { kind = "native" :: "native", shadow = "overlay" }
				assert(definition.chrome).panel = { kind = "native" :: "native", shadow = "lifted" }
				assert(definition.chrome).field = { kind = "native" :: "native", shadow = "raised" }
				local package, report = themes.define(definition)
				Verify.expect(report.ok):toBe(true)
				local h = harness({ theme = package })
				local UDim, UDim2 = h.engine.types.UDim, h.engine.types.UDim2
				local root, stop = mount(h, function()
					return h.Host.Frame({
						h.UI.Button({ Name = "Action", label = "Go" }) :: unknown,
						h.UI.TextInput({ Name = "Field", value = Compose.cell("") }),
					})
				end)
				local overlay = find(root, "Action"):FindFirstChild("ChromeShadow")
				Verify.expect(overlay.BlurRadius):toBe(UDim.new(0, 24))
				Verify.expect(overlay.Transparency):toBe(0.45)
				Verify.expect(overlay.Offset):toBe(UDim2.new(0, 0, 0, 8))
				Verify.expect(overlay.ZIndex):toBe(-1)
				Verify.expect(overlay.Color):toBe(h.engine.types.Color3.new(0, 0, 0))
				local owned = find(root, "Field"):FindFirstChild("ChromeShadow")
				Verify.expect(owned.BlurRadius):toBe(UDim.new(0, 30))
				Verify.expect(owned.Transparency):toBe(0.6)
				Verify.expect(owned.Color):toBe(h.engine.types.Color3.new(0.2, 0, 0))
				stop()
				local target
				local stopPanel = h.runtime.mount(function()
					target = h.Host.Frame({ Name = "Panel" })
					h.runtime.mount(function()
						return themes.skin(h.runtime, package, "panel", { types = h.engine.types, target = target })
					end, target)
					return target
				end, h.engine.new("ScreenGui"))
				local lifted = target:FindFirstChild("ChromeShadow")
				Verify.expect(lifted.BlurRadius):toBe(UDim.new(0, 9))
				Verify.expect(lifted.Transparency):toBe(0.2)
				Verify.expect(lifted.Offset):toBe(UDim2.new(0, 2, 0, 5))
				stopPanel()
				h.dispose()
				local live = themes.neutralPackage()
				assert(live.chrome).control = { kind = "native" :: "native", shadow = "overlay" }
				local selected = Compose.cell(live)
				local reactive = harness({ theme = selected })
				local reactiveRoot, stopReactive = mount(reactive, function()
					return reactive.UI.Button({ Name = "Action", label = "Go" })
				end)
				local shadow = find(reactiveRoot, "Action"):FindFirstChild("ChromeShadow")
				Verify.expect(shadow.BlurRadius):toBe(UDim.new(0, 24))
				local named = themes.neutralPackage()
				named.style.shadows = { lifted = { blurRadius = { offset = 9 }, transparency = 0.2 } }
				assert(named.chrome).control = { kind = "native" :: "native", shadow = "lifted" }
				selected:set(named)
				Verify.expect((find(reactiveRoot, "Action"):FindFirstChild("ChromeShadow"))):toBe(shadow)
				Verify.expect(shadow.BlurRadius):toBe(UDim.new(0, 9))
				Verify.expect(shadow.Transparency):toBe(0.2)
				stopReactive()
				reactive.dispose()
				local unknown = themes.neutralPackage()
				assert(unknown.chrome).control = { kind = "native" :: "native", shadow = "floaty" }
				local rejected, failure = themes.define(unknown)
				Verify.expect(rejected):toBe(nil)
				Verify.expect(failure.errors[1].field):toBe("chrome.control.shadow")
			end,
		})
	end)

	local function countWrites(sheet: any): { [any]: number }
		local writes: { [any]: number } = {}
		for _, rule in sheet:GetChildren() do
			local original = rule.SetProperties
			rule.SetProperties = function(self: any, properties: any)
				writes[self] = (writes[self] or 0) + 1
				return original(self, properties)
			end
		end
		return writes
	end

	verifyHarness:suite("native paint strength: theme sheets", function()
		verifyHarness:case(
			"falls back to GuiService transparency and a 0.2 second paint transition that the engine's Reduce Motion (limited) keeps",
			{
				id = "native_parity_strength_paint::native paint strength: theme sheets::falls back to GuiService transparency and a 0.2 second paint transition that the engine's Reduce Motion (limited) keeps",
				run = function()
					local h = harness()
					local environment = (getfenv :: any)(0)
					local gui = h.engine.new("GuiService")
					gui.ReducedMotionEnabled = false
					gui.PreferredTransparency = 0.5
					local requested = {}
					environment.game = {
						GetService = function(_, name: string)
							table.insert(requested, name)
							return if name == "UserInputService" then h.input else gui
						end,
					}
					local package = themes.neutralPackage()
					local absentMotionMetrics = package.metrics :: any
					absentMotionMetrics.motion = nil
					local stop, sheet = h.runtime.mount(function()
						return themes.createStyleSheet(h.runtime, package, { types = h.engine.types })
					end, h.engine.new("Folder"))
					environment.game = nil
					Verify.expect(requested)
						:toEqual({ "GuiService", "UserInputService", "GuiService", "UserInputService" })
					local text = ruleNode(sheet, ".facet-text")
					local timing = transitionOf(text, "TextColor3")
					Verify.expect(timing.Time):toBe(0.2)
					Verify.expect(timing.EasingStyle):toBe(h.engine.types.Enum.EasingStyle.Quad)
					Verify.expect(timing.EasingDirection):toBe(h.engine.types.Enum.EasingDirection.Out)
					Verify.expect((transitionOf(ruleNode(sheet, ".facet-surface"), "BackgroundTransparency")))
						:toBe(timing)
					Verify.expect(style(sheet, ".facet-scrim").BackgroundTransparency):toBeCloseTo(0.55 * 0.5, 1e-4)
					gui.ReducedMotionEnabled = true
					Verify.expect(transitionOf(text, "TextColor3").Time):toBe(0.2)
					gui.ReducedMotionEnabled = false
					Verify.expect(transitionOf(text, "TextColor3").Time):toBe(0.2)
					gui.PreferredTransparency = 1
					Verify.expect(style(sheet, ".facet-scrim").BackgroundTransparency):toBeCloseTo(0.55, 1e-4)
					Verify.expect((engineLib.connections(gui:GetPropertyChangedSignal("ReducedMotionEnabled")))):toBe(0)
					Verify.expect((engineLib.connections(gui:GetPropertyChangedSignal("PreferredTransparency"))))
						:toBe(1)
					stop()
					Verify.expect((engineLib.connections(gui:GetPropertyChangedSignal("ReducedMotionEnabled")))):toBe(0)
					Verify.expect((engineLib.connections(gui:GetPropertyChangedSignal("PreferredTransparency"))))
						:toBe(0)
					local halfDeclared = themes.neutralPackage()
					local partialMotionMetrics = halfDeclared.metrics :: any
					partialMotionMetrics.motion = { fast = 0.1 }
					local second, stopSecond = sheetFor(h, halfDeclared)
					Verify.expect(transitionOf(ruleNode(second, ".facet-text"), "TextColor3").Time):toBe(0.2)
					stopSecond()
					local headless, stopHeadless = sheetFor(h, themes.neutralPackage(), { reducedMotion = nil })
					Verify.expect(transitionOf(ruleNode(headless, ".facet-text"), "TextColor3").Time):toBe(0.2)
					stopHeadless()
					h.dispose()
				end,
			}
		)

		verifyHarness:case(
			"writes per-side button insets to the padding rules and costs no writes when nothing changes",
			{
				id = "native_parity_strength_paint::native paint strength: theme sheets::writes per-side button insets to the padding rules and costs no writes when nothing changes",
				run = function()
					local h = harness()
					local UDim = h.engine.types.UDim
					local package = Compose.cell(themes.neutralPackage())
					local sheet, stop = sheetFor(h, package)
					local function padding(selector: string): { number }
						local properties = style(sheet, selector)
						return {
							properties.PaddingLeft and properties.PaddingLeft.Offset,
							properties.PaddingRight and properties.PaddingRight.Offset,
							properties.PaddingTop and properties.PaddingTop.Offset,
							properties.PaddingBottom and properties.PaddingBottom.Offset,
						} :: any
					end
					Verify.expect((padding(".facet-button::UIPadding"))):toEqual({ 12, 12, 0, 0 })
					Verify.expect((padding(".facet-button > UIPadding"))):toEqual({ 12, 12, 0, 0 })
					Verify.expect((padding(".facet-shape-circle::UIPadding"))):toEqual({ 0, 0, 0, 0 })
					Verify.expect((padding(".facet-badge::UIPadding"))):toEqual({ 8, 8, 3, 3 })
					local writes = countWrites(sheet)
					package:set(themes.neutralPackage())
					Verify.expect((next(writes))):toBe(nil)
					local inset = themes.neutralPackage()
					assert(inset.assets).plate = { content = "rbxassetid://9" }
					assert(inset.chrome).control = {
						kind = "nineSlice" :: "nineSlice",
						asset = "plate",
						contentInsets = { left = 20, right = 14, top = 6, bottom = 9 },
					}
					package:set(inset)
					Verify.expect((padding(".facet-button::UIPadding"))):toEqual({ 32, 26, 6, 9 })
					Verify.expect((padding(".facet-button > UIPadding"))):toEqual({ 32, 26, 6, 9 })
					Verify.expect(style(sheet, ".facet-button-described::UIPadding").PaddingTop):toBe(UDim.new(0, 16))
					Verify.expect(style(sheet, ".facet-button-described::UIPadding").PaddingBottom)
						:toBe(UDim.new(0, 19))
					Verify.expect(style(sheet, ".facet-busy::UIPadding").PaddingRight):toBe(UDim.new(0, 46))
					Verify.expect(style(sheet, ".facet-disclosure::UIPadding").PaddingRight):toBe(UDim.new(0, 46))
					Verify.expect(writes[ruleNode(sheet, ".facet-button::UIPadding")]):toBe(1)
					Verify.expect(writes[ruleNode(sheet, ".facet-button > UIPadding")]):toBe(1)
					Verify.expect(writes[ruleNode(sheet, ".facet-field::UIPadding")]):toBe(nil)
					Verify.expect(writes[ruleNode(sheet, ".facet-button")]):toBe(nil)
					Verify.expect(writes[ruleNode(sheet, ".facet-button::UICorner")]):toBe(nil)
					table.clear(writes)
					local same = themes.neutralPackage()
					assert(same.assets).plate = { content = "rbxassetid://9" }
					assert(same.chrome).control = {
						kind = "nineSlice" :: "nineSlice",
						asset = "plate",
						contentInsets = { left = 20, right = 14, top = 6, bottom = 9 },
					}
					package:set(same)
					Verify.expect((next(writes))):toBe(nil)
					local narrow = table.clone(same)
					narrow.chrome = table.clone(same.chrome)
					assert(narrow.chrome).control =
						{ kind = "nineSlice" :: "nineSlice", asset = "plate", contentInsets = { left = 4, top = 2 } }
					package:set(narrow)
					Verify.expect((padding(".facet-button::UIPadding"))):toEqual({ 16, 12, 2, 0 })
					table.clear(writes)
					local metric = table.clone(narrow)
					metric.metrics = table.clone(narrow.metrics)
					metric.metrics.radii = { control = 5, panel = 12, pill = 999 }
					package:set(metric)
					Verify.expect(writes[ruleNode(sheet, ".facet-button::UICorner")]):toBe(1)
					Verify.expect(style(sheet, ".facet-button::UICorner").CornerRadius):toBe(UDim.new(0, 5))
					Verify.expect(writes[ruleNode(sheet, ".facet-button::UIPadding")]):toBe(nil)
					stop()
					h.dispose()
				end,
			}
		)

		verifyHarness:case(
			"orders every state rule after its base and disabled after selection in every shipped sheet",
			{
				id = "native_parity_strength_paint::native paint strength: theme sheets::orders every state rule after its base and disabled after selection in every shipped sheet",
				run = function()
					local h = harness()
					local packages = { themes.neutralPackage() }
					for _, name in SHIPPED do
						table.insert(packages, (shipped(name)))
					end
					local checkedStates = 0
					for _, package in packages do
						for _, palette in package.style.themes do
							local sheet, stop = sheetFor(h, package, { theme = palette.name })
							local first: { [string]: number } = {}
							for _, rule in sheet:GetChildren() do
								if first[rule.Selector] == nil then
									first[rule.Selector] = rule.Priority
								end
							end
							for selector, priority in first do
								local base, state = string.match(selector, "^(.-):(%a+)$")
								if base and string.sub(base, -1) ~= ":" and (state == "Hover" or state == "Press") then
									Verify.expect(first[base] ~= nil):toBe(true)
									Verify.expect(priority > first[base]):toBe(true)
									checkedStates += 1
									if state == "Press" and first[base .. ":Hover"] then
										Verify.expect(priority > first[base .. ":Hover"]):toBe(true)
									end
								end
							end
							Verify.expect(first[".facet-text"] < first[".facet-surface"]):toBe(true)
							Verify.expect(first[".facet-control"] < first[".facet-button:Hover"]):toBe(true)
							Verify.expect(first[".facet-button:Hover"] < first[".facet-button:Press"]):toBe(true)
							Verify.expect(first[".facet-button:Press"] < first[".facet-selected"]):toBe(true)
							Verify.expect(first[".facet-selected"] < first[".facet-disabled"]):toBe(true)
							for _, role in { ".facet-role-destructive", ".facet-accent", ".facet-appearance-soft" } do
								Verify.expect(first[role] > first[".facet-button"]):toBe(true)
							end
							Verify.expect(first[".facet-skinned"] > first[".facet-segment-current:Hover"]):toBe(true)
							stop()
						end
					end
					Verify.expect(checkedStates > 12 * 15):toBe(true)
					h.dispose()
				end,
			}
		)

		verifyHarness:case("paints the authored selected label or the content color and rejects an unreadable one", {
			id = "native_parity_strength_paint::native paint strength: theme sheets::paints the authored selected label or the content color and rejects an unreadable one",
			run = function()
				local h = harness()
				local colors, extra = neutralColors()
				local sheet, stop = sheetFor(h, themes.neutralPackage())
				for _, selector in { ".facet-selected", ".facet-selected >> .facet-text" } do
					Verify.expect(style(sheet, selector).TextColor3):toBe(color(h.engine, colors.content))
				end
				Verify.expect(style(sheet, ".facet-selected >> .facet-icon").ImageColor3)
					:toBe(color(h.engine, colors.content))
				stop()
				local authored = themes.neutralPackage()
				assert(authored.style.themes[1].extra).controlSelected = { r = 0.1, g = 0.3, b = 0.8 }
				assert(authored.style.themes[1].extra).onSelected = { r = 1, g = 1, b = 1 }
				local package, report = themes.define(authored)
				Verify.expect(report.ok):toBe(true)
				local pairs = {}
				for _, entry in report.contrast do
					if entry.pair == "onSelected/controlSelected" then
						table.insert(pairs, entry)
					end
				end
				Verify.expect(#pairs):toBe(#authored.style.themes)
				Verify.expect(pairs[1].ok):toBe(true)
				Verify.expect(pairs[1].ratio)
					:toBeCloseTo(contrast({ r = 1, g = 1, b = 1 }, { r = 0.1, g = 0.3, b = 0.8 }), 1e-4)
				for index = 2, #pairs do
					local palette = authored.style.themes[index]
					Verify.expect(pairs[index].ok):toBe(true)
					Verify.expect(pairs[index].ratio):toBeCloseTo(
						contrast(
							assert(palette.extra).onSelected or palette.colors.content,
							assert(palette.extra).controlSelected
						),
						1e-4
					)
				end
				local authoredSheet, stopAuthored = sheetFor(h, package)
				local white = h.engine.types.Color3.new(1, 1, 1)
				local root, stopMount = mount(h, function()
					return h.UI.Button({ Name = "Chosen", label = "Chosen", icon = "checkmark", selected = true })
				end)
				local chosen = find(root, "Chosen")
				Verify.expect((resolve(authoredSheet, chosen, "BackgroundColor3")))
					:toBe(h.engine.types.Color3.new(0.1, 0.3, 0.8))
				Verify.expect((resolve(authoredSheet, find(chosen, "Title"), "TextColor3"))):toBe(white)
				Verify.expect((resolve(authoredSheet, find(chosen, "LeadingIcon"), "ImageColor3"))):toBe(white)
				stopMount()
				stopAuthored()
				local unreadable = themes.neutralPackage()
				assert(unreadable.style.themes[1].extra).onSelected =
					assert(unreadable.style.themes[1].extra).controlSelected
				local rejected, failure = themes.define(unreadable)
				Verify.expect(rejected):toBe(nil)
				Verify.expect(failure.errors[1].field):toBe("style.Dark")
				Verify.expect(failure.errors[1].message):toBe("onSelected contrast is below 4.5:1")
				local dark = themes.neutralPackage()
				assert(dark.style.themes[1].extra).controlSelected = { r = 0.85, g = 0.88, b = 0.92 }
				local noPartner = themes.define(dark)
				Verify.expect(noPartner):toBe(nil)
				Verify.expect(extra.onSelected):toBe(nil)
				h.dispose()
			end,
		})

		verifyHarness:case("rewrites only changed rules and keeps a designer edit on an untouched rule", {
			id = "native_parity_strength_paint::native paint strength: theme sheets::rewrites only changed rules and keeps a designer edit on an untouched rule",
			run = function()
				local h = harness()
				local base = themes.neutralPackage()
				local package = Compose.cell(base)
				local sheet, stop = sheetFor(h, package)
				local writes = countWrites(sheet)
				local tooltip = ruleNode(sheet, ".facet-tooltip::UIStroke")
				local edited = tooltip:GetProperties()
				edited.Thickness = 3
				tooltip:SetProperties(edited)
				table.clear(writes)
				local recolored = themes.neutralPackage()
				recolored.style.themes[1].colors.accent = { r = 0.9, g = 0.2, b = 0.4 }
				package:set(recolored)
				local accent = h.engine.types.Color3.new(0.9, 0.2, 0.4)
				Verify.expect(style(sheet, ".facet-accent").BackgroundColor3):toBe(accent)
				Verify.expect(writes[ruleNode(sheet, ".facet-accent")]):toBe(1)
				Verify.expect(writes[tooltip]):toBe(nil)
				Verify.expect(tooltip:GetProperties().Thickness):toBe(3)
				Verify.expect(writes[ruleNode(sheet, ".facet-text")]):toBe(nil)
				Verify.expect(writes[ruleNode(sheet, ".facet-button::UICorner")]):toBe(nil)
				for rule in writes do
					local properties = rule:GetProperties()
					local touched = false
					for _, value in properties do
						if value == accent then
							touched = true
						end
					end
					Verify.expect(touched):toBe(true)
				end
				table.clear(writes)
				local metric = themes.neutralPackage()
				metric.style.themes[1].colors.accent = { r = 0.9, g = 0.2, b = 0.4 }
				metric.metrics.radii.control = 3
				metric.metrics.typography.control.size = 22
				package:set(metric)
				Verify.expect(writes[ruleNode(sheet, ".facet-button::UICorner")]):toBe(1)
				Verify.expect(style(sheet, ".facet-button::UICorner").CornerRadius):toBe(h.engine.types.UDim.new(0, 3))
				Verify.expect(writes[ruleNode(sheet, ".facet-button")]):toBe(1)
				Verify.expect(style(sheet, ".facet-button").TextSize):toBe(22)
				Verify.expect(writes[ruleNode(sheet, ".facet-accent")]):toBe(nil)
				Verify.expect(writes[tooltip]):toBe(nil)
				Verify.expect(tooltip:GetProperties().Thickness):toBe(3)
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case(
			"keeps each selection art declaration close to its sampled plate and pins the readable label",
			{
				id = "native_parity_strength_paint::native paint strength: theme sheets::keeps each selection art declaration close to its sampled plate and pins the readable label",
				run = function()
					local samples = serde.decode("json", fs.readFile("assets/themes/plate-samples.json")).samples
					local function distance(a: any, b: any): number
						return math.sqrt((a.r - b.r) ^ 2 + (a.g - b.g) ^ 2 + (a.b - b.b) ^ 2)
					end
					local pinned = {}
					local hashed = 0
					for key, entry in samples do
						for _, sample in entry do
							Verify.expect((serde.hash("sha256", fs.readFile(sample.file)))):toBe(sample.sha256)
							Verify.expect(sample.alpha >= 0.9):toBe(true)
							hashed += 1
						end
						local plate = entry.selected
						if plate then
							local package = shipped((string.gsub(key, "-", "_")))
							local art = { r = plate.r / 255, g = plate.g / 255, b = plate.b / 255 }
							for _, palette in package.style.themes do
								local colors, extra = paletteOf(palette)
								local accent = colors.accent
								local asset = package.chrome.control.asset
								local link = if type(asset) == "table" then asset.selected else nil
								local declared = if type(link) == "table" then link.tint else nil
								local tint = declared
									or {
										r = 1 + (accent.r - 1) * 0.35,
										g = 1 + (accent.g - 1) * 0.35,
										b = 1 + (accent.b - 1) * 0.35,
									}
								local tinted = { r = art.r * tint.r, g = art.g * tint.g, b = art.b * tint.b }
								Verify.expect(
									distance(extra.controlSelected, tinted) <= if declared then 1 / 255 else 0.12
								)
									:toBe(true)
								local label = extra.onSelected or colors.content
								Verify.expect(contrast(label, if declared then tinted else art) >= 4.5):toBe(true)
								Verify.expect(contrast(label, extra.controlSelected) >= 4.5):toBe(true)
								table.insert(
									pinned,
									`{key}/{palette.name}={if extra.onSelected then "onSelected" else "content"}`
								)
							end
						end
					end
					table.sort(pinned)
					Verify.expect(hashed):toBe(15)
					Verify.expect((table.concat(pinned, " "))):toBe(
						"compact-pointer/Aqua=content fantasy-ornate/Crypt=content fantasy-ornate/Grand Hall=content "
							.. "fantasy-parchment/Candlelight=onSelected fantasy-parchment/Daylight=onSelected "
							.. "glossy-touch/Sky=onSelected pixel-quest/Quest=onSelected"
					)
				end,
			}
		)

		verifyHarness:case("reports contrast with the written-out WCAG formula for every shipped pair", {
			id = "native_parity_strength_paint::native paint strength: theme sheets::reports contrast with the written-out WCAG formula for every shipped pair",
			run = function()
				local function wcag(value: any): number
					local function linear(channel: number): number
						return if channel <= 0.03928 then channel / 12.92 else ((channel + 0.055) / 1.055) ^ 2.4
					end
					return 0.2126 * linear(value.r) + 0.7152 * linear(value.g) + 0.0722 * linear(value.b)
				end
				local function ratio(first: any, second: any): number
					local a, b = wcag(first), wcag(second)
					return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05)
				end
				local measured = 0
				for _, name in SHIPPED do
					local package, report = shipped(name)
					local index = 0
					for _, palette in package.style.themes do
						local colors, extra = paletteOf(palette)
						for _, pair in
							{
								{ "content", "surface" },
								{ "contentStrong", "surfaceStrong" },
								{ "onAccent", "accent" },
								{ "onDanger", "danger" },
								{ "onSuccess", "success" },
								{ "onWarning", "warning" },
								{ "onSelected", "controlSelected" },
							}
						do
							index += 1
							local entry = report.contrast[index]
							Verify.expect(entry.pair):toBe(pair[1] .. "/" .. pair[2])
							local first = colors[pair[1]] or extra[pair[1]] or colors.content
							local second = colors[pair[2]] or extra[pair[2]]
							Verify.expect(math.abs(entry.ratio - ratio(first, second)) < 1e-4):toBe(true)
							Verify.expect(math.abs(entry.ratio - contrast(first, second)) < 1e-9):toBe(true)
							Verify.expect(entry.ok):toBe(entry.ratio >= 4.5)
							measured += 1
						end
					end
					Verify.expect(#report.contrast):toBe(index)
				end
				Verify.expect(measured):toBe(11 * 7)
				local extreme = themes.neutralPackage()
				extreme.style.themes[1].colors.content = { r = 1, g = 1, b = 1 }
				extreme.style.themes[1].colors.surface = { r = 0, g = 0, b = 0 }
				local _, report = themes.define(extreme)
				Verify.expect(report.contrast[1].pair):toBe("content/surface")
				Verify.expect(report.contrast[1].ratio):toBe(21)
				local same = themes.neutralPackage()
				same.style.themes[1].colors.content = same.style.themes[1].colors.surface
				local _, flat = themes.define(same)
				Verify.expect(flat.contrast[1].ratio):toBe(1)
				Verify.expect(flat.contrast[1].ok):toBe(false)
			end,
		})

		verifyHarness:case("keeps every token pair readable and the accent indicator visible on its surface", {
			id = "native_parity_strength_paint::native paint strength: theme sheets::keeps every token pair readable and the accent indicator visible on its surface",
			run = function()
				local h = harness()
				local entries = { { id = "neutral", package = themes.neutralPackage() } }
				for _, name in SHIPPED do
					table.insert(entries, { id = name, package = (shipped(name)) })
				end
				for _, entry in entries do
					for _, palette in entry.package.style.themes do
						local colors, extra = paletteOf(palette)
						Verify.expect(contrast(colors.content, colors.surface) >= 4.5):toBe(true)
						Verify.expect(contrast(colors.contentStrong, colors.surfaceStrong) >= 4.5):toBe(true)
						Verify.expect(contrast(colors.onAccent, colors.accent) >= 4.5):toBe(true)
						Verify.expect(contrast(colors.accent, colors.surface) >= 3):toBe(true)
						local sheet, stop = sheetFor(h, entry.package, { theme = palette.name })
						Verify.expect(style(sheet, ".facet-selection-indicator").BackgroundColor3)
							:toBe(color(h.engine, colors.accent))
						Verify.expect(style(sheet, ".facet-surface").BackgroundColor3)
							:toBe(color(h.engine, colors.surface))
						Verify.expect(style(sheet, ".facet-text").TextColor3):toBe(color(h.engine, colors.content))
						Verify.expect(style(sheet, ".facet-accent").TextColor3):toBe(color(h.engine, colors.onAccent))
						Verify.expect(style(sheet, ".facet-selected").BackgroundColor3)
							:toBe(color(h.engine, extra.controlSelected))
						stop()
					end
				end
				local weak = themes.neutralPackage()
				weak.style.themes[1].colors.accent = { r = 0.1, g = 0.1, b = 0.13 }
				Verify.expect(contrast(weak.style.themes[1].colors.accent, weak.style.themes[1].colors.surface) < 3)
					:toBe(true)
				h.dispose()
			end,
		})

		verifyHarness:case("shows an off switch's knob against its track in every shipped package and palette", {
			id = "native_parity_strength_paint::native paint strength: theme sheets::shows an off switch's knob against its track in every shipped package and palette",
			run = function()
				local h = harness()
				local on = Compose.cell(false)
				local root, stop = mount(h, function()
					return h.UI.Toggle({ Name = "Url", label = "URL bar", value = on })
				end)
				local indicator = find(root, "Indicator")
				local knob = find(indicator, "Mark")
				local entries = { { id = "neutral", package = themes.neutralPackage() } }
				for _, name in SHIPPED do
					table.insert(entries, { id = name, package = (shipped(name)) })
				end
				local weak = {}
				for _, entry in entries do
					for _, palette in entry.package.style.themes do
						local colors, extra = paletteOf(palette)
						local sheet, stopSheet = sheetFor(h, entry.package, { theme = palette.name })
						on:set(false)
						local ink = resolve(sheet, knob, "BackgroundColor3")
						local track = resolve(sheet, indicator, "BackgroundColor3")
						local measured = contrast(
							{ r = ink.R, g = ink.G, b = ink.B },
							{ r = track.R, g = track.G, b = track.B }
						)
						local art = assert(entry.package.chrome).toggleKnob
						if measured < 3 and (art == nil or art.kind == "native" or art.kind == "none") then
							table.insert(weak, `{entry.id}/{palette.name}`)
						end
						on:set(true)
						local selection = extra.onSelection or colors.onAccent
						Verify.expect((resolve(sheet, knob, "BackgroundColor3"))):toBe(color(h.engine, selection))
						stopSheet()
					end
				end
				Verify.expect((table.concat(weak, " "))):toBe("")
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case(
			"paints every text field placeholder with contentSecondary, and field text and placeholder clear 4.5:1 on the tinted field art",
			{
				id = "native_parity_strength_paint::native paint strength: theme sheets::paints every text field placeholder with contentSecondary, and field text and placeholder clear 4.5:1 on the tinted field art",
				run = function()
					local samples = serde.decode("json", fs.readFile("assets/themes/plate-samples.json")).samples
					local h = harness()
					local root, stopProbes = mount(h, function()
						return h.Host.Frame({
							h.UI.TextInput "Plain" { value = Compose.cell(""), placeholder = "Search" } :: unknown,
							h.UI.TextInput "Framed" { value = Compose.cell(""), placeholder = "Name", label = "Name" },
						})
					end)
					local boxes = {}
					for _, node in root:GetDescendants() do
						if node.ClassName == "TextBox" then
							table.insert(boxes, node)
						end
					end
					Verify.expect(#boxes):toBe(2)
					local entries = { { id = "neutral", package = themes.neutralPackage() } }
					for _, name in SHIPPED do
						table.insert(entries, { id = name, package = (shipped(name)) })
					end
					local sampled, unreadable = 0, {}
					for _, entry in entries do
						local art = (samples[(string.gsub(entry.id, "_", "-"))] or {}).field
						for _, palette in entry.package.style.themes do
							local colors, extra = paletteOf(palette)
							local secondary = extra.contentSecondary or colors.contentSecondary
							local tint = extra.artTint or { r = 1, g = 1, b = 1 }
							local plate = if art
								then { r = art.r / 255 * tint.r, g = art.g / 255 * tint.g, b = art.b / 255 * tint.b }
								else extra.control
							if art then
								sampled += 1
							end
							local sheet, stop = sheetFor(h, entry.package, { theme = palette.name })
							for _, box in boxes do
								Verify.expect((resolve(sheet, box, "PlaceholderColor3")))
									:toBe(color(h.engine, secondary))
							end
							if art and (contrast(secondary, plate) < 4.5 or contrast(colors.content, plate) < 4.5) then
								table.insert(unreadable, `{entry.id}/{palette.name}`)
							end
							stop()
						end
					end
					Verify.expect(sampled):toBe(7)
					Verify.expect((table.concat(unreadable, " "))):toBe("")
					stopProbes()
					h.dispose()
				end,
			}
		)

		verifyHarness:case("paints a table row from the theme row role and every delete control in the danger role", {
			id = "native_parity_strength_paint::native paint strength: theme sheets::paints a table row from the theme row role and every delete control in the danger role",
			run = function()
				local h = harness()
				local root, stop = mount(h, function()
					return h.UI.Table({
						from = { { id = "a", name = "Neon" } },
						key = "id",
						editing = Compose.cell(true),
						reorderable = true,
						onReorder = function() end,
						deletable = true,
						onDelete = function() end,
						columns = { { id = "name", label = "Name" } :: FixtureCollectionTypes.TableColumn<any, any> },
						rowActions = function()
							return {
								trailing = {
									{
										id = "remove",
										label = "Remove",
										role = "destructive" :: "destructive",
										onActivate = function() end,
									} :: FixtureCollectionTypes.RowAction,
								},
							}
						end,
					})
				end)
				local body = find(root, "Body")
				body.AbsoluteWindowSize = h.engine.types.Vector2.new(400, 200)
				body.AbsoluteSize = h.engine.types.Vector2.new(400, 200)
				local band = find(root, "Reorderable")
				local inner = find(root, "DisclosingRow")
				local minus, confirm = find(root, "Minus"), find(root, "Delete")
				local function underSwipe(node: any): boolean
					local cursor = node.Parent
					while cursor do
						if cursor:HasTag("facet-rowactions") then
							return true
						end
						cursor = cursor.Parent
					end
					return false
				end
				Verify.expect(underSwipe(minus) or underSwipe(confirm) or underSwipe(find(root, "Move"))):toBe(false)
				for _, entry in
					{
						{ id = "neutral", package = themes.neutralPackage() },
						{ id = "classic_desktop", package = (shipped("classic_desktop")) },
					}
				do
					for _, palette in entry.package.style.themes do
						local colors, extra = paletteOf(palette)
						local sheet, stopSheet = sheetFor(h, entry.package, { theme = palette.name })
						local row = extra.tableRow or extra.control
						Verify.expect(`{entry.id}/{palette.name}:{tostring(resolve(sheet, band, "BackgroundColor3"))}`)
							:toBe(`{entry.id}/{palette.name}:{tostring(color(h.engine, row))}`)
						Verify.expect((resolve(sheet, band, "BackgroundTransparency"))):toBe(0)
						Verify.expect(band.BackgroundTransparency):toBe(0)
						Verify.expect(inner.BackgroundTransparency):toBe(1)
						for _, control in { minus, confirm } do
							Verify.expect((control:HasTag("facet-accent"))):toBe(false)
							Verify.expect((resolve(sheet, control, "BackgroundColor3")))
								:toBe(color(h.engine, colors.danger))
						end
						stopSheet()
					end
				end
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case(
			"keeps table row, alternate row, header and selected row text at 4.5:1 in every shipped palette",
			{
				id = "native_parity_strength_paint::native paint strength: theme sheets::keeps table row, alternate row, header and selected row text at 4.5:1 in every shipped palette",
				run = function()
					local weak = {}
					local entries = { { id = "neutral", package = themes.neutralPackage() } }
					for _, name in SHIPPED do
						table.insert(entries, { id = name, package = (shipped(name)) })
					end
					for _, entry in entries do
						for _, palette in entry.package.style.themes do
							local colors, extra = paletteOf(palette)
							local pairs: {
								[string]: { typeof(colors.content) | typeof(extra.tableRow or extra.control) }
									| {
										typeof(colors.content)
										| typeof(extra.tableRowAlternate or extra.controlHover)
									}
									| { typeof(colors.content) | typeof(extra.tableHeader or extra.control) }
									| { typeof(extra.onSelected or colors.content) | typeof(extra.controlSelected) },
							} =
								{
									row = { colors.content, extra.tableRow or extra.control },
									alternate = { colors.content, extra.tableRowAlternate or extra.controlHover },
									header = { colors.content, extra.tableHeader or extra.control },
									selected = { extra.onSelected or colors.content, extra.controlSelected },
								}
							for name, pair in pairs do
								if pair[1] and pair[2] and contrast(pair[1], pair[2]) < 4.5 then
									table.insert(weak, `{entry.id}/{palette.name}:{name}`)
								end
							end
						end
					end
					table.sort(weak)
					Verify.expect((table.concat(weak, " "))):toBe("")
				end,
			}
		)

		verifyHarness:case(
			"pads a skinned control plate by its art carve, so HUD chips keep their content inside the frame",
			{
				id = "native_parity_strength_paint::native paint strength: theme sheets::pads a skinned control plate by its art carve, so HUD chips keep their content inside the frame",
				run = function()
					local h = harness()
					local package = shipped("fantasy_parchment")
					local sheet, stop = sheetFor(h, package)
					local plate = h.engine.new("Frame")
					plate:AddTag("facet-control")
					local padding = h.engine.new("UIPadding")
					padding.Parent = plate
					local carve = package.chrome.control.contentInsets
					Verify.expect((resolve(sheet, padding, "PaddingTop"))):toBe(nil)
					plate:AddTag("facet-skinned")
					Verify.expect((resolve(sheet, padding, "PaddingTop"))):toBe(h.engine.types.UDim.new(0, carve.top))
					Verify.expect((resolve(sheet, padding, "PaddingLeft"))):toBe(h.engine.types.UDim.new(0, carve.left))
					stop()
					h.dispose()
				end,
			}
		)

		verifyHarness:case("an inactive tab on control art reads at 4.5:1 on the art after the palette's artTint", {
			id = "native_parity_strength_paint::native paint strength: theme sheets::an inactive tab on control art reads at 4.5:1 on the art after the palette's artTint",
			run = function()
				local samples = serde.decode("json", fs.readFile("assets/themes/plate-samples.json")).samples
				local h = harness()
				local tab = h.engine.new("TextButton")
				for _, tag in { "facet-button", "facet-tab-item", "facet-skinned" } do
					tab:AddTag(tag)
				end
				local caption = h.engine.new("TextLabel")
				caption:AddTag("facet-text")
				caption:AddTag("facet-button-caption")
				caption.Parent = tab
				local art = h.engine.new("ImageLabel")
				art:AddTag("facet-skin-art")
				art:AddTag("facet-skin-art-control")
				art.Parent = tab
				local checked, unreadable = 0, {}
				for _, name in SHIPPED do
					local package = shipped(name)
					local sample = (samples[(string.gsub(name, "_", "-"))] or {}).control
					if sample then
						for _, palette in package.style.themes do
							local _, extra = paletteOf(palette)
							local sheet, stop = sheetFor(h, package, { theme = palette.name })
							local tint = resolve(sheet, art, "ImageColor3") or h.engine.types.Color3.new(1, 1, 1)
							local ink = resolve(sheet, caption, "TextColor3")
							if extra.artTint then
								Verify.expect(tint):toBe(color(h.engine, extra.artTint))
							end
							local plate = {
								r = sample.r / 255 * tint.R,
								g = sample.g / 255 * tint.G,
								b = sample.b / 255 * tint.B,
							}
							checked += 1
							if contrast({ r = ink.R, g = ink.G, b = ink.B }, plate) < 4.5 then
								table.insert(unreadable, `{name}/{palette.name}`)
							end
							stop()
						end
					end
				end
				Verify.expect(checked):toBe(7)
				Verify.expect((table.concat(unreadable, " "))):toBe("")
				h.dispose()
			end,
		})

		verifyHarness:case("never parents field art under a TextBox, where it would cover the text and placeholder", {
			id = "native_parity_strength_paint::native paint strength: theme sheets::never parents field art under a TextBox, where it would cover the text and placeholder",
			run = function()
				local covered = {}
				for _, name in SHIPPED do
					local h = harness({ theme = (shipped(name)) })
					local root, stop = mount(h, function()
						return h.Host.Frame({
							h.UI.TextInput "Plain" { value = Compose.cell(""), placeholder = "Name" } :: unknown,
							h.UI.TextInput "Search" {
								value = Compose.cell(""),
								presentation = "search" :: "search",
								placeholder = "Filter",
							},
							h.UI.TextInput "Framed" { value = Compose.cell(""), placeholder = "Name", label = "Name" },
						})
					end)
					local plates = 0
					for _, node in root:GetDescendants() do
						if node:HasTag("facet-skin-art") then
							plates += 1
							local parent = node.Parent
							while parent and parent ~= root do
								if parent.ClassName == "TextBox" then
									table.insert(covered, `{name}/{parent.Name}`)
								end
								parent = parent.Parent
							end
						end
					end
					Verify.expect(
						plates > 0 or name == "classic_desktop" or name == "glossy_mobile" or name == "scifi_hud"
					)
						:toBe(true)
					stop()
					h.dispose()
				end
				Verify.expect((table.concat(covered, " "))):toBe("")
			end,
		})

		verifyHarness:case("composes the sheet scrim and the full-screen backdrop from the same clamped preference", {
			id = "native_parity_strength_paint::native paint strength: theme sheets::composes the sheet scrim and the full-screen backdrop from the same clamped preference",
			run = function()
				local h = harness({ motionLevel = "none" })
				local preference = Compose.cell(1 :: any)
				local sheet, stopSheet = sheetFor(h, themes.neutralPackage(), { preferredTransparency = preference })
				local base = 1 - 0.45
				local source
				local root, stop = mount(h, function()
					source = h.Host.Frame({ Name = "Source" })
					return h.Host.Frame({
						source :: unknown,
						h.UI.Alert({
							isPresented = Compose.cell(true),
							title = "Map",
							surface = "fullScreen",
							transition = { source = source },
							actions = {
								{ id = "close", label = "Close", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
							},
						}),
					})
				end)
				local backdrop = find(root.Parent, "DismissOutside")
				Verify.expect((backdrop:HasTag("facet-scrim"))):toBe(true)
				local backdropBase = backdrop.BackgroundTransparency
				Verify.expect(backdropBase):toBeCloseTo(0.35, 1e-4)
				local expected = { [1] = 1, [0.5] = 0.5, [0.25] = 0.25, [0] = 0, [-1] = 0, [2] = 1 }
				local inputs: { any } = { 1, 0.5, 0.25, 0, -1, 2, 0 / 0, "opaque" }
				for _, value in inputs do
					preference:set(value)
					h.gui.PreferredTransparency = value
					local clamped = if type(value) == "number" and value == value then expected[value] else 1
					local fromSheet = style(sheet, ".facet-scrim").BackgroundTransparency
					local fromBackdrop = backdrop.BackgroundTransparency
					Verify.expect(fromSheet):toBeCloseTo(if clamped >= 1 then base else base * clamped, 1e-4)
					Verify.expect(fromBackdrop):toBeCloseTo(backdropBase * clamped, 1e-4)
					Verify.expect(fromSheet / base):toBeCloseTo(fromBackdrop / backdropBase, 1e-4)
				end
				stop()
				stopSheet()
				h.dispose()
			end,
		})
	end)

	verifyHarness:suite("native paint strength: value and status paint", function()
		verifyHarness:case("sizes ring strokes, bar tracks and spinner dots from theme metrics unless authored", {
			id = "native_parity_strength_paint::native paint strength: value and status paint::sizes ring strokes, bar tracks and spinner dots from theme metrics unless authored",
			run = function()
				local colors, extra = neutralColors()
				local package = Compose.cell(themes.neutralPackage())
				local h = harness({ theme = package })
				local sheet, stopSheet = sheetFor(h, themes.neutralPackage())
				local diameter = Compose.cell(32)
				local root, stop = mount(h, function()
					return h.Host.Frame({
						h.UI.ProgressView({
							Name = "Ring",
							presentation = "circular" :: "circular",
							value = 0.5,
							diameter = diameter,
						}) :: unknown,
						h.UI.ProgressView({
							Name = "Authored",
							presentation = "circular" :: "circular",
							value = 0.5,
							thickness = 5,
						}),
						h.UI.ProgressView({ Name = "Bar", value = 0.5 }),
						h.UI.ProgressView({ Name = "Thin", value = 0.5, thickness = 4 }),
						h.UI.ProgressView({ Name = "Spinner", presentation = "spinner" :: "spinner" }),
					})
				end)
				local ring = find(root, "Ring")
				local fill, track = find(ring, "RingFill"), find(ring, "RingTrack")
				for _, case in { { 32, 3 }, { 20, 3 }, { 100, 8 }, { 64, 5 } } do
					diameter:set(case[1])
					Verify.expect(fill.Thickness):toBe(case[2])
					Verify.expect(track.Thickness):toBe(case[2])
				end
				local authored = find(find(root, "Authored"), "RingFill")
				Verify.expect(authored.Thickness):toBe(5)
				Verify.expect(find(find(root, "Bar"), "Track").Size):toBe(h.engine.types.UDim2.new(1, 0, 0, 6))
				Verify.expect(find(find(root, "Thin"), "Track").Size):toBe(h.engine.types.UDim2.new(1, 0, 0, 4))
				Verify.expect(find(find(root, "Spinner"), "Segment1").Size):toBe(h.engine.types.UDim2.fromOffset(4, 4))
				local retuned = themes.neutralPackage()
				retuned.metrics.controls.progress =
					{ trackHeight = 10, circularSize = 32, circularThickness = 7, spinnerDotSize = 6 }
				package:set(retuned)
				Verify.expect(fill.Thickness):toBe(7)
				Verify.expect(track.Thickness):toBe(7)
				diameter:set(100)
				Verify.expect(fill.Thickness):toBe(8)
				Verify.expect(authored.Thickness):toBe(5)
				Verify.expect(find(find(root, "Bar"), "Track").Size):toBe(h.engine.types.UDim2.new(1, 0, 0, 10))
				Verify.expect(find(find(root, "Thin"), "Track").Size):toBe(h.engine.types.UDim2.new(1, 0, 0, 4))
				Verify.expect(find(find(root, "Spinner"), "Segment1").Size):toBe(h.engine.types.UDim2.fromOffset(6, 6))
				Verify.expect((resolve(sheet, fill, "Color3"))):toBe(color(h.engine, colors.accent))
				Verify.expect((resolve(sheet, track, "Color3"))):toBe(color(h.engine, extra.control))
				stop()
				stopSheet()
				h.dispose()
			end,
		})

		verifyHarness:case("paints each level half with its own tint and returns an omitted half to the theme", {
			id = "native_parity_strength_paint::native paint strength: value and status paint::paints each level half with its own tint and returns an omitted half to the theme",
			run = function()
				local h = harness()
				local colors, extra = neutralColors()
				local sheet, stopSheet = sheetFor(h, themes.neutralPackage())
				local Color3 = h.engine.types.Color3
				local red, green, blue = Color3.new(1, 0, 0), Color3.new(0, 1, 0), Color3.new(0, 0, 1)
				local bars, glyphs, images, plain = Compose.cell(3), Compose.cell(2), Compose.cell(1), Compose.cell(2)
				local filledTint = Compose.cell(red)
				local root, stop = mount(h, function()
					return h.Host.Frame({
						h.UI.LevelPicker({
							Name = "Bars",
							value = bars,
							count = 10,
							tint = { filled = filledTint, empty = green },
						}) :: unknown,
						h.UI.LevelPicker({
							Name = "Glyphs",
							value = glyphs,
							count = 3,
							segment = "glyph",
							tint = { filled = red },
						}),
						h.UI.LevelPicker({
							Name = "Images",
							value = images,
							count = 3,
							segment = "image",
							images = { filled = "rbxassetid://1", empty = "rbxassetid://2" },
							tint = { empty = green },
						}),
						h.UI.LevelPicker({ Name = "Plain", value = plain, count = 4 }),
					})
				end)
				local function mark(name: string, index: number): any
					return find(find(root, name), "Level" .. index)
				end
				for index = 1, 10 do
					Verify.expect(mark("Bars", index).BackgroundColor3):toBe(if index <= 3 then red else green)
				end
				bars:set(7)
				Verify.expect(mark("Bars", 7).BackgroundColor3):toBe(red)
				Verify.expect(mark("Bars", 8).BackgroundColor3):toBe(green)
				filledTint:set(blue)
				Verify.expect(mark("Bars", 1).BackgroundColor3):toBe(blue)
				Verify.expect(mark("Bars", 8).BackgroundColor3):toBe(green)
				local untouched = h.engine.new("TextLabel").TextColor3
				Verify.expect(mark("Glyphs", 1).TextColor3):toBe(red)
				Verify.expect(mark("Glyphs", 3).TextColor3):toBe(untouched)
				Verify.expect((resolve(sheet, mark("Glyphs", 3), "TextColor3"))):toBe(color(h.engine, colors.content))
				glyphs:set(1)
				Verify.expect(mark("Glyphs", 2).TextColor3):toBe(untouched)
				Verify.expect(mark("Glyphs", 1).TextColor3):toBe(red)
				glyphs:set(3)
				Verify.expect(mark("Glyphs", 3).TextColor3):toBe(red)
				local defaultImage = h.engine.new("ImageLabel").ImageColor3
				Verify.expect(mark("Images", 1).ImageColor3):toBe(defaultImage)
				Verify.expect(mark("Images", 2).ImageColor3):toBe(green)
				images:set(3)
				Verify.expect(mark("Images", 2).ImageColor3):toBe(defaultImage)
				Verify.expect(mark("Images", 2).Image):toBe("rbxassetid://1")
				local filled, empty = mark("Plain", 1), mark("Plain", 4)
				Verify.expect((resolve(sheet, filled, "BackgroundColor3"))):toBe(color(h.engine, colors.accent))
				Verify.expect((resolve(sheet, empty, "BackgroundColor3"))):toBe(color(h.engine, extra.control))
				Verify.expect(resolve(sheet, filled, "BackgroundColor3") ~= resolve(sheet, empty, "BackgroundColor3"))
					:toBe(true)
				plain:set(4)
				Verify.expect((resolve(sheet, empty, "BackgroundColor3"))):toBe(color(h.engine, colors.accent))
				stop()
				stopSheet()
				h.dispose()
			end,
		})

		verifyHarness:case("paints an unstatused badge as a control plate with content text and no focus stop", {
			id = "native_parity_strength_paint::native paint strength: value and status paint::paints an unstatused badge as a control plate with content text and no focus stop",
			run = function()
				local h = harness()
				local root, stop = mount(h, function()
					return h.Host.Frame({
						h.UI.Badge({ Name = "Plain", label = "New" }) :: unknown,
						h.UI.Badge({ Name = "Iconic", label = "New", icon = "checkmark" }),
						h.UI.Badge({ Name = "Neutral", label = "New", status = Compose.cell("neutral") }),
					})
				end)
				local packages = { themes.neutralPackage() }
				for _, name in SHIPPED do
					table.insert(packages, (shipped(name)))
				end
				for _, package in packages do
					for _, palette in package.style.themes do
						local colors, extra = paletteOf(palette)
						local sheet, stopSheet = sheetFor(h, package, { theme = palette.name })
						for _, name in { "Plain", "Iconic" } do
							local pill = find(root, name)
							for _, tag in pill:GetTags() do
								Verify.expect(string.sub(tag, 1, 13) == "facet-status-"):toBe(false)
							end
							Verify.expect((resolve(sheet, pill, "BackgroundColor3")))
								:toBe(color(h.engine, extra.control))
							Verify.expect((resolve(sheet, pill, "BackgroundTransparency"))):toBe(0)
							Verify.expect((resolve(sheet, pill, "CornerRadius", "UICorner")))
								:toBe(h.engine.types.UDim.new(0, package.metrics.radii.control))
							Verify.expect(resolve(sheet, pill, "PaddingLeft", "UIPadding").Offset >= 8):toBe(true)
							Verify.expect(resolve(sheet, pill, "PaddingTop", "UIPadding").Offset >= 3):toBe(true)
							local text = if pill:IsA("TextLabel") then pill else find(pill, "Label")
							Verify.expect((resolve(sheet, text, "TextColor3"))):toBe(color(h.engine, colors.content))
						end
						local icon = find(root, "Iconic"):FindFirstChildWhichIsA("ImageLabel")
						Verify.expect((resolve(sheet, icon, "ImageColor3"))):toBe(color(h.engine, colors.content))
						local neutral = find(root, "Neutral")
						Verify.expect((resolve(sheet, neutral, "BackgroundColor3")))
							:toBe(color(h.engine, extra.contentSecondary))
						Verify.expect((resolve(sheet, neutral, "TextColor3"))):toBe(color(h.engine, colors.surface))
						stopSheet()
					end
				end
				for _, name in { "Plain", "Iconic", "Neutral" } do
					local pill = find(root, name)
					for _, node in { pill, table.unpack(pill:GetDescendants()) } do
						if node:IsA("GuiObject") then
							Verify.expect(node.Selectable):toBe(false)
						end
					end
				end
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("paints every status with its shared palette pair and caps the count at the authored max", {
			id = "native_parity_strength_paint::native paint strength: value and status paint::paints every status with its shared palette pair and caps the count at the authored max",
			run = function()
				local h = harness()
				local pairs: { [string]: { string } } = {
					neutral = { "contentSecondary", "surface" },
					info = { "accent", "onAccent" },
					success = { "success", "onSuccess" },
					warning = { "warning", "onWarning" },
					error = { "danger", "onDanger" },
					accent = { "accent", "onAccent" },
				}
				local count, capped = Compose.cell(0), Compose.cell(0)
				local status = Compose.cell("neutral")
				local root, stop = mount(h, function()
					return h.Host.Frame({
						h.UI.StatusIndicator({ Name = "Count", status = status, count = count }) :: unknown,
						h.UI.StatusIndicator({ Name = "Capped", status = status, count = capped, max = 9 }),
						h.UI.StatusIndicator({ Name = "Ring", status = status, form = "ring", diameter = 16 }),
					})
				end)
				local node, cappedNode = find(root, "Count"), find(root, "Capped")
				local ring = find(root, "Ring"):FindFirstChildWhichIsA("UIStroke")
				Verify.expect(node:FindFirstChildWhichIsA("UISizeConstraint").MinSize)
					:toBe(h.engine.types.Vector2.new(24, 24))
				for _, entry in
					{
						{ value = 0, label = "0" },
						{ value = 9, label = "9" },
						{ value = 99, label = "99" },
						{ value = 100, label = "99+" },
						{ value = 1000, label = "99+" },
					}
				do
					count:set(entry.value)
					Verify.expect(node.Text):toBe(entry.label)
				end
				for _, entry in
					{
						{ value = 0, label = "0" },
						{ value = 9, label = "9" },
						{ value = 10, label = "9+" },
						{ value = 1000, label = "9+" },
					}
				do
					capped:set(entry.value)
					Verify.expect(cappedNode.Text):toBe(entry.label)
				end
				local packages = { themes.neutralPackage() }
				for _, name in SHIPPED do
					table.insert(packages, (shipped(name)))
				end
				for _, package in packages do
					for _, palette in package.style.themes do
						local colors, extra = paletteOf(palette)
						local sheet, stopSheet = sheetFor(h, package, { theme = palette.name })
						for name, pair in pairs do
							status:set(name)
							local fill = colors[pair[1]] or extra[pair[1]]
							local partner = colors[pair[2]] or extra[pair[2]]
							for _, indicator in { node, cappedNode } do
								Verify.expect((resolve(sheet, indicator, "BackgroundColor3")))
									:toBe(color(h.engine, fill))
								Verify.expect((resolve(sheet, indicator, "TextColor3"))):toBe(color(h.engine, partner))
								Verify.expect((resolve(sheet, indicator, "BackgroundTransparency"))):toBe(0)
							end
							Verify.expect((resolve(sheet, ring, "Color"))):toBe(color(h.engine, fill))
							Verify.expect((resolve(sheet, find(root, "Ring"), "BackgroundTransparency"))):toBe(1)
						end
						stopSheet()
					end
				end
				Verify.expect(function()
					mount(h, function()
						return h.UI.StatusIndicator({ count = 3, max = 1.5 })
					end)
				end):toThrow()
				stop()
				h.dispose()
			end,
		})
	end)

	verifyHarness:suite("native paint strength: split button", function()
		local function split(h: Harness): (any, () -> ())
			return mount(h, function()
				return h.Host.Frame({
					h.UI.Button({ Name = "Plain", label = "Plain" }) :: unknown,
					h.UI.SplitButton "Split" {
						label = "Start race",
						onActivate = function() end,
						items = {
							{ id = "practice", label = "Practice", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
						},
					},
				})
			end)
		end

		verifyHarness:case("joins the primary and an icon-only menu segment on one plate", {
			id = "native_parity_strength_paint::native paint strength: split button::joins the primary and an icon-only menu segment on one plate",
			run = function()
				local package = themes.neutralPackage()
				local h = harness({ theme = package })
				local root, stop = split(h)
				local sheet, stopSheet = sheetFor(h, package)
				local primary, segment = find(root, "Primary"), find(root, "Alternatives")
				local plate = primary.Parent
				Verify.expect(segment.Parent):toBe(plate)
				Verify.expect(plate:FindFirstChildWhichIsA("UIListLayout").Padding.Offset):toBe(0)
				local divider = find(plate, "Divider")
				Verify.expect(primary.LayoutOrder < divider.LayoutOrder and divider.LayoutOrder < segment.LayoutOrder)
					:toBe(true)
				Verify.expect(divider.Size.Y.Scale):toBe(0)
				Verify.expect(divider:FindFirstChildWhichIsA("UIFlexItem").ItemLineAlignment.Name):toBe("Stretch")
				Verify.expect((resolve(sheet, plate, "BackgroundTransparency"))):toBe(0)
				Verify.expect((resolve(sheet, plate, "CornerRadius", "UICorner")))
					:toBe(resolve(sheet, find(root, "Plain"), "CornerRadius", "UICorner"))
				Verify.expect((resolve(sheet, primary, "BackgroundTransparency"))):toBe(1)
				Verify.expect((resolve(sheet, segment, "BackgroundTransparency"))):toBe(1)
				Verify.expect(segment.Text):toBe("")
				Verify.expect((find(segment, "Title"))):toBe(nil)
				Verify.expect(find(segment, "LeadingIcon") ~= nil):toBe(true)
				Verify.expect((segment:GetAttribute("label"))):toBe("More options")
				Verify.expect(primary.Size.Y.Offset):toBe(find(root, "Plain").Size.Y.Offset)
				Verify.expect(segment.Size.Y.Offset):toBe(primary.Size.Y.Offset)
				Verify.expect(primary.Size.Y.Offset >= 44):toBe(true)
				Verify.expect((segment:FindFirstChildWhichIsA("UISizeConstraint"))):toBe(nil)
				Verify.expect(primary.Selectable ~= false and segment.Selectable ~= false):toBe(true)
				segment.Activated:Fire()
				Verify.expect(find(root.Parent or root, "MenuPanel") ~= nil):toBe(true)
				stopSheet()
				stop()
				h.dispose()
			end,
		})

		verifyHarness:case("paints skinned plate art across the whole split, not per segment", {
			id = "native_parity_strength_paint::native paint strength: split button::paints skinned plate art across the whole split, not per segment",
			run = function()
				local package = skinPackage({ control = "rbxassetid://123" })
				local h = harness({ theme = package })
				local root, stop = split(h)
				local primary = find(root, "Primary")
				Verify.expect((ownSlots(primary.Parent))):toEqual({ "control" })
				Verify.expect((ownSlots(primary))):toEqual({})
				Verify.expect((ownSlots(find(root, "Alternatives")))):toEqual({})
				stop()
				h.dispose()
			end,
		})
	end)

	verifyHarness:suite("native paint strength: media button", function()
		verifyHarness:case("hugs an image button to its media and captions with the media flush to the plate top", {
			id = "native_parity_strength_paint::native paint strength: media button::hugs an image button to its media and captions with the media flush to the plate top",
			run = function()
				local h = harness()
				local sheet, stopSheet = sheetFor(h, themes.neutralPackage())
				local root, stop = mount(h, function()
					return h.UI.Button "Card" { label = "Button", subtitle = "12 playing", image = "rbxassetid://1" }
				end)
				local E = h.engine.types.Enum
				local plate = find(root, "Card")
				Verify.expect(plate.AutomaticSize):toBe(E.AutomaticSize.Y)
				Verify.expect(plate.Size.Y.Scale + plate.Size.Y.Offset):toBe(0)
				local content = find(plate, "Content")
				Verify.expect(content.AutomaticSize):toBe(E.AutomaticSize.Y)
				Verify.expect(content.Size.Y.Scale):toBe(0)
				for _, side in { "Top", "Left", "Right" } do
					Verify.expect(resolve(sheet, plate, "Padding" .. side, "UIPadding").Offset):toBe(0)
				end
				Verify.expect(resolve(sheet, plate, "PaddingBottom", "UIPadding").Offset):toBe(10)
				local media = find(plate, "Media")
				Verify.expect(media.Parent):toBe(content)
				Verify.expect(media.LayoutOrder < find(plate, "Captions").LayoutOrder):toBe(true)
				Verify.expect(media.Size.X.Scale):toBe(1)
				Verify.expect(media.ClipsDescendants):toBe(true)
				local aspect = media:FindFirstChildWhichIsA("UIAspectRatioConstraint")
				Verify.expect(aspect.AspectRatio):toBe(16 / 9)
				Verify.expect(aspect.DominantAxis):toBe(E.DominantAxis.Width)
				local radius = resolve(sheet, plate, "CornerRadius", "UICorner").Offset
				Verify.expect(radius > 0):toBe(true)
				local image = find(media, "Image")
				Verify.expect(image:FindFirstChildWhichIsA("UICorner").CornerRadius.Offset):toBe(radius)
				Verify.expect(image.Size.Y.Scale):toBe(1)
				Verify.expect(image.Size.Y.Offset):toBe(radius)
				local captions = find(plate, "Captions")
				Verify.expect(resolve(sheet, captions, "PaddingLeft", "UIPadding").Offset):toBe(12)
				Verify.expect(resolve(sheet, captions, "PaddingRight", "UIPadding").Offset):toBe(12)
				stop()
				stopSheet()
				h.dispose()
			end,
		})
	end)

	verifyHarness:suite("native paint strength: pixel quest selected plate", function()
		verifyHarness:case("paints every selected Pixel Quest plate as the wood frame turned over and tinted green", {
			id = "native_parity_strength_paint::native paint strength: pixel quest selected plate::paints every selected Pixel Quest plate as the wood frame turned over and tinted green",
			run = function()
				local package = shipped("pixel_quest")
				local plate = package.assets.pixel_plate_default
				local link = package.chrome.control.asset.selected
				Verify.expect(link.asset):toBe("pixel_plate_default")
				Verify.expect(link.rotation):toBe(180)
				Verify.expect(plate.sliceCenter.x0 + plate.sliceCenter.x1):toBe(36)
				Verify.expect(plate.sliceCenter.y0 + plate.sliceCenter.y1):toBe(36)
				local h = harness({ theme = package })
				local sheet, stopSheet = sheetFor(h, package)
				local green = color(h.engine, link.tint)
				local _, extra = paletteOf(package.style.themes[1])
				local ink = color(h.engine, extra.onSelected)
				local root, stop = mount(h, function()
					return h.Host.Frame({
						h.UI.Picker({
							style = "segmented" :: "segmented",
							selected = Compose.cell("a"),
							options = {
								{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "B" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						}) :: unknown,
						h.UI.Picker({
							style = "inline" :: "inline",
							selected = Compose.cell("a"),
							options = {
								{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "B" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						}),
						h.UI.Chip({ Name = "Chip", label = "Rain", selected = Compose.cell(true) }),
						h.UI.Toggle({
							Name = "Toggle",
							label = "On",
							presentation = "button" :: "button",
							value = Compose.cell(true),
						}),
						h.UI.Button({ Name = "Row", label = "Row", selected = true }),
					})
				end)
				local chosen = tagged(root, "facet-selected")
				Verify.expect(#chosen >= 5):toBe(true)
				for _, node in chosen do
					local art = ownArt(node, "control")
					Verify.expect(art.Image):toBe(plate.content)
					for _, state in { "Idle", "Hover" } do
						setState(h, node, state)
						Verify.expect(art.Rotation):toBe(180)
						Verify.expect(art.ImageColor3):toBe(green)
					end
					setState(h, node, "Idle")
					Verify.expect(resolve(sheet, art.Parent.Parent, "Visible") ~= false):toBe(true)
					Verify.expect((resolve(sheet, node, "BackgroundTransparency"))):toBe(1)
					Verify.expect((resolve(sheet, node, "TextColor3"))):toBe(ink)
					for _, caption in tagged(node, "facet-button-caption") do
						Verify.expect((resolve(sheet, caption, "TextColor3"))):toBe(ink)
					end
				end
				for _, node in tagged(root, "facet-segment") do
					if not node:HasTag("facet-selected") then
						Verify.expect(ownArt(node, "control").Rotation):toBe(0)
					end
				end
				stop()
				stopSheet()
				h.dispose()
			end,
		})

		verifyHarness:case("rejects a state link that turns a plate a quarter or tints outside zero to one", {
			id = "native_parity_strength_paint::native paint strength: pixel quest selected plate::rejects a state link that turns a plate a quarter or tints outside zero to one",
			run = function()
				local function withLink(selected: any): boolean
					local definition: any =
						{ identity = { id = "x" }, assets = { art = { content = "rbxassetid://1" } } }
					definition.chrome = {
						control = {
							kind = "nineSlice" :: "nineSlice",
							asset = { default = "art", selected = selected },
						},
					}
					local package = themes.define(definition)
					return package ~= nil
				end
				Verify.expect((withLink({ asset = "art", rotation = 180, tint = { r = 0.5, g = 1, b = 0.5 } })))
					:toBe(true)
				Verify.expect((withLink({ asset = "art", rotation = 90 }))):toBe(false)
				Verify.expect((withLink({ asset = "art", tint = { r = 2, g = 1, b = 1 } }))):toBe(false)
				Verify.expect((withLink({ asset = "art", tint = "green" }))):toBe(false)
			end,
		})

		verifyHarness:case(
			"paints every selected plate in every skinned package with its selected art at its sibling's size",
			{
				id = "native_parity_strength_paint::native paint strength: pixel quest selected plate::paints every selected plate in every skinned package with its selected art at its sibling's size",
				run = function()
					local function selectedLink(package: any): any
						local control = package.chrome.control
						local layers = if control.kind == "layered" then control.layers else { control }
						for _, layer in layers do
							local link = if type(layer.asset) == "table" then layer.asset.selected else nil
							if link ~= nil then
								return if type(link) == "string" then { asset = link } else link
							end
						end
						return nil
					end
					local covered = {}
					for _, name in
						{ "compact_pointer", "fantasy_ornate", "fantasy_parchment", "glossy_touch", "pixel_quest" }
					do
						local package = shipped(name)
						local link = selectedLink(package)
						Verify.expect(link ~= nil):toBe(true)
						if link then
							local asset = package.assets[link.asset]
							local h = harness({ theme = package })
							local sheet, stopSheet = sheetFor(h, package)
							local tint = color(h.engine, link.tint or { r = 1, g = 1, b = 1 })
							local function picker(style: string, extra: { [string]: any }?): any
								local props: { [string]: any } = {
									Name = style .. ((extra or ({} :: { [string]: any })).axis or ""),
									style = style,
									selected = Compose.cell("a"),
									options = { { value = "a", label = "Rally" }, { value = "b", label = "Road" } },
								}
								for key, value in extra or ({} :: { [string]: any }) do
									props[key] = value
								end
								return h.UI.Picker(props)
							end
							local function row(label: string, on: boolean): any
								local node = h.UI.Button({ Name = label, label = label, selected = on })
								node:AddTag("facet-menu-item")
								return node
							end
							local root, stop = mount(h, function()
								return h.Host.Frame({
									picker("segmented") :: unknown,
									picker("inline"),
									picker("radioGroup"),
									picker("cards"),
									picker("cards", { axis = "x" :: "x" }),
									h.UI.Chip({ Name = "ChipOn", label = "Rain", selected = Compose.cell(true) }),
									h.UI.Chip({ Name = "ChipOff", label = "Snow", selected = Compose.cell(false) }),
									h.UI.Toggle({
										Name = "ToggleOn",
										label = "On",
										presentation = "button" :: "button",
										value = Compose.cell(true),
									}),
									h.UI.Toggle({
										Name = "ToggleOff",
										label = "Off",
										presentation = "button" :: "button",
										value = Compose.cell(false),
									}),
									row("RowOn", true),
									row("RowOff", false),
								})
							end)
							local pairs = {
								{ find(root, "segmented"), "a", "b" },
								{ find(root, "inline"), "a", "b" },
								{ find(root, "radioGroup"), "a", "b" },
								{ find(root, "cards"), "Card-a", "Card-b" },
								{ find(root, "cardsx"), "Card-a", "Card-b" },
								{ root, "ChipOn", "ChipOff" },
								{ root, "ToggleOn", "ToggleOff" },
								{ root, "RowOn", "RowOff" },
							}
							for _, entry in pairs do
								local on, off = find(entry[1], entry[2]), find(entry[1], entry[3])
								if not on:HasTag("facet-selected") then
									on = find(on, "Toggle") or on
								end
								local label = `{name}/{entry[1].Name}/{entry[2]}`
								Verify.expect(label .. ":" .. tostring(on:HasTag("facet-selected")))
									:toBe(label .. ":true")
								Verify.expect((off:HasTag("facet-selected"))):toBe(false)
								local art = ownArt(on, "control")
								Verify.expect(art ~= nil):toBe(true)
								Verify.expect(art.Image):toBe(asset.content or asset.contentId)
								Verify.expect(art.Rotation):toBe(link.rotation or 0)
								Verify.expect(resolve(sheet, art, "ImageColor3") or art.ImageColor3):toBe(tint)
								Verify.expect(
									label .. ":" .. tostring(resolve(sheet, art.Parent.Parent, "Visible") ~= false)
								)
									:toBe(label .. ":true")
								Verify.expect(label .. ":" .. tostring(resolve(sheet, on, "BackgroundTransparency")))
									:toBe(label .. ":" .. tostring(resolve(sheet, off, "BackgroundTransparency")))
								Verify.expect(on.Size):toBe(off.Size)
								Verify.expect(on.AutomaticSize):toBe(off.AutomaticSize)
								for _, property in { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" } do
									Verify.expect((resolve(sheet, on, property, "UIPadding")))
										:toBe(resolve(sheet, off, property, "UIPadding"))
								end
								Verify.expect((resolve(sheet, on, "Thickness", "UIStroke")))
									:toBe(resolve(sheet, off, "Thickness", "UIStroke"))
								table.insert(covered, label)
							end
							stop()
							stopSheet()
							h.dispose()
						end
					end
					Verify.expect(#covered):toBe(40)
				end,
			}
		)
	end)

	verifyHarness:suite("native paint strength: table rows", function()
		verifyHarness:case("an alternate row resolves to tableRowAlternate in every shipped package and palette", {
			id = "native_parity_strength_paint::native paint strength: table rows::an alternate row resolves to tableRowAlternate in every shipped package and palette",
			run = function()
				local h = harness()
				local root, stopTable = mount(h, function()
					return h.UI.Table({
						from = { { id = "a" }, { id = "b" } },
						key = "id",
						scrolls = false,
						alternatingRows = true,
						columns = { { id = "id" } :: FixtureCollectionTypes.TableColumn<any, any> },
					})
				end)
				local alternate = tagged(root, "facet-tablerow-alternate")[1]
				local plain = find(root, "a")
				Verify.expect(alternate ~= nil):toBe(true)
				local packages = { themes.neutralPackage() }
				for _, name in SHIPPED do
					table.insert(packages, (shipped(name)))
				end
				for _, package in packages do
					for _, palette in package.style.themes do
						local sheet, stop = sheetFor(h, package, { theme = palette.name })
						Verify.expect((resolve(sheet, alternate, "BackgroundColor3")))
							:toBe(style(sheet, ".facet-tablerow-alternate").BackgroundColor3)
						Verify.expect((resolve(sheet, tagged(plain, "facet-tablerow")[1], "BackgroundColor3")))
							:toBe(style(sheet, ".facet-tablerow").BackgroundColor3)
						stop()
					end
				end
				stopTable()
				h.dispose()
			end,
		})

		verifyHarness:case("the Edit button reserves the width of both Edit and Done in its own font", {
			id = "native_parity_strength_paint::native paint strength: table rows::the Edit button reserves the width of both Edit and Done in its own font",
			run = function()
				local h = harness({ environment = { preferredInput = "Touch" } })
				local root, stopTable = mount(h, function()
					return h.UI.Table({
						from = { { id = "a" } },
						key = "id",
						scrolls = false,
						deletable = true,
						onDelete = function() end,
						columns = { { id = "id" } :: FixtureCollectionTypes.TableColumn<any, any> },
					})
				end)
				local button = find(root, "Edit")
				local reserve = find(button, "WidthReserve")
				Verify.expect(reserve ~= nil):toBe(true)
				local words = {}
				for _, label in reserve:GetChildren() do
					if label:IsA("TextLabel") then
						Verify.expect(label.TextTransparency):toBe(1)
						Verify.expect(label.Visible):toBe(true)
						table.insert(words, label.Text)
					end
				end
				table.sort(words)
				Verify.expect((table.concat(words, ","))):toBe("Done,Edit")
				stopTable()
				h.dispose()
			end,
		})
	end)

	verifyHarness:suite("native paint strength: calendar day", function()
		verifyHarness:case("a calendar day keeps no button inset in any theme, so its range band meets the next day", {
			id = "native_parity_strength_paint::native paint strength: calendar day::a calendar day keeps no button inset in any theme, so its range band meets the next day",
			run = function()
				local packages = { themes.neutralPackage() }
				for _, name in SHIPPED do
					table.insert(packages, (shipped(name)))
				end
				for _, package in packages do
					local h = harness({ theme = package })
					local range = Compose.cell({
						start = { year = 2026, month = 9, day = 8 },
						finish = { year = 2026, month = 9, day = 17 },
					})
					local root, stop = mount(h, function()
						return h.UI.DateTimePicker("P")({
							selection = "range",
							style = "inline" :: "inline",
							range = range,
							onRangeChange = function(r: any)
								range:set(r)
							end,
						})
					end)
					local sheet, stopSheet = sheetFor(h, package)
					local day = tagged(root, "facet-calendar-day")[10]
					local sides = {}
					for _, side in { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" } do
						local value = resolve(sheet, day, side, "UIPadding")
						table.insert(sides, if value then value.Offset else 0)
					end
					Verify.expect((table.concat(sides, " "))):toBe("0 0 0 0")
					stopSheet()
					stop()
					h.dispose()
				end
			end,
		})

		verifyHarness:case("paints a day number on the range band in onSelected, readable on controlSelected", {
			id = "native_parity_strength_paint::native paint strength: calendar day::paints a day number on the range band in onSelected, readable on controlSelected",
			run = function()
				local checked = 0
				for _, name in SHIPPED do
					local package = shipped(name)
					local h = harness({ theme = package })
					local range = Compose.cell({
						start = { year = 2026, month = 9, day = 8 },
						finish = { year = 2026, month = 9, day = 17 },
					})
					local root, stop = mount(h, function()
						return h.UI.DateTimePicker("P")({
							selection = "range",
							style = "inline" :: "inline",
							range = range,
							onRangeChange = function(r: any)
								range:set(r)
							end,
						})
					end)
					for _, palette in package.style.themes do
						local colors, extra = paletteOf(palette)
						local sheet, stopSheet = sheetFor(h, package, { theme = palette.name })
						local banded = 0
						for _, number in tagged(root, "facet-calendar-number") do
							local band = find(number.Parent, "Band")
							if band and band.Visible and not number:HasTag("facet-calendar-chosen-end") then
								local ink = resolve(sheet, number, "TextColor3")
								Verify.expect(ink):toBe(color(h.engine, extra.onSelected or colors.content))
								local fill = extra.controlSelected
								Verify.expect(contrast({ r = ink.R, g = ink.G, b = ink.B }, fill) >= 4.5):toBe(true)
								banded += 1
							end
						end
						Verify.expect(banded >= 8):toBe(true)
						checked += 1
						stopSheet()
					end
					stop()
					h.dispose()
				end
				Verify.expect(checked >= 8):toBe(true)
			end,
		})
	end)

	verifyHarness:suite("native paint strength: skinned control carve", function()
		verifyHarness:case("insets every skinned control's content past its art carve on every side at every rung", {
			id = "native_parity_strength_paint::native paint strength: skinned control carve::insets every skinned control's content past its art carve on every side at every rung",
			run = function()
				local SIDES: { [string]: string } =
					{ left = "PaddingLeft", right = "PaddingRight", top = "PaddingTop", bottom = "PaddingBottom" }
				local function effective(sheet: any, node: any, property: string): number
					local own = node:FindFirstChildWhichIsA("UIPadding")
					if own and own[property].Offset ~= 0 then
						return own[property].Offset
					end
					local styled = resolve(sheet, node, property, "UIPadding")
					return if styled then styled.Offset else 0
				end
				local misses = {}
				for _, name in { "pixel_quest", "fantasy_ornate", "fantasy_parchment" } do
					local package = shipped(name)
					local h = harness({ theme = package })
					local sheet, stopSheet = sheetFor(h, package)
					for _, rung in
						{ "xsmall", "compact", "regular", "large" } :: { "compact" | "large" | "regular" | "xsmall" }
					do
						local options = { { value = "a", label = "(default)" }, { value = "b", label = "Other" } }
						local root, stop = mount(h, function()
							return h.Host.Frame({
								h.UI.Button({
									Name = "Button",
									label = "Go",
									controlSize = rung :: "compact" | "large" | "regular" | "xsmall",
								}) :: unknown,
								h.UI.Chip({
									Name = "Chip",
									label = "Chip",
									selected = Compose.cell(false),
									controlSize = rung :: "compact" | "large" | "regular" | "xsmall",
								}),
								h.UI.Picker({
									Name = "Menu",
									style = "menu" :: "menu",
									controlSize = rung :: "compact" | "large" | "regular" | "xsmall",
									selected = Compose.cell("a"),
									options = options,
								}),
								h.UI.Picker({
									Name = "Segmented",
									style = "segmented" :: "segmented",
									controlSize = rung :: "compact" | "large" | "regular" | "xsmall",
									selected = Compose.cell("a"),
									options = options,
								}),
								h.UI.TextInput({
									Name = "Field",
									value = Compose.cell("x"),
									controlSize = rung :: "compact" | "large" | "regular" | "xsmall",
								}),
							})
						end)
						local controls = {
							{ name = "Button", node = find(root, "Button"), skin = "control", scale = 1 },
							{ name = "Chip", node = find(root, "Chip"), skin = "control", scale = 1 },
							{
								name = "Trigger",
								node = find(find(root, "Menu"), "Trigger"),
								skin = "control",
								scale = 1,
							},
							{
								name = "Segment",
								node = find(find(root, "Segmented"), "a"),
								skin = "control",
								scale = 1,
							},
							{ name = "Field", node = find(find(root, "Field"), "Input"), skin = "field", scale = 1 },
						}
						for _, entry in controls do
							local label, node, slot = entry.name, entry.node, entry.skin
							local carve = package.chrome[slot].contentInsets
							for side, property in SIDES do
								local face = if side == "left" or side == "right" then 1 else 0
								local value = effective(sheet, node, property)
								if value < (carve[side] or 0) + face then
									table.insert(misses, `{name}/{rung}/{label}.{side}={value}<{carve[side]}+{face}`)
								end
							end
						end
						local trigger = find(find(root, "Menu"), "Trigger")
						local icon = find(trigger, "Disclosure")
						local right = effective(sheet, trigger, "PaddingRight")
						local iconRight = right - icon.Position.X.Offset
						local iconLeft = iconRight + icon.Size.X.Offset
						if iconRight < package.chrome.control.contentInsets.right + 1 or iconLeft > right then
							table.insert(misses, `{name}/{rung}/Disclosure right={right} icon={iconRight}..{iconLeft}`)
						end
						local E = h.engine.types.Enum
						if
							trigger.AutomaticSize ~= E.AutomaticSize.XY
							and trigger.AutomaticSize ~= E.AutomaticSize.Y
						then
							table.insert(misses, `{name}/{rung}/Trigger does not grow around its label`)
						end
						stop()
					end
					stopSheet()
					h.dispose()
				end
				Verify.expect((table.concat(misses, "\n"))):toBe("")
			end,
		})
	end)
end
