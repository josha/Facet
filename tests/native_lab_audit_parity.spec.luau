--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local FixtureNavigationTypes = require("../src/ui/navigation_types")

	local Facet = require("../src")
	local worlds = require("./lib/content_world")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose
	local themes = Facet.themes

	local function package(name: string): any
		if name == "neutral" then
			return themes.neutralPackage()
		end
		local module: any = (require :: any)("../examples/themes/" .. name)
		return module.build(themes)
	end

	local function tall(node: any): number
		local floor = node:FindFirstChildWhichIsA("UISizeConstraint")
		return math.max(node.Size.Y.Offset, if floor then floor.MinSize.Y else 0)
	end

	local function tagged(root: any, tag: string): { any }
		local found = {}
		for _, node in root:GetDescendants() do
			if node:HasTag(tag) then
				table.insert(found, node)
			end
		end
		return found
	end

	local function sheetFor(theme: any): (any, () -> ())
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local sheet
		local stop = runtime.mount(function()
			sheet = themes.createStyleSheet(runtime, theme, { types = engine.types })
			return sheet
		end, engine.new("Folder"))
		return sheet, stop
	end

	local function rule(sheet: any, selector: string): any?
		for _, node in sheet:GetChildren() do
			if node.Selector == selector then
				return node
			end
		end
		return nil
	end

	verifyHarness:suite("native lab audit: menu submenu rows", function()
		verifyHarness:case("a submenu row shows its chevron beside a shortcut row, and the shortcut row shows none", {
			id = "native_lab_audit_parity::native lab audit: menu submenu rows::a submenu row shows its chevron beside a shortcut row, and the shortcut row shows none",
			run = function()
				local opened = Compose.cell(false)
				local w = worlds.new(function(UI: FacetControls)
					return UI.Menu({
						isPresented = opened,
						items = {
							{ id = "copy", label = "Copy", shortcutLabel = "Ctrl+C", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
							{
								id = "share",
								label = "Share",
								children = { { id = "mail", label = "Mail", onSelect = function() end } },
							} :: FixtureNavigationTypes.MenuItem<any>,
						},
					})
				end)
				opened:set(true)
				local share, copy = w.find("share"), w.find("copy")
				Verify.expect(share ~= nil and copy ~= nil):toBe(true)
				Verify.expect(w.find("TrailingIcon", share) ~= nil):toBe(true)
				Verify.expect((w.find("TrailingIcon", copy))):toBe(nil)
				Verify.expect(#w.findAll("TrailingIcon", w.screen)):toBe(1)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native lab audit: Slider rung thumb and track floor", function()
		local function cell(axis: "x" | "y", size: ("xsmall" | "compact" | "regular" | "large")?): (any, number)
			local w = worlds.new(function(UI: FacetControls, Host: RobloxHost, engine)
				return Host.Frame({
					Name = "Cell",
					AutomaticSize = engine.types.Enum.AutomaticSize.XY,
					UI.Slider("Vol")({
						label = "Vol",
						value = Compose.cell(50),
						min = 0,
						max = 100,
						axis = axis,
						controlSize = size,
						onChange = function() end,
					}),
				})
			end)
			local thumbs = tagged(w.screen, "facet-slider-thumb")
			Verify.expect(#thumbs >= 1):toBe(true)
			return w, thumbs[1].Size.X.Offset
		end
		for _, axis in { "x", "y" } do
			verifyHarness:case(`axis {axis}: the track keeps one target of travel in a hugging cell`, {
				id = "native_lab_audit_parity::"
					.. "native lab audit: Slider rung thumb and track floor"
					.. "::"
					.. `axis {axis}: the track keeps one target of travel in a hugging cell`,
				run = function()
					local w = cell(axis :: "x" | "y", nil)
					local floor = w.find("Track"):FindFirstChildWhichIsA("UISizeConstraint")
					Verify.expect(floor ~= nil):toBe(true)
					Verify.expect(if axis == "y" then floor.MinSize.Y else floor.MinSize.X):toBe(44)
					w.stop()
				end,
			})
		end
		verifyHarness:case("compact and large thumbs differ, and regular is the theme's thumb", {
			id = "native_lab_audit_parity::native lab audit: Slider rung thumb and track floor::compact and large thumbs differ, and regular is the theme's thumb",
			run = function()
				local sizes: { [string]: number } = {}
				for _, rung in { "compact", "regular", "large", "none" } :: { "compact" | "large" | "none" | "regular" } do
					local w, size =
						cell("y", if rung == "none" then nil else rung :: "xsmall" | "compact" | "regular" | "large")
					sizes[rung] = size
					w.stop()
				end
				Verify.expect(sizes.compact < sizes.regular and sizes.regular < sizes.large):toBe(true)
				Verify.expect(sizes.regular):toBe(sizes.none)
			end,
		})
	end)

	verifyHarness:suite("native lab audit: ProgressView rungs", function()
		verifyHarness:case(
			"a bar spends its rung on track thickness: small rungs thin, regular and large the theme track",
			{
				id = "native_lab_audit_parity::native lab audit: ProgressView rungs::a bar spends its rung on track thickness: small rungs thin, regular and large the theme track",
				run = function()
					for rung, px in
						{ xsmall = 4, compact = 4, regular = 6, large = 6, none = 6 } :: { [string]: number }
					do
						local w = worlds.new(function(UI: FacetControls)
							return UI.ProgressView("P")({
								value = 0.5,
								controlSize = if rung == "none"
									then nil
									else rung :: "xsmall" | "compact" | "regular" | "large",
							})
						end)
						Verify.expect(`{rung}={w.find("Track").Size.Y.Offset}`):toBe(`{rung}={px}`)
						w.stop()
					end
				end,
			}
		)
		verifyHarness:case("a large ring shows its value in the gauge", {
			id = "native_lab_audit_parity::native lab audit: ProgressView rungs::a large ring shows its value in the gauge",
			run = function()
				local w = worlds.new(function(UI: FacetControls)
					return UI.ProgressView("P")({
						value = 0.65,
						presentation = "circular" :: "circular",
						showValue = true,
						controlSize = "large" :: "large",
						format = function(value: number): string
							return tostring(value)
						end,
					})
				end)
				local value = w.find("Value", w.find("Gauge"))
				Verify.expect(value ~= nil):toBe(true)
				Verify.expect(value.Text):toBe("0.65")
				w.stop()
			end,
		})
		verifyHarness:case("refuses a bar rung with a thickness", {
			id = "native_lab_audit_parity::native lab audit: ProgressView rungs::refuses a bar rung with a thickness",
			run = function()
				local ok, err = pcall(function()
					worlds.new(function(UI: FacetControls)
						return UI.ProgressView("P")({ value = 0.5, controlSize = "compact" :: "compact", thickness = 8 })
					end)
				end)
				Verify.expect(ok):toBe(false)
				Verify.expect(string.find(tostring(err), "not both", 1, true) ~= nil):toBe(true)
				for _, spec in
					{
						{
							presentation = "circular" :: "circular",
							value = 0.5,
							diameter = 64,
							controlSize = "regular" :: "regular",
						},
						{ presentation = "spinner" :: "spinner", controlSize = "huge" :: "huge" },
						{ value = 0.5, endLabel = 7 },
						{ value = 0.5, endLabel = Compose.cell(7 :: any) },
					} :: { { [string]: any } }
				do
					Verify.expect(worlds.mountError(function(UI: FacetControls)
						return UI.ProgressView("P")(spec :: any)
					end) ~= nil):toBe(true)
				end
				Verify.expect((worlds.mountError(function(UI: FacetControls)
					return UI.ProgressView("P")({ value = 0.5, endLabel = "Done" })
				end))):toBeNil()
			end,
		})
	end)

	verifyHarness:suite("native lab audit: Vote and one rung plate height", function()
		verifyHarness:case("a readOnly vote keeps the interactive strip's rung height", {
			id = "native_lab_audit_parity::native lab audit: Vote and one rung plate height::a readOnly vote keeps the interactive strip's rung height",
			run = function()
				local heights: { [string]: number } = {}
				for _, readOnly in { false, true } do
					for _, rung in { "compact", "large" } :: { "compact" | "large" } do
						local w = worlds.new(function(UI: FacetControls)
							return UI.Vote("V")({
								value = "up" :: "up",
								readOnly = readOnly,
								controlSize = rung :: "xsmall" | "compact" | "regular" | "large",
								onChange = function() end,
							})
						end)
						heights[`{readOnly}/{rung}`] = tall(w.find("Opt1", w.find("V")))
						w.stop()
					end
				end
				Verify.expect(heights["true/compact"]):toBe(heights["false/compact"])
				Verify.expect(heights["true/large"]):toBe(heights["false/large"])
				Verify.expect(heights["true/compact"] < heights["true/large"]):toBe(true)
			end,
		})
		for _, name in
			{
				"neutral",
				"classic_desktop",
				"compact_pointer",
				"fantasy_ornate",
				"fantasy_parchment",
				"glossy_mobile",
				"glossy_touch",
				"pixel_quest",
				"scifi_hud",
			}
		do
			verifyHarness:case(`{name}: a Button, the segmented track and a checkbox land on one rung height`, {
				id = "native_lab_audit_parity::"
					.. "native lab audit: Vote and one rung plate height"
					.. "::"
					.. `{name}: a Button, the segmented track and a checkbox land on one rung height`,
				run = function()
					local boxes: { number } = {}
					for _, rung in
						{ "xsmall", "compact", "regular", "large" } :: { "compact" | "large" | "regular" | "xsmall" }
					do
						local options = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } }
						local w = worlds.new(function(UI: FacetControls, Host: RobloxHost)
							return Host.Frame({
								Name = "Row",
								UI.Button("B")({
									label = "Settings",
									controlSize = rung :: "xsmall" | "compact" | "regular" | "large",
								}) :: unknown,
								UI.Picker("PM")({
									label = "Theme:",
									style = "menu" :: "menu",
									controlSize = rung :: "xsmall" | "compact" | "regular" | "large",
									selected = Compose.cell("a"),
									options = options,
								}),
								UI.Picker("PS")({
									style = "segmented" :: "segmented",
									controlSize = rung :: "xsmall" | "compact" | "regular" | "large",
									selected = Compose.cell("a"),
									options = options,
								}),
								UI.TextInput("TI")({
									value = Compose.cell("x"),
									controlSize = rung :: "xsmall" | "compact" | "regular" | "large",
								}),
								UI.Toggle("TK")({
									label = "Motion",
									presentation = "checkbox" :: "checkbox",
									controlSize = rung :: "xsmall" | "compact" | "regular" | "large",
									value = Compose.cell(false),
								}),
								UI.Toggle("TC")({
									label = "Reduced Motion",
									presentation = "checkbox" :: "checkbox",
									appearance = "plain" :: "plain",
									controlSize = rung :: "xsmall" | "compact" | "regular" | "large",
									value = Compose.cell(false),
								}),
								UI.Toggle("TS")({
									label = "Music",
									controlSize = rung :: "xsmall" | "compact" | "regular" | "large",
									value = Compose.cell(false),
								}),
							})
						end, { theme = package(name) })
						local button = w.find("B").Size.Y.Offset
						Verify.expect(w.find("PS"):FindFirstChild("TargetFloor").MinSize.Y):toBe(button)
						Verify.expect(`{rung} {button > 0}`):toBe(`{rung} true`)
						local plated = {
							menu = w.find("Trigger", w.find("PM")),
							segmented = w.find("PS"),
							field = w.find("Input", w.find("TI")),
							checkbox = w.find("TK"),
						}
						for key, node in plated :: { [string]: GuiObject } do
							Verify.expect(`{rung} {key} {node.Size.Y.Offset}`):toBe(`{rung} {key} {button}`)
						end
						for _, key in { "TC", "TS" } do
							Verify.expect(`{rung} {key} {w.find(key).Size.Y.Offset <= button}`)
								:toBe(`{rung} {key} true`)
						end
						local box = w.find("Indicator", w.find("TC")).Size
						Verify.expect(`{rung} {box.X.Offset == box.Y.Offset and box.Y.Offset <= button}`)
							:toBe(`{rung} true`)
						table.insert(boxes, box.Y.Offset)
						w.stop()
					end
					Verify.expect(boxes[1] <= boxes[2] and boxes[2] <= boxes[3] and boxes[3] <= boxes[4]):toBe(true)
					Verify.expect(boxes[1] < boxes[4]):toBe(true)
				end,
			})
		end
	end)

	verifyHarness:suite("native lab audit: Badge status mark", function()
		verifyHarness:case("the status mark has no page-colour ring and reads against the badge plate", {
			id = "native_lab_audit_parity::native lab audit: Badge status mark::the status mark has no page-colour ring and reads against the badge plate",
			run = function()
				for _, name in { "neutral", "pixel_quest", "fantasy_ornate" } do
					for _, status in
						{ "warning", "error", "accent", "neutral" } :: { "accent" | "error" | "neutral" | "warning" }
					do
						local w = worlds.new(function(UI: FacetControls)
							return UI.Badge("B")({
								label = "Ready",
								appearance = "status" :: "status",
								status = status :: "accent" | "error" | "neutral" | "warning",
							})
						end, { theme = package(name) })
						Verify.expect(w.find("Status") ~= nil):toBe(true)
						Verify.expect((w.find("Cutout"))):toBe(nil)
						Verify.expect(#tagged(w.screen, "facet-cutout")):toBe(0)
						w.stop()
					end
					local sheet, stop = sheetFor(package(name))
					local plate = assert(rule(sheet, ".facet-badge-status")):GetProperties().BackgroundColor3
					for _, status in
						{ "warning", "error", "accent", "neutral" } :: { "accent" | "error" | "neutral" | "warning" }
					do
						local mark = assert(rule(sheet, ".facet-status-" .. status)):GetProperties().BackgroundColor3
						Verify.expect(`{name} {status} {mark == plate}`):toBe(`{name} {status} false`)
					end
					stop()
				end
			end,
		})
		verifyHarness:case("an unplated utility badge draws no status mark", {
			id = "native_lab_audit_parity::native lab audit: Badge status mark::an unplated utility badge draws no status mark",
			run = function()
				local w = worlds.new(function(UI: FacetControls)
					return UI.Badge("B")({
						label = "Ready",
						appearance = "utility" :: "utility",
						status = "success" :: "success",
					})
				end)
				Verify.expect((w.find("Status"))):toBe(nil)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native lab audit: ShortcutHint keycap outline", function()
		verifyHarness:case("the keycap stroke is a theme metric: Neutral the hairline, 0 draws none", {
			id = "native_lab_audit_parity::native lab audit: ShortcutHint keycap outline::the keycap stroke is a theme metric: Neutral the hairline, 0 draws none",
			run = function()
				local neutral = themes.neutralPackage()
				local sheet, stop = sheetFor(neutral)
				local stroke = assert(rule(sheet, ".facet-shortcut-hint::UIStroke")):GetProperties()
				Verify.expect(stroke.Thickness):toBe(neutral.metrics.strokes.hairline)
				stop()
				for thickness, expected in { [0] = false, [2] = true } :: { [number]: boolean } do
					local soft, report = themes.define({
						base = themes.neutralPackage(),
						identity = {
							id = "soft",
							displayName = "Soft",
							schemaVersion = themes.SCHEMA,
							version = "1.0.0",
						},
						metrics = { controls = { shortcutHint = { capStroke = thickness, capGap = 2 } } },
					} :: any)
					assert(soft ~= nil, tostring(report.errors[1] and report.errors[1].message))
					local other, done = sheetFor(soft)
					local found = rule(other, ".facet-shortcut-hint::UIStroke")
					Verify.expect(found ~= nil):toBe(expected)
					if found then
						Verify.expect(found:GetProperties().Thickness):toBe(thickness)
					end
					done()
				end
			end,
		})
	end)

	verifyHarness:suite("native lab audit: StepIndicator rung marker", function()
		verifyHarness:case("the rung sizes the step marker, and regular is the theme's medium icon", {
			id = "native_lab_audit_parity::native lab audit: StepIndicator rung marker::the rung sizes the step marker, and regular is the theme's medium icon",
			run = function()
				local sizes: { [string]: number } = {}
				for _, rung in { "compact", "regular", "large", "none" } :: { "compact" | "large" | "none" | "regular" } do
					local w = worlds.new(function(UI: FacetControls)
						return UI.StepIndicator("S")({
							steps = {
								{ id = "cart", label = "Cart" },
								{ id = "pay", label = "Pay" },
								{ id = "ship", label = "Ship" },
							},
							current = "ship",
							controlSize = if rung == "none"
								then nil
								else rung :: "xsmall" | "compact" | "regular" | "large",
						})
					end)
					sizes[rung] = w.find("Cue").Size.Y.Offset
					w.stop()
				end
				Verify.expect(sizes.compact <= sizes.regular and sizes.regular < sizes.large):toBe(true)
				Verify.expect(sizes.regular):toBe(sizes.none)
			end,
		})
	end)

	verifyHarness:suite("native lab audit: Notice plate carve", function()
		verifyHarness:case("an art theme's panel carve pads the standard plate; emphasis keeps the plain inset", {
			id = "native_lab_audit_parity::native lab audit: Notice plate carve::an art theme's panel carve pads the standard plate; emphasis keeps the plain inset",
			run = function()
				for _, name in { "neutral", "pixel_quest", "fantasy_ornate", "glossy_mobile" } do
					local theme = package(name)
					local carve = ((theme.chrome or {}).panel or {}).contentInsets or {}
					for _, appearance in { "standard", "emphasis" } :: { "emphasis" | "standard" } do
						local w = worlds.new(function(UI: FacetControls)
							return UI.Notice("Conn")({
								title = "Update available",
								message = "A new track pack is ready.",
								appearance = appearance :: "emphasis" | "standard",
								actions = { { id = "Install", label = "Install", onActivate = function() end } },
								onDismiss = function() end,
							})
						end, { theme = theme })
						local root = w.find("Conn")
						local padding = root:FindFirstChildWhichIsA("UIPadding")
						local want = if appearance == "emphasis" then 8 else math.max(8, carve.left or 0)
						Verify.expect(`{name} {appearance} {padding.PaddingLeft.Offset}`)
							:toBe(`{name} {appearance} {want}`)
						local top = if appearance == "emphasis" then 8 else math.max(8, carve.top or 0)
						Verify.expect(`{name} {appearance} {padding.PaddingTop.Offset}`)
							:toBe(`{name} {appearance} {top}`)
						local title = w.find("Title", root)
						Verify.expect(title.TextWrapped):toBe(true)
						w.stop()
					end
				end
			end,
		})
	end)
end
