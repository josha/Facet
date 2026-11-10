--!strict
local Verify = require("../tools/vendor/verify/src/core")
local styleProperties = require("./lib/style_properties")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type ReadOnlyValue<T> = typeof(require("@repo/src/vendor/compose/core").accumulator<<T, number>>(nil :: never))
	type Use = <T>(ReadOnlyValue<T>) -> T

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose
	local themes = Facet.themes
	local Roblox = require("./lib/native_engine").types

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

	local function make(options: { [string]: any }?): (engineLib.Engine, ComposeRuntime, Facet.Controls)
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local config: any = { types = engine.types, guiService = gui, services = { GuiService = gui } }
		for key, value in options or {} do
			config[key] = value
		end
		local controlOptions: Facet.ControlOptions = config
		return engine, runtime, Facet.controls(runtime, controlOptions)
	end

	local function build(
		options: { [string]: any }?,
		body: (Facet.Controls, Facet.Host) -> Instance
	): (any, engineLib.Engine, () -> ())
		local engine, runtime, UI = make(options)
		local root: any
		runtime.mount(function()
			root = body(UI, Facet.host(runtime))
			return root
		end, engine.new("ScreenGui"))
		return root, engine, function()
			runtime:dispose()
		end
	end

	local function refusal(body: (Facet.Controls, Facet.Host) -> Instance, options: { [string]: any }?): string?
		local engine, runtime, UI = make(options)
		local ok, message = pcall(function()
			runtime.mount(function()
				return body(UI, Facet.host(runtime))
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
				{ types = engine.types, preferredTransparency = 1, motionLevel = "normal" }
			)
		end, engine.new("Folder"))
		return sheet, function()
			runtime:dispose()
		end
	end

	local function style(sheet: any, selector: string): { [string]: any }
		for _, node in sheet:GetChildren() do
			if table.find(string.split(node.Selector, ", "), selector) ~= nil then
				return styleProperties(node)
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
				local root, _, stop = build(nil, function(UI)
					return UI.Text "Lap" { text = value, textRole = "title" }
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
					local root, _, stop = build(nil, function(UI)
						builds += 1
						local title: any = if form == "cell"
							then value
							elseif form == "formula" then Compose.formula(function(use: Use)
								return use(value)
							end)
							else function(use: any)
								return use(value)
							end
						return UI.Label "Lap" { title = title }
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
				local unknownIcon = refusal(function(UI)
					return UI.Label { title = "Saved", icon = "unknown-semantic-icon" }
				end)
				Verify.expect((mentions(unknownIcon, "unknown icon"))):toBe(true)
				local plainText = refusal(function(UI)
					local legacy: any = { text = "Saved" }
					local props: Facet.LabelProps = legacy
					return UI.Label(props)
				end)
				Verify.expect((mentions(plainText, "UI.Text"))):toBe(true)
			end,
		})

		verifyHarness:case("shows every standard glyph with its registry art", {
			id = "native_restored_controls::native restored controls: Label::shows every standard glyph with its registry art",
			run = function()
				local icons = require("../src/ui/icons")
				local StandardIcons = require("../examples/standard_icons")
				local theme = StandardIcons.apply(Facet.themes.neutralPackage())
				for name, art in icons.ART do
					local root, _, stop = build({ theme = theme }, function(UI)
						return UI.Label { title = name, icon = name }
					end)
					Verify.expect(root:FindFirstChild("Icon", true).Image):toBe(StandardIcons.CONTENT[name])
					Verify.expect(art.contentId):toBe(nil)
					stop()
				end
			end,
		})

		verifyHarness:case("sizes an icon Button caption like a text-only Button label", {
			id = "native_restored_controls::native restored controls: Label::sizes an icon Button caption like a text-only Button label",
			run = function()
				local root, _, stop = build(nil, function(UI, Host)
					return Host.Frame {
						UI.Button "Plain" { label = "Harvest all" },
						UI.Button "Iconic" { label = "Harvest all", icon = "checkmark" },
					}
				end)
				local title = root:FindFirstChild("Iconic"):FindFirstChild("Title", true)
				Verify.expect(title:HasTag("facet-type-control")):toBe(true)
				Verify.expect(title:HasTag("facet-type-body")):toBe(false)
				stop()
			end,
		})

		verifyHarness:case("draws a standard control glyph as strokes until the theme supplies its art", {
			id = "native_restored_controls::native restored controls: Label::draws a standard control glyph as strokes until the theme supplies its art",
			run = function()
				local root, _, stop = build(nil, function(UI)
					return UI.Label { title = "Saved", icon = "checkmark" }
				end)
				local function strokes(node: Instance): { Path2D }
					local found: { Path2D } = {}
					for _, child in node:GetChildren() do
						if child:IsA("Path2D") and child.Name == "Stroke" then
							table.insert(found, child)
						end
					end
					return found
				end
				local icon = root:FindFirstChild("Icon", true)
				Verify.expect(icon.Image):toBe("")
				Verify.expect(#strokes(icon)):toBe(1)
				Verify.expect(#strokes(icon)[1]:GetControlPoints()):toBe(3)
				stop()
				local StandardIcons = require("../examples/standard_icons")
				local themed, _, stopThemed = build(
					{ theme = StandardIcons.apply(Facet.themes.neutralPackage()) },
					function(UI)
						return UI.Label { title = "Saved", icon = "checkmark" }
					end
				)
				local art = themed:FindFirstChild("Icon", true)
				Verify.expect(art.Image):toBe(StandardIcons.CONTENT.checkmark)
				Verify.expect(#strokes(art)):toBe(0)
				stopThemed()
				local name = Compose.cell("chevron.down")
				local live, _, stopLive = build(nil, function(UI)
					return UI.Button { label = "More", icon = name }
				end)
				local liveIcon = live:FindFirstChild("LeadingIcon", true)
				local function tip(): number
					return math.round(strokes(liveIcon)[1]:GetControlPoints()[2].Position.Y.Scale * 100)
				end
				Verify.expect(tip()):toBe(66)
				name:set("chevron.up")
				Verify.expect(tip()):toBe(34)
				Verify.expect(#strokes(liveIcon)):toBe(1)
				stopLive()
				local unknown = refusal(function(UI)
					return UI.Label { title = "Kart", icon = "kart" }
				end)
				Verify.expect((mentions(unknown, "unknown icon 'kart'"))):toBe(true)
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
					{ spec = { aspectRatio = 0 }, fragment = "aspectRatio must be a number above zero" },
					{
						spec = { paintRect = { x0 = 16, y0 = 16, x1 = 376, y1 = 166 } },
						fragment = "paintRect = { x0, y0, x1, y1, width, height }",
					},
					{
						spec = { paintRect = { x0 = 16, y0 = 16, x1 = 400, y1 = 166, width = 392, height = 182 } },
						fragment = "inside an image of width by height",
					},
					{
						spec = { paintRect = { x0 = 60, y0 = 16, x1 = 60, y1 = 166, width = 392, height = 182 } },
						fragment = "rectangle of the paint",
					},
					{
						spec = {
							image = Compose.cell("rbxassetid://1"),
							paintRect = { x0 = 16, y0 = 16, x1 = 376, y1 = 166, width = 392, height = 182 },
						},
						fragment = "paintRect belongs to one image",
					},
					{
						spec = { shape = "circle" :: "circle", aspectRatio = 2 },
						fragment = "circle has its own aspect ratio",
					},
				}
				for _, case in cases do
					Verify.expect((mentions(
						refusal(function(UI)
							return UI.Image(case.spec)
						end),
						case.fragment
					))):toBe(true)
				end
				local mode = Compose.cell("fit" :: "crop" | "fill" | "fit" | "slice" | "stretch" | "tile")
				local root, engine, stop = build(nil, function(UI)
					return UI.Image { scaleMode = mode }
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

	verifyHarness:suite("native restored controls: Image paint", function()
		verifyHarness:case("records paintRect on the ImageLabel for the review", {
			id = "native_restored_controls::native restored controls: Image paint::records paintRect on the ImageLabel for the review",
			run = function()
				local card, engine, stopCard = build(nil, function(UI)
					return UI.Image {
						image = "rbxassetid://1",
						scaleMode = "stretch" :: "stretch",
						paintRect = { x0 = 16, y0 = 16, x1 = 376, y1 = 166, width = 392, height = 182 },
					}
				end)
				Verify.expect(card:GetAttribute("FacetPaintRect")):toBe(engine.types.Rect.new(16, 16, 376, 166))
				Verify.expect(card:GetAttribute("FacetSourceSize")):toBe(engine.types.Vector2.new(392, 182))
				stopCard()
				local plain, _, stopPlain = build(nil, function(UI)
					return UI.Image { image = "rbxassetid://1" }
				end)
				Verify.expect(plain:GetAttribute("FacetPaintRect")):toBe(nil)
				Verify.expect(plain:GetAttribute("FacetSourceSize")):toBe(nil)
				stopPlain()
			end,
		})
	end)

	verifyHarness:suite("native restored controls: Image size", function()
		verifyHarness:case("takes its size from width, height and aspectRatio", {
			id = "native_restored_controls::native restored controls: Image size::takes its size from width, height and aspectRatio",
			run = function()
				local band, engine, stopBand = build(nil, function(UI)
					return UI.Image { image = "rbxassetid://1", width = "fill" :: "fill", height = 120 }
				end)
				local D2, E = engine.types.UDim2, engine.types.Enum
				Verify.expect(band.Size):toBe(D2.new(1, 0, 0, 120))
				Verify.expect(band:FindFirstChildWhichIsA("UIAspectRatioConstraint")):toBe(nil)
				stopBand()
				local card, _, stopCard = build(nil, function(UI)
					return UI.Image { image = "rbxassetid://1", width = 150, aspectRatio = 0.5 }
				end)
				Verify.expect(card.Size):toBe(D2.new(0, 150, 0, 300))
				local held = card:FindFirstChildWhichIsA("UIAspectRatioConstraint")
				Verify.expect(held.AspectRatio):toBe(0.5)
				Verify.expect(held.DominantAxis):toBe(E.DominantAxis.Width)
				Verify.expect(held.AspectType):toBe(E.AspectType.FitWithinMaxSize)
				stopCard()
				local tall, _, stopTall = build(nil, function(UI)
					return UI.Image { image = "rbxassetid://1", height = "fill" :: "fill", aspectRatio = 2 }
				end)
				Verify.expect(tall.Size):toBe(D2.new(1, 0, 1, 0))
				local led = tall:FindFirstChildWhichIsA("UIAspectRatioConstraint")
				Verify.expect(led.DominantAxis):toBe(E.DominantAxis.Height)
				Verify.expect(led.AspectType):toBe(E.AspectType.ScaleWithParentSize)
				stopTall()
				local alone, _, stopAlone = build(nil, function(UI)
					return UI.Image { image = "rbxassetid://1", aspectRatio = 2 }
				end)
				Verify.expect(alone.Size.Y.Offset > 0):toBe(true)
				Verify.expect(alone.Size.X.Offset):toBe(alone.Size.Y.Offset * 2)
				stopAlone()
				local wide = Compose.cell(72 :: "fill" | number)
				local live, _, stopLive = build(nil, function(UI)
					return UI.Image { image = "rbxassetid://1", width = wide, aspectRatio = 0.5 }
				end)
				Verify.expect(live.Size):toBe(D2.new(0, 72, 0, 144))
				wide:set(150)
				Verify.expect(live.Size):toBe(D2.new(0, 150, 0, 300))
				wide:set("fill")
				Verify.expect(live.Size):toBe(D2.new(1, 0, 1, 0))
				Verify.expect(live:FindFirstChildWhichIsA("UIAspectRatioConstraint").AspectType)
					:toBe(E.AspectType.ScaleWithParentSize)
				stopLive()
			end,
		})
	end)

	verifyHarness:suite("native restored controls: bare Button", function()
		verifyHarness:case("has the size of its face, with no plate and no label", {
			id = "native_restored_controls::native restored controls: bare Button::has the size of its face, with no plate and no label",
			run = function()
				local root, engine, stop = build(nil, function(UI)
					return UI.Button "Piece" {
						appearance = "bare",
						name = "Piece",
						UI.Image "Face" { image = "rbxassetid://1", width = 40, height = 56 },
					}
				end)
				Verify.expect((root:HasTag("facet-appearance-bare"))):toBe(true)
				Verify.expect(root.Size):toBe(engine.types.UDim2.new())
				Verify.expect(root.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.XY)
				Verify.expect(root.BackgroundTransparency):toBe(1)
				Verify.expect(root:FindFirstChild("Face", true) ~= nil):toBe(true)
				stop()
				local plain, _, stopPlain = build(nil, function(UI)
					return UI.Button "Deal" { label = "Deal" }
				end)
				Verify.expect((plain:HasTag("facet-appearance-bare"))):toBe(false)
				stopPlain()
			end,
		})
	end)

	verifyHarness:suite("native restored controls: Divider", function()
		verifyHarness:case("uses the theme hairline weight by default and accepts pixels or a metric name", {
			id = "native_restored_controls::native restored controls: Divider::uses the theme hairline weight by default and accepts pixels or a metric name",
			run = function()
				local theme = Compose.cell(themes.neutralPackage())
				local root, engine, stop = build({ theme = theme }, function(UI)
					return UI.VStack {
						UI.Divider "Default" {},
						UI.Divider "Pixels" { thickness = 3 },
						UI.Divider "Step" { thickness = "xs" },
					}
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
				local zeroThickness = refusal(function(UI)
					return UI.Divider { thickness = 0 }
				end)
				Verify.expect((mentions(zeroThickness, "positive number"))):toBe(true)
			end,
		})

		verifyHarness:case("leaves its transparency at the class default so the divider rule paints the line", {
			id = "native_restored_controls::native restored controls: Divider::leaves its transparency at the class default so the divider rule paints the line",
			run = function()
				local root, _, stop = build(nil, function(UI)
					return UI.Divider {}
				end)
				Verify.expect(root.BackgroundTransparency):toBe(0)
				Verify.expect(root.BorderSizePixel):toBe(0)
				stop()
				Verify.expect((mentions(
					refusal(function(UI)
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
						local grounds: { Color3 } = {
							style(sheet, ".facet-level-segment").BackgroundColor3,
							style(sheet, ".facet-pane").BackgroundColor3,
						}
						for _, ground in grounds do
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
				local root, engine, stop = build(nil, function(UI)
					return UI.HStack {
						UI.Spacer "Gap" { Size = Roblox.UDim2.fromOffset(40, 4), minLength = 8 },
					}
				end)
				Verify.expect(root:FindFirstChild("Gap").Size):toBe(engine.types.UDim2.fromOffset(40, 4))
				stop()
				for _, value in { -1, "huge" } :: { any } do
					Verify.expect(refusal(function(UI)
						return UI.HStack { UI.Spacer { minLength = value } }
					end) ~= nil):toBe(true)
				end
			end,
		})
	end)

	verifyHarness:suite("native restored controls: floating plates", function() end);
	(function(verifyHarness: Verify.Harness)
		type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
		type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)

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

		local function setup(
			build: (Facet.Controls, Facet.Host, engineLib.Engine) -> Facet.Child,
			options: { [string]: any }?
		): World
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
			local config: any = {
				types = engine.types,
				guiService = gui,
				services = { GuiService = gui, UserInputService = input },
				motionLevel = "none",
			}
			for key, value in options or {} do
				config[key] = value
			end
			local controlOptions: Facet.ControlOptions = config
			local UI = Facet.controls(runtime, controlOptions)
			local Host = Facet.host(runtime)
			local stop, root: any = runtime.mount(function()
				return Host.ScreenGui { build(UI, Host, engine) }
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

		local StandardIcons = require("../examples/standard_icons")
		local function glyph(name: string): string?
			local icon = themes.resolveIcon(StandardIcons.apply(themes.neutralPackage()), name)
			return if type(icon) == "string" then icon else nil
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
					local theme = Compose.cell(StandardIcons.apply(themes.neutralPackage()))
					local world = setup(function(UI)
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
						theme:set(StandardIcons.apply((require :: any)("../examples/themes/" .. name).build(themes)))
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
