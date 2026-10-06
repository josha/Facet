--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
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

		verifyHarness:case("takes a pixel size, a role name, alignment, wrapping, rich text, direction and tint", {
			id = "native_restored_controls::native restored controls: Text::takes a pixel size, a role name, alignment, wrapping, rich text, direction and tint",
			run = function()
				local align = Compose.cell("center" :: "center" | "end" | "start")
				local root, engine, stop = build(nil, function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Text("Pixels")({ text = "a", textSize = 22 }) :: unknown,
						UI.Text("Role")({ text = "b", textSize = "caption" :: "caption" }),
						UI.Text("Styled")({
							text = "<b>c</b>",
							textAlign = align,
							wrap = true,
							rich = true,
							direction = "rtl" :: "rtl",
							tint = Roblox.Color3.new(1, 0, 0),
						}),
					})
				end)
				local Enum = engine.types.Enum
				local pixels, role, styled =
					root:FindFirstChild("Pixels"), root:FindFirstChild("Role"), root:FindFirstChild("Styled")
				Verify.expect(pixels.TextSize):toBe(22)
				Verify.expect((pixels:HasTag("facet-type-body"))):toBe(true)
				Verify.expect((role:HasTag("facet-type-caption"))):toBe(true)
				Verify.expect((role:HasTag("facet-type-body"))):toBe(false)
				Verify.expect(styled.TextXAlignment):toBe(Enum.TextXAlignment.Center)
				align:set("end")
				Verify.expect(styled.TextXAlignment):toBe(Enum.TextXAlignment.Right)
				Verify.expect(styled.TextWrapped):toBe(true)
				Verify.expect(styled.RichText):toBe(true)
				Verify.expect(styled.TextDirection):toBe(Enum.TextDirection.RightToLeft)
				Verify.expect(styled.TextColor3):toBe(engine.types.Color3.new(1, 0, 0))
				stop()
			end,
		})

		verifyHarness:case("turns the secondary role on and off with a bound role", {
			id = "native_restored_controls::native restored controls: Text::turns the secondary role on and off with a bound role",
			run = function()
				local role = Compose.cell("secondary" :: "content" | "secondary")
				local root, _, stop = build(nil, function(UI: FacetControls)
					return UI.Text({ text = "Offline", role = role })
				end)
				Verify.expect((root:HasTag("facet-secondary"))):toBe(true)
				role:set("content")
				Verify.expect((root:HasTag("facet-secondary"))):toBe(false)
				role:set("secondary")
				Verify.expect((root:HasTag("facet-secondary"))):toBe(true)
				stop()
			end,
		})

		verifyHarness:case("refuses a missing text, the retired spellings, style authority and a doubled role", {
			id = "native_restored_controls::native restored controls: Text::refuses a missing text, the retired spellings, style authority and a doubled role",
			run = function()
				Verify.expect((mentions(
					refusal(function(UI: FacetControls)
						return UI.Text({} :: any)
					end),
					"requires text"
				))):toBe(true)
				for _, spec in { { label = "a" }, { text = "a", label = "b" }, { Text = "a" } } :: { any } do
					Verify.expect((mentions(
						refusal(function(UI: FacetControls)
							return UI.Text(spec)
						end),
						"set the text with text"
					))):toBe(true)
				end
				for _, key in { "color", "font" } do
					Verify.expect((mentions(
						refusal(function(UI: FacetControls)
							return UI.Text({ text = "a", [key] = "x" } :: any)
						end),
						"style authority"
					))):toBe(true)
				end
				Verify.expect((mentions(
					refusal(function(UI: FacetControls)
						return UI.Text(
							{ text = "a", textSize = "title" :: "title", textRole = "body" :: "body" } :: any
						)
					end),
					"one time"
				))):toBe(true)
				Verify.expect((mentions(
					refusal(function(UI: FacetControls)
						return UI.Text({ text = "a", role = "loud" :: "loud" } :: any)
					end),
					"secondary or content"
				))):toBe(true)
				Verify.expect((mentions(
					refusal(function(UI: FacetControls)
						return UI.Text({ text = "a", direction = "up" :: "up" } :: any)
					end),
					"auto, ltr or rtl"
				))):toBe(true)
			end,
		})
	end)

	verifyHarness:suite("native restored controls: Label", function()
		verifyHarness:case("renders an icon and a title together and names itself by the title", {
			id = "native_restored_controls::native restored controls: Label::renders an icon and a title together and names itself by the title",
			run = function()
				local root, _, stop = build(nil, function(UI: FacetControls)
					return UI.Label("Save")({ title = "Save", icon = "rbxassetid://1" })
				end)
				Verify.expect(root.Name):toBe("Save")
				Verify.expect(root:FindFirstChild("Icon").ClassName):toBe("ImageLabel")
				Verify.expect(root:FindFirstChild("Icon").Image):toBe("rbxassetid://1")
				Verify.expect(root:FindFirstChild("Title").Text):toBe("Save")
				Verify.expect((root:GetAttribute("AccessibleLabel"))):toBe("Save")
				Verify.expect((root:GetAttribute("FacetPresentation"))):toBe("titleAndIcon")
				Verify.expect(root:FindFirstChild("Icon").LayoutOrder < root:FindFirstChild("Title").LayoutOrder)
					:toBe(true)
				stop()
			end,
		})

		verifyHarness:case("keeps the title as the accessible name when it shows the icon only", {
			id = "native_restored_controls::native restored controls: Label::keeps the title as the accessible name when it shows the icon only",
			run = function()
				local root, _, stop = build(nil, function(UI: FacetControls)
					return UI.Label({ title = "Save", icon = "rbxassetid://1", presentation = "iconOnly" :: "iconOnly" })
				end)
				Verify.expect((root:FindFirstChild("Title"))):toBe(nil)
				Verify.expect(root:FindFirstChild("Icon") ~= nil):toBe(true)
				Verify.expect((root:GetAttribute("AccessibleLabel"))):toBe("Save")
				Verify.expect((root:GetAttribute("FacetPresentation"))):toBe("iconOnly")
				stop()
			end,
		})

		verifyHarness:case("shows the title when iconOnly has no icon, because an empty square is worse than a word", {
			id = "native_restored_controls::native restored controls: Label::shows the title when iconOnly has no icon, because an empty square is worse than a word",
			run = function()
				local root, _, stop = build(nil, function(UI: FacetControls)
					return UI.Label({ title = "Save", presentation = "iconOnly" :: "iconOnly" })
				end)
				Verify.expect((root:GetAttribute("FacetPresentation"))):toBe("titleOnly")
				Verify.expect(root:FindFirstChild("Title") ~= nil):toBe(true)
				Verify.expect((root:FindFirstChild("Icon"))):toBe(nil)
				stop()
			end,
		})

		verifyHarness:case("titleOnly renders no empty icon slot", {
			id = "native_restored_controls::native restored controls: Label::titleOnly renders no empty icon slot",
			run = function()
				local root, _, stop = build(nil, function(UI: FacetControls)
					return UI.Label({
						title = "Save",
						icon = "rbxassetid://1",
						presentation = "titleOnly" :: "titleOnly",
					})
				end)
				Verify.expect((root:FindFirstChild("Icon"))):toBe(nil)
				Verify.expect(root:FindFirstChild("Title").Text):toBe("Save")
				stop()
			end,
		})

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

		verifyHarness:case("requires a title, because an icon-only label without one has no accessible name", {
			id = "native_restored_controls::native restored controls: Label::requires a title, because an icon-only label without one has no accessible name",
			run = function()
				for _, spec in
					{
						{ icon = "rbxassetid://1" },
						{ title = "" },
						{ title = 4 },
						{ title = Compose.cell("") },
						{
							title = function()
								return false
							end,
						},
					} :: { any }
				do
					Verify.expect((mentions(
						refusal(function(UI: FacetControls)
							return UI.Label(spec)
						end),
						"title"
					))):toBe(true)
				end
			end,
		})

		verifyHarness:case("rejects an unknown presentation and names the legal set", {
			id = "native_restored_controls::native restored controls: Label::rejects an unknown presentation and names the legal set",
			run = function()
				Verify.expect((mentions(
					refusal(function(UI: FacetControls)
						return UI.Label({ title = "T", presentation = "sideways" :: "sideways" } :: any)
					end),
					"iconOnly | titleAndIcon | titleOnly"
				))):toBe(true)
			end,
		})

		verifyHarness:case("refuses an unknown semantic icon and plain-text options", {
			id = "native_restored_controls::native restored controls: Label::refuses an unknown semantic icon and plain-text options",
			run = function()
				Verify.expect((mentions(
					refusal(function(UI: FacetControls)
						return UI.Label({ title = "Saved", icon = "check" })
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

		verifyHarness:case("sizes a semantic icon by a metric name or pixels, and puts it after the title on request", {
			id = "native_restored_controls::native restored controls: Label::sizes a semantic icon by a metric name or pixels, and puts it after the title on request",
			run = function()
				local root, _, stop = build(nil, function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Label("Metric")({
							title = "Search",
							icon = "facet:search",
							presentation = "iconOnly" :: "iconOnly",
							iconSize = "controlSizes.large.iconSize",
						}) :: unknown,
						UI.Label("Pixels")({
							title = "Next",
							icon = "chevron.trailing",
							iconSize = 30,
							iconPosition = "trailing" :: "trailing",
						}),
					})
				end)
				local metric = root:FindFirstChild("Metric"):FindFirstChild("Icon")
				local expected = themes.neutralPackage().metrics.controlSizes.large.iconSize
				Verify.expect(metric.Size.X.Offset):toBe(expected)
				Verify.expect(metric.Image ~= ""):toBe(true)
				local pixels = root:FindFirstChild("Pixels")
				Verify.expect(pixels:FindFirstChild("Icon").Size.X.Offset):toBe(30)
				Verify.expect(pixels:FindFirstChild("Title").LayoutOrder < pixels:FindFirstChild("Icon").LayoutOrder)
					:toBe(true)
				stop()
			end,
		})
	end)

	verifyHarness:suite("native restored controls: Image", function()
		verifyHarness:case("maps every scale mode to the native ScaleType and follows a bound mode", {
			id = "native_restored_controls::native restored controls: Image::maps every scale mode to the native ScaleType and follows a bound mode",
			run = function()
				local mode = Compose.cell("fit" :: "crop" | "fill" | "fit" | "slice" | "stretch" | "tile")
				local root, engine, stop = build(nil, function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Image("Bound")({ image = "rbxassetid://1", scaleMode = mode }) :: unknown,
						UI.Image("Tile")({
							image = "rbxassetid://1",
							scaleMode = "tile" :: "tile",
							tileSize = { width = 32, height = 16 },
						}),
						UI.Image("Slice")({
							image = "rbxassetid://1",
							scaleMode = "slice" :: "slice",
							sliceCenter = { x0 = 8, y0 = 8, x1 = 56, y1 = 56 },
							sliceScale = 2,
						}),
					})
				end)
				local types = engine.types
				local ScaleType = types.Enum.ScaleType
				local bound = root:FindFirstChild("Bound")
				Verify.expect(bound.ClassName):toBe("ImageLabel")
				Verify.expect(bound.Image):toBe("rbxassetid://1")
				Verify.expect(bound.ScaleType):toBe(ScaleType.Fit)
				local scaleTypes: { [string]: Enum.ScaleType } =
					{ fill = ScaleType.Crop, crop = ScaleType.Crop, stretch = ScaleType.Stretch }
				for word, native in scaleTypes do
					mode:set(word :: "fill" | "crop" | "stretch")
					Verify.expect(bound.ScaleType):toBe(native)
				end
				local tile = root:FindFirstChild("Tile")
				Verify.expect(tile.ScaleType):toBe(ScaleType.Tile)
				Verify.expect(tile.TileSize):toBe(types.UDim2.fromOffset(32, 16))
				local slice = root:FindFirstChild("Slice")
				Verify.expect(slice.ScaleType):toBe(ScaleType.Slice)
				Verify.expect(slice.SliceCenter):toBe(types.Rect.new(8, 8, 56, 56))
				Verify.expect(slice.SliceScale):toBe(2)
				stop()
			end,
		})

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

		verifyHarness:case("resamples, tints, sizes and rounds a circle through native properties", {
			id = "native_restored_controls::native restored controls: Image::resamples, tints, sizes and rounds a circle through native properties",
			run = function()
				local resample = Compose.cell("pixelated" :: "default" | "pixelated")
				local root, engine, stop = build(nil, function(UI: FacetControls)
					return UI.Image({
						image = "rbxassetid://2",
						resample = resample,
						tint = Roblox.Color3.new(0, 1, 0),
						shape = "circle" :: "circle",
					})
				end)
				local types = engine.types
				Verify.expect(root.ResampleMode):toBe(types.Enum.ResamplerMode.Pixelated)
				resample:set("default")
				Verify.expect(root.ResampleMode):toBe(types.Enum.ResamplerMode.Default)
				Verify.expect(root.ImageColor3):toBe(types.Color3.new(0, 1, 0))
				local height = themes.neutralPackage().metrics.controlSizes.regular.height
				Verify.expect(root.Size):toBe(types.UDim2.fromOffset(height, height))
				Verify.expect(root:FindFirstChildWhichIsA("UICorner").CornerRadius):toBe(types.UDim.new(1, 0))
				Verify.expect(root:FindFirstChildWhichIsA("UIAspectRatioConstraint").AspectRatio):toBe(1)
				Verify.expect(root.BackgroundTransparency):toBe(1)
				stop()
			end,
		})
	end)

	verifyHarness:suite("native restored controls: Divider", function()
		verifyHarness:case("takes its direction from the stack that holds it and turns with it", {
			id = "native_restored_controls::native restored controls: Divider::takes its direction from the stack that holds it and turns with it",
			run = function()
				local root, engine, stop = build(nil, function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.VStack("Column")({ UI.Divider("Rule")({}) }) :: unknown,
						UI.HStack("Row")({ UI.Divider("Rule")({}) }),
						UI.HStack("Forced")({ UI.Divider("Rule")({ axis = "y" :: "y" }) }),
					})
				end)
				local UDim2 = engine.types.UDim2
				local hairline = themes.neutralPackage().metrics.strokes.hairline
				local function rule(name: string): any
					return root:FindFirstChild(name):FindFirstChild("Rule")
				end
				Verify.expect(rule("Column").Size):toBe(UDim2.new(1, 0, 0, hairline))
				Verify.expect(rule("Row").Size):toBe(UDim2.new(0, hairline, 1, 0))
				Verify.expect(rule("Forced").Size):toBe(UDim2.new(1, 0, 0, hairline))
				local layout = root:FindFirstChild("Column"):FindFirstChildWhichIsA("UIListLayout")
				layout.FillDirection = engine.types.Enum.FillDirection.Horizontal
				Verify.expect(rule("Column").Size):toBe(UDim2.new(0, hairline, 1, 0))
				layout.FillDirection = engine.types.Enum.FillDirection.Vertical
				Verify.expect(rule("Column").Size):toBe(UDim2.new(1, 0, 0, hairline))
				stop()
			end,
		})

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

		verifyHarness:case("wears the divider tags and adds the strong tag while a bound appearance is strong", {
			id = "native_restored_controls::native restored controls: Divider::wears the divider tags and adds the strong tag while a bound appearance is strong",
			run = function()
				local appearance = Compose.cell("standard" :: "standard" | "strong")
				local root, _, stop = build(nil, function(UI: FacetControls)
					return UI.Divider({ appearance = appearance })
				end)
				Verify.expect((root:HasTag("facet-divider"))):toBe(true)
				Verify.expect((root:HasTag("facet-divider-strong"))):toBe(false)
				appearance:set("strong")
				Verify.expect((root:HasTag("facet-divider-strong"))):toBe(true)
				appearance:set("standard")
				Verify.expect((root:HasTag("facet-divider-strong"))):toBe(false)
				stop()
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
		verifyHarness:case("fills the free main-axis space and keeps a themed minimum on the stack axis", {
			id = "native_restored_controls::native restored controls: Spacer::fills the free main-axis space and keeps a themed minimum on the stack axis",
			run = function()
				local floor = Compose.cell("m")
				local root, engine, stop = build(nil, function(UI: FacetControls)
					return UI.VStack({
						UI.HStack("Row")({ UI.Spacer("Gap")({ minLength = floor }) }) :: unknown,
						UI.VStack("Column")({ UI.Spacer("Gap")({ minLength = 12 }) }),
						UI.VStack("Bare")({ UI.Spacer("Gap")({}) }),
					})
				end)
				local UDim2 = engine.types.UDim2
				local space = themes.neutralPackage().metrics.space
				local row = root:FindFirstChild("Row"):FindFirstChild("Gap")
				Verify.expect(row:FindFirstChildWhichIsA("UIFlexItem").FlexMode):toBe(engine.types.Enum.UIFlexMode.Fill)
				Verify.expect((row:HasTag("facet-layout"))):toBe(true)
				Verify.expect(row.Size):toBe(UDim2.fromOffset(space.m, 0))
				floor:set("l")
				Verify.expect(row.Size):toBe(UDim2.fromOffset(space.l, 0))
				Verify.expect(root:FindFirstChild("Column"):FindFirstChild("Gap").Size):toBe(UDim2.fromOffset(0, 12))
				Verify.expect(root:FindFirstChild("Bare"):FindFirstChild("Gap").Size):toBe(UDim2.fromOffset(0, 0))
				stop()
			end,
		})

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

	verifyHarness:suite("native restored controls: floating plates", function()
		verifyHarness:case("outlines floating plates the way a menu plate is outlined in every shipped package", {
			id = "native_restored_controls::native restored controls: floating plates::outlines floating plates the way a menu plate is outlined in every shipped package",
			run = function()
				for _, entry in packages() do
					local sheet, stop = sheetOf(entry.package)
					local menu = style(sheet, ".facet-menu::UIStroke")
					local plate = style(sheet, ".facet-floating::UIStroke")
					Verify.expect(plate.Color):toBe(menu.Color)
					Verify.expect(plate.Thickness):toBe(menu.Thickness)
					Verify.expect(plate.Transparency):toBe(menu.Transparency)
					stop()
				end
			end,
		})
	end)
end
