--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose
	local themes = Facet.themes
	local Roblox = require("@lune/roblox")

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

	local function make(options: { [string]: any }?): (any, any, any)
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local config: { [string]: any } = { types = engine.types, guiService = gui, services = { GuiService = gui } }
		for key, value in (options or {}) :: { [string]: any } do
			config[key] = value
		end
		return engine, runtime, Facet.controls(runtime, config :: any)
	end

	local function build(options: { [string]: any }?, body: (any, any) -> any): (any, any, () -> ())
		local engine, runtime, UI = make(options)
		local root: any
		runtime.mount(function()
			root = body(UI, runtime.constructors)
			return root
		end, engine.new("ScreenGui"))
		return root, engine, function()
			runtime:dispose()
		end
	end

	local function refusal(body: (any, any) -> any, options: { [string]: any }?): string?
		local engine, runtime, UI = make(options)
		local ok, message = pcall(function()
			runtime.mount(function()
				return body(UI, runtime.constructors)
			end, engine.new("ScreenGui"))
		end)
		runtime:dispose()
		return if ok then nil else tostring(message)
	end

	local function mentions(message: string?, fragment: string): boolean
		return message ~= nil and string.find(message, fragment, 1, true) ~= nil
	end

	local function sheetOf(package: any): (any, () -> ())
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local _, sheet: any = runtime.mount(function()
			return themes.createStyleSheet(
				runtime,
				package,
				{ types = engine.types, preferredTransparency = 1, motionLevel = "normal" } :: any
			)
		end, engine.new("Folder"))
		return sheet, function()
			runtime:dispose()
		end
	end

	local function style(sheet: any, selector: string): { [string]: any }
		for _, node in sheet:GetChildren() do
			if node.Selector == selector then
				return node:GetProperties()
			end
		end
		error("No rule: " .. selector)
	end

	local function packages(): { { label: string, package: any } }
		local out = { { label = "Facet Neutral", package = themes.neutralPackage() } }
		for _, name in SHIPPED do
			local module: any = (require :: any)("../examples/themes/" .. name)
			local package, report = module.build(themes)
			assert(report.ok, name .. " did not build")
			table.insert(out, { label = name, package = package })
		end
		return out
	end

	verifyHarness:suite("native restored controls: Text", function()
		verifyHarness:case("paints text with its type role and follows a bound text without a rebuild", {
			id = "native_restored_controls::native restored controls: Text::paints text with its type role and follows a bound text without a rebuild",
			run = function()
				local value = Compose.cell("Lap 1")
				local root, _, stop = build(nil, function(UI: FacetControls)
					return UI.Text("Lap")({ text = value, textRole = "title" :: "title" })
				end)
				Verify.expect(root.ClassName):toBe("TextLabel")
				Verify.expect(root.Name):toBe("Lap")
				Verify.expect(root.Text):toBe("Lap 1")
				Verify.expect((root:HasTag("facet-text"))):toBe(true)
				Verify.expect((root:HasTag("facet-type-title"))):toBe(true)
				value:set("Lap 2")
				Verify.expect(root.Text):toBe("Lap 2")
				stop()
				value:set("Lap 3")
				Verify.expect((value:peek())):toBe("Lap 3")
			end,
		})
	end)

	verifyHarness:suite("native restored controls: Label", function()
		for _, form in { "cell", "formula", "function" } :: { "cell" | "formula" | "function" } do
			verifyHarness:case(`tracks a {form} title in the text and the accessible name without a rebuild`, {
				id = "native_restored_controls::"
					.. "native restored controls: Label"
					.. "::"
					.. `tracks a {form} title in the text and the accessible name without a rebuild`,
				run = function()
					local value = Compose.cell("Lap 1")
					local builds = 0
					local root, _, stop = build(nil, function(UI: FacetControls)
						builds += 1
						local title: any = if form == "cell"
							then value
							elseif form == "formula" then Compose.formula(function(use: Use)
								return use(value)
							end)
							else function(use: any)
								return use(value)
							end
						return UI.Label("Lap")({ title = title })
					end)
					local before = root:FindFirstChild("Title")
					Verify.expect(before.Text):toBe("Lap 1")
					value:set("Lap 2")
					Verify.expect((root:FindFirstChild("Title"))):toBe(before)
					Verify.expect(before.Text):toBe("Lap 2")
					Verify.expect((root:GetAttribute("AccessibleLabel"))):toBe("Lap 2")
					Verify.expect(builds):toBe(1)
					stop()
					value:set("Lap 3")
					Verify.expect((value:peek())):toBe("Lap 3")
				end,
			})
		end

		verifyHarness:case("refuses an unknown semantic icon and plain-text options", {
			id = "native_restored_controls::native restored controls: Label::refuses an unknown semantic icon and plain-text options",
			run = function()
				Verify.expect((mentions(
					refusal(function(UI: FacetControls)
						return UI.Label({ title = "Saved", icon = "unknown-semantic-icon" })
					end),
					"unknown icon"
				))):toBe(true)
				Verify.expect((mentions(
					refusal(function(UI: FacetControls)
						return UI.Label({ text = "Saved" } :: any)
					end),
					"UI.Text"
				))):toBe(true)
			end,
		})
	end)

	verifyHarness:suite("native restored controls: Image", function()
		verifyHarness:case("checks each geometry key against its mode in both directions", {
			id = "native_restored_controls::native restored controls: Image::checks each geometry key against its mode in both directions",
			run = function()
				local cases: { { spec: any, fragment: string } } = {
					{ spec = { scaleMode = "tile" :: "tile" }, fragment = "requires tileSize" },
					{
						spec = { scaleMode = "tile" :: "tile", tileSize = { width = 1.5, height = 2 } },
						fragment = "whole pixels",
					},
					{ spec = { tileSize = { width = 2, height = 2 } }, fragment = "tileSize requires scaleMode tile" },
					{ spec = { scaleMode = "slice" :: "slice" }, fragment = "requires sliceCenter" },
					{
						spec = { sliceCenter = { x0 = 1, y0 = 1, x1 = 2, y1 = 2 } },
						fragment = "requires scaleMode slice",
					},
					{ spec = { sliceScale = 2 }, fragment = "sliceScale requires scaleMode slice" },
					{
						spec = {
							scaleMode = "slice" :: "slice",
							sliceCenter = { x0 = 1, y0 = 1, x1 = 2, y1 = 2 },
							sliceScale = 0,
						},
						fragment = "above zero",
					},
					{
						spec = { scaleMode = Compose.cell("fit"), tileSize = { width = 2, height = 2 } },
						fragment = "static",
					},
					{
						spec = {
							shape = "circle" :: "circle",
							scaleMode = "slice" :: "slice",
							sliceCenter = { x0 = 1, y0 = 1, x1 = 2, y1 = 2 },
						},
						fragment = "circle cannot slice",
					},
					{ spec = { scaleMode = "zoom" :: "zoom" }, fragment = "scaleMode must be" },
					{ spec = { imageFraming = { width = 2, height = 2 } }, fragment = "unknown option" },
				}
				for _, case in cases do
					Verify.expect((mentions(
						refusal(function(UI: FacetControls)
							return UI.Image(case.spec)
						end),
						case.fragment
					))):toBe(true)
				end
				local mode = Compose.cell("fit" :: "crop" | "fill" | "fit" | "slice" | "stretch" | "tile")
				local root, engine, stop = build(nil, function(UI: FacetControls)
					return UI.Image({ scaleMode = mode })
				end)
				local ok, failure = pcall(function()
					mode:set("tile")
				end)
				Verify.expect(ok):toBe(false)
				Verify.expect((mentions(tostring(failure), "static geometry"))):toBe(true)
				Verify.expect(root.ScaleType):toBe(engine.types.Enum.ScaleType.Fit)
				stop()
			end,
		})
	end)

	verifyHarness:suite("native restored controls: Divider", function()
		verifyHarness:case("uses the theme hairline weight by default and accepts pixels or a metric name", {
			id = "native_restored_controls::native restored controls: Divider::uses the theme hairline weight by default and accepts pixels or a metric name",
			run = function()
				local theme = Compose.cell(themes.neutralPackage())
				local root, engine, stop = build({ theme = theme }, function(UI: FacetControls)
					return UI.VStack({
						UI.Divider("Default")({}) :: unknown,
						UI.Divider("Pixels")({ thickness = 3 }),
						UI.Divider("Step")({ thickness = "xs" }),
					})
				end)
				local UDim2 = engine.types.UDim2
				Verify.expect(root:FindFirstChild("Default").Size):toBe(UDim2.new(1, 0, 0, 1))
				Verify.expect(root:FindFirstChild("Pixels").Size):toBe(UDim2.new(1, 0, 0, 3))
				local xs = themes.neutralPackage().metrics.space.xs
				Verify.expect(root:FindFirstChild("Step").Size):toBe(UDim2.new(1, 0, 0, xs))
				local heavy = themes.neutralPackage()
				heavy.metrics.strokes.hairline = 2
				theme:set(heavy)
				Verify.expect(root:FindFirstChild("Default").Size):toBe(UDim2.new(1, 0, 0, 2))
				stop()
				Verify.expect((mentions(
					refusal(function(UI: FacetControls)
						return UI.Divider({ thickness = 0 })
					end),
					"positive number"
				))):toBe(true)
			end,
		})

		verifyHarness:case("leaves its transparency at the class default so the divider rule paints the line", {
			id = "native_restored_controls::native restored controls: Divider::leaves its transparency at the class default so the divider rule paints the line",
			run = function()
				local root, _, stop = build(nil, function(UI: FacetControls)
					return UI.Divider({})
				end)
				Verify.expect(root.BackgroundTransparency):toBe(0)
				Verify.expect(root.BorderSizePixel):toBe(0)
				stop()
				Verify.expect((mentions(
					refusal(function(UI: FacetControls)
						return UI.Divider({ appearance = "loud" :: "loud" } :: any)
					end),
					"standard or strong"
				))):toBe(true)
			end,
		})

		verifyHarness:case("spends the transparency the hairline strokes spend in every shipped package", {
			id = "native_restored_controls::native restored controls: Divider::spends the transparency the hairline strokes spend in every shipped package",
			run = function()
				local count = 0
				for _, entry in packages() do
					local sheet, stop = sheetOf(entry.package)
					local extra = entry.package.style.themes[1].extra or {}
					local divider = style(sheet, ".facet-divider").BackgroundTransparency
					local stroke = style(sheet, ".facet-shortcut-hint::UIStroke").Transparency
					Verify.expect(divider):toBe(stroke)
					Verify.expect(divider):toBe(extra.hairlineOpacity or 0.92)
					local strong = style(sheet, ".facet-divider-strong").BackgroundTransparency
					Verify.expect(strong < divider):toBe(true)
					stop()
					count += 1
				end
				Verify.expect(count):toBe(#SHIPPED + 1)
			end,
		})

		verifyHarness:case("composited over its surface, a washed divider is quieter than secondary content", {
			id = "native_restored_controls::native restored controls: Divider::composited over its surface, a washed divider is quieter than secondary content",
			run = function()
				local function distance(a: any, b: any): number
					return math.max(math.abs(a.R - b.R), math.abs(a.G - b.G), math.abs(a.B - b.B))
				end
				local washed, bold = 0, {}
				for _, entry in packages() do
					local sheet, stop = sheetOf(entry.package)
					local rule = style(sheet, ".facet-divider")
					local transparency = rule.BackgroundTransparency
					if transparency < 0.5 then
						table.insert(bold, entry.label)
					else
						washed += 1
						local ink = rule.BackgroundColor3
						local words = style(sheet, ".facet-secondary").TextColor3
						for _, ground in
							{
								style(sheet, ".facet-level-segment").BackgroundColor3,
								style(sheet, ".facet-pane").BackgroundColor3,
							}
						do
							local alpha = 1 - transparency
							local seam = {
								R = ground.R + (ink.R - ground.R) * alpha,
								G = ground.G + (ink.G - ground.G) * alpha,
								B = ground.B + (ink.B - ground.B) * alpha,
							}
							Verify.expect(distance(seam, ground) > 0):toBe(true)
							Verify.expect(distance(seam, ground) < distance(words, ground)):toBe(true)
						end
					end
					stop()
				end
				Verify.expect(washed >= #SHIPPED):toBe(true)
				Verify.expect((table.concat(bold, ","))):toBe("pixel_quest")
			end,
		})
	end)

	verifyHarness:suite("native restored controls: Spacer", function()
		verifyHarness:case("keeps an explicit native size and refuses an invalid minimum", {
			id = "native_restored_controls::native restored controls: Spacer::keeps an explicit native size and refuses an invalid minimum",
			run = function()
				local root, engine, stop = build(nil, function(UI: FacetControls)
					return UI.HStack({ UI.Spacer("Gap")({ Size = Roblox.UDim2.fromOffset(40, 4), minLength = 8 }) })
				end)
				Verify.expect(root:FindFirstChild("Gap").Size):toBe(engine.types.UDim2.fromOffset(40, 4))
				stop()
				for _, value in { -1, "huge" } :: { any } do
					Verify.expect(refusal(function(UI: FacetControls)
						return UI.HStack({ UI.Spacer({ minLength = value }) })
					end) ~= nil):toBe(true)
				end
			end,
		})
	end)

	verifyHarness:suite("native restored controls: floating plates", function() end);
	(function(verifyHarness: Verify.Harness)
		type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
		type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
		type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
		type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)

		local Facet = require("../src")
		local engineLib = require("./lib/native_engine")
		local Compose: ComposeModule = Facet.Compose
		local themes = Facet.themes

		type World = {
			engine: any,
			runtime: any,
			gui: any,
			input: any,
			root: any,
			settle: () -> (),
			stop: () -> (),
		}

		local function setup(build: (any, any, any) -> any, options: { [string]: any }?): World
			local engine: any = engineLib.new()
			local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
			local gui = engine.new("GuiService")
			local input = engine.new("UserInputService")
			input.GetFocusedTextBox = function()
				return nil
			end
			input.IsKeyDown = function()
				return false
			end
			local config: { [string]: any } = {
				types = engine.types,
				guiService = gui,
				services = { GuiService = gui, UserInputService = input },
				motionLevel = "none",
			}
			for key, value in (options or {}) :: { [string]: any } do
				config[key] = value
			end
			local UI = Facet.controls(runtime, config :: any)
			local Host = (runtime.constructors :: unknown) :: RobloxHost
			local stop, root: any = runtime.mount(function()
				return Host.ScreenGui({ build(UI, Host, engine) })
			end, engine.new("Folder"))
			return {
				engine = engine,
				runtime = runtime,
				gui = gui,
				input = input,
				root = root,
				settle = function()
					for _ = 1, 60 do
						engine.heartbeat:Fire(1 / 60)
					end
				end,
				stop = function()
					stop()
					runtime:dispose()
				end,
			}
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

		local function glyph(name: string): string?
			return themes.resolveIcon({}, name)
		end

		local function paintedIcon(row: any): string?
			local icon = find(row, "LeadingIcon")
			return if icon and icon.Visible then icon.Image else nil
		end

		verifyHarness:suite("native parity weak3 h1", function()
			verifyHarness:case("resolves the Club check icon when a collapsible title changes", {
				id = "native_restored_controls::native parity weak3 h1::resolves the Club check icon when a collapsible title changes",
				run = function()
					local club = Compose.cell(false)
					local theme = Compose.cell(themes.neutralPackage())
					local world = setup(function(UI: FacetControls)
						return UI.CollapsibleView "Settings" {
							label = "Race settings",
							expanded = Compose.cell(false),
							icon = Compose.formula(function(use: any): string
								return if use(club) then "check" else "flag"
							end),
							content = function(): Instance
								return UI.Toggle "Club" { value = club, label = "Club membership" }
							end,
						}
					end, { theme = theme })
					local trigger = find(world.root, "Settings")
					Verify.expect(paintedIcon(trigger)):toBe(glyph("flag"))
					trigger.Activated:Fire()
					world.settle()
					local toggle = find(world.root, "Club")
					Verify.expect(toggle ~= nil):toBe(true)
					toggle.Activated:Fire()
					Verify.expect(paintedIcon(trigger)):toBe(glyph("checkmark"))
					Verify.expect(find(world.root, "Settings")):toBe(trigger)
					for _, name in { "glossy_mobile", "fantasy_parchment", "scifi_hud" } do
						theme:set((require :: any)("../examples/themes/" .. name).build(themes))
						Verify.expect(paintedIcon(trigger)):toBe(glyph("checkmark"))
					end
					world.stop()
				end,
			})
			for _, style in { "radioGroup", "inline" } :: { "inline" | "radioGroup" } do
			end
		end)
	end)(verifyHarness)
end
