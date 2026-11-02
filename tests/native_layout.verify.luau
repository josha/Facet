--!strict
type Sides = typeof(require("@repo/tools/typecheck/aliases").Sides)
local Verify = require("../tools/vendor/verify/src/core")
local Bdd = require("../tools/vendor/verify/src/bdd")
local VerifyRoblox = require("../tools/vendor/verify/src/roblox")
local ThemeTypes = require("../src/ui/theme_types")
local EnvironmentTypes = require("../src/ui/environment_types")
local SharedTypes = require("../src/ui/types")
local Facet = require("../src")

return function(verifyHarness: Verify.Harness)
	local test = Bdd.create(verifyHarness)
	local describe, it, expect = test.describe, test.it, test.expect
	type ComposeModule = typeof(require("../src/vendor/compose/core"))
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FacetControls = Facet.Controls
	type RobloxHost = Facet.Host
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	local ComposeTypes = require("../src/vendor/compose/core")
	type Use = ComposeTypes.Use
	type GlassBands = { width: number, height: number, top: number, left: number, bottom: number, right: number }

	local engineLib = require("./lib/native_engine")
	local cells = require("./lib/cells")
	local Compose: ComposeModule = Facet.Compose

	local function make(options: { [string]: any }?, engineOptions: engineLib.Options?)
		local engine, fixture = engineLib.new(engineOptions)
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = (engine.new("GuiService") :: unknown) :: GuiService
		engine.environment.fakeOn(VerifyRoblox.assertInstance(gui), "GetGuiInset", function()
			return engine.types.Vector2.zero, engine.types.Vector2.zero
		end)
		local config: { [string]: any } = { types = engine.types, guiService = gui, services = { GuiService = gui } }
		if engineOptions then
			config.services = { GuiService = gui, RunService = { Heartbeat = engine.heartbeat } }
		end
		for key, value in (options or {}) :: { [string]: any } do
			config[key] = value
		end
		return engine, runtime, Facet.controls(runtime, config :: any), fixture
	end

	local function build(
		options: { [string]: any }?,
		body: (FacetControls, RobloxHost) -> ComposeTypes.Child,
		engineOptions: engineLib.Options?
	): (any, any, () -> (), any)
		local engine, runtime, UI = make(options, engineOptions)
		local root: any
		local unmount = runtime.mount(function()
			root = body(UI, Facet.host(runtime))
			return root
		end, engine.new("ScreenGui"))
		return root, engine, function()
			unmount()
			runtime:dispose()
		end, runtime
	end

	local function child(node: any, className: string): any
		return node:FindFirstChildWhichIsA(className)
	end

	local function refusal(body: (FacetControls, RobloxHost) -> ComposeTypes.Node): string?
		local engine, runtime, UI = make()
		local ok, message = pcall(function()
			runtime.mount(function()
				return body(UI, Facet.host(runtime))
			end, engine.new("ScreenGui"))
		end)
		runtime:dispose()
		return if ok then nil else tostring(message)
	end

	local function painted(root: any): string
		local nodes: { TextLabel } = {}
		for _, node in root:GetChildren() do
			if node:IsA("GuiObject") then
				table.insert(nodes, node)
			end
		end
		table.sort(nodes, function(a: TextLabel, b: TextLabel)
			return a.LayoutOrder < b.LayoutOrder
		end)
		local texts = {}
		for at, node in nodes do
			table.insert(
				texts,
				if at > 1 and nodes[at - 1].LayoutOrder == node.LayoutOrder then "=" .. node.Text else node.Text
			)
		end
		return table.concat(texts, " ")
	end

	local function mentions(message: string?, fragment: string): boolean
		return message ~= nil and string.find(message, fragment, 1, true) ~= nil
	end

	describe("native composition rest measurements", function()
		it("sizes a simplified Region without an automatic parent and hit target feedback loop", {
			id = "native_layout::native composition rest measurements::sizes a simplified Region without an automatic parent and hit target feedback loop",
			run = function()
				local root, engine, stop = build(nil, function(UI, Host)
					return UI.Composition {
						UI.Region "Health" {
							zone = "bottomLeft" :: "bottomLeft",
							rank = 1,
							Host.Frame "Full" {},
							Host.Frame "Compact" {},
						},
					}
				end)
				local region = root:FindFirstChild("Health", true)
				local full, compact = region:FindFirstChild("Full", true), region:FindFirstChild("Compact", true)
				local V2 = engine.types.Vector2
				engine.environment.poke(full, "AbsoluteSize", V2.new(147, 26))
				engine.environment.poke(compact, "AbsoluteSize", V2.new(32, 20))
				engine.environment.poke(root:FindFirstChild("Zones"), "AbsoluteSize", V2.new(80, 200))
				expect(region:GetAttribute("FacetForm")):toBe(2)
				engine.environment.poke(compact, "AbsoluteSize", V2.new(39, 26))
				expect(region.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.None)
				expect(region.Size):toBe(engine.types.UDim2.fromOffset(44, 44))
				local trigger = region:FindFirstChildWhichIsA("TextButton", true)
				expect(trigger.Size):toBe(engine.types.UDim2.fromScale(1, 1))
				engine.environment.poke(root:FindFirstChild("Zones"), "AbsoluteSize", V2.new(1079, 745))
				engine.environment.poke(root:FindFirstChild("Zones"), "AbsoluteSize", V2.new(80, 200))
				expect(region.Size):toBe(engine.types.UDim2.fromOffset(44, 44))
				stop()
			end,
		})
		it("sizes wrapped Text to its text in a hugging row and to the width of a stack", {
			id = "native_layout::native composition rest measurements::sizes wrapped Text to its text in a hugging row and to the width of a stack",
			run = function()
				local root, engine, stop = build(nil, function(UI)
					return UI.VStack "Page" {
						UI.HStack "Hud" { UI.Text "Menu" { text = "Menu", wrap = true } },
						UI.VStack "Body" { UI.Text "Copy" { text = "A longer paragraph", wrap = true } },
					}
				end)
				local E, D2 = engine.types.Enum, engine.types.UDim2
				local menu = root:FindFirstChild("Menu", true)
				local copy = root:FindFirstChild("Copy", true)
				expect(menu.Size):toBe(D2.fromScale(0, 0))
				expect(menu.AutomaticSize):toBe(E.AutomaticSize.XY)
				expect(menu.TextWrapped):toBe(true)
				expect(copy.Size):toBe(D2.fromScale(1, 0))
				expect(copy.AutomaticSize):toBe(E.AutomaticSize.Y)
				stop()
			end,
		})
		it("keeps a simplified Region rectangle after a scaled viewport round trip", {
			id = "native_layout::native composition rest measurements::keeps a simplified Region rectangle after a scaled viewport round trip",
			run = function()
				local root, engine, stop = build(nil, function(UI, Host)
					return UI.Composition {
						UI.Region "Health" {
							zone = "bottomLeft" :: "bottomLeft",
							rank = 1,
							Host.Frame "Full" {},
							Host.Frame "Compact" {},
						},
					}
				end)
				local region = root:FindFirstChild("Health", true)
				local full, compact = region:FindFirstChild("Full", true), region:FindFirstChild("Compact", true)
				local V2 = engine.types.Vector2
				engine.environment.poke(
					root:FindFirstChild("Zones"):FindFirstChild("LayoutUnit"),
					"AbsoluteSize",
					V2.new(100, 1)
				)
				engine.environment.poke(full, "AbsoluteSize", V2.new(90, 35))
				engine.environment.poke(compact, "AbsoluteSize", V2.new(41.5, 35))
				engine.environment.poke(root:FindFirstChild("Zones"), "AbsoluteSize", V2.new(80, 200))
				expect(region:GetAttribute("FacetForm")):toBe(2)
				local trigger = region:FindFirstChildWhichIsA("TextButton", true)
				local initial = trigger.Size
				for _, unit in { 0.94, 0.5, 1 } do
					local a, b = full:FindFirstChild("LayoutUnit"), compact:FindFirstChild("LayoutUnit")
					if a then
						engine.environment.poke(a, "AbsoluteSize", V2.new(100 * unit, unit))
					end
					if b then
						engine.environment.poke(b, "AbsoluteSize", V2.new(100 * unit, unit))
					end
					engine.environment.poke(full, "AbsoluteSize", V2.new(90 * unit, 35 * unit))
					engine.environment.poke(compact, "AbsoluteSize", V2.new(41.5 * unit, 35 * unit))
					expect(region:GetAttribute("FacetForm")):toBe(2)
					expect(trigger.Size):toBe(initial)
				end
				stop()
			end,
		})
	end)

	describe("stack surfaces", function()
		it("paints a stack with the named theme plate and rejects an unknown surface", {
			id = "native_layout::stack surfaces::paints a stack with the named theme plate and rejects an unknown surface",
			run = function()
				local root, _, stop = build(nil, function(UI)
					return UI.VStack "Readouts" { surface = "panel", padding = "s" }
				end)
				expect(table.find(root:GetTags(), "facet-panel") ~= nil):toBe(true)
				stop()
				local plain, _, stopPlain = build(nil, function(UI)
					return UI.HStack "Row" {}
				end)
				expect(table.find(plain:GetTags(), "facet-panel")):toBe(nil)
				stopPlain()
				local ok, problem = true, ""
				local _, _, stopBad = build(nil, function(UI)
					ok, problem = pcall(function()
						UI.VStack { surface = "glass" :: any }
					end)
					return UI.VStack {}
				end)
				stopBad()
				expect(ok):toBe(false)
				expect(string.find(tostring(problem), "surface must be", 1, true) ~= nil):toBe(true)
			end,
		})
	end)

	describe("stack stretch matching", function()
		it("gives the children of a hugging stretch stack the width of the widest one", {
			id = "native_layout::stack stretch matching::gives the children of a hugging stretch stack the width of the widest one",
			run = function()
				local root, engine, stop = build(nil, function(UI, Host)
					return UI.VStack {
						align = "stretch",
						Host.Frame { Name = "Row", Host.Frame { Name = "RowInner" } },
						Host.Frame { Name = "Other", Host.Frame { Name = "OtherInner" } },
					}
				end, {})
				local E, V = engine.types.Enum, engine.types.Vector2
				local list = child(root, "UIListLayout")
				local row, other = root:FindFirstChild("Row"), root:FindFirstChild("Other")
				row.AutomaticSize, other.AutomaticSize = E.AutomaticSize.XY, E.AutomaticSize.XY
				local function floor(node: Instance): number
					local match = node:FindFirstChild("Lift") :: UISizeConstraint?
					return if match then match.MinSize.X else 0
				end
				local inners: { [Instance]: number } = {}
				local function place(node: Instance, width: number)
					local holder = (node :: unknown) :: { AbsoluteSize: Vector2 }
					if holder.AbsoluteSize.X ~= width then
						engine.environment.poke(node, "AbsoluteSize", V.new(width, 20))
					end
				end
				local function size(node: Instance, inner: number, outer: number)
					local holder = node :: Frame
					local content = holder:FindFirstChildWhichIsA("Frame") :: Frame
					inners[node] = inner
					engine.environment.poke(content, "AbsoluteSize", V.new(inner, 20))
					place(node, outer)
				end
				local function settle()
					for _ = 1, 8 do
						engine.heartbeat:Fire(1 / 60)
						for node, inner in inners do
							place(node, math.max(inner, floor(node)))
						end
					end
				end
				expect(list.HorizontalFlex):toBe(E.UIFlexAlignment.None)
				size(row, 80, 80)
				size(other, 50, 50)
				settle()
				expect(floor(other)):toBe(80)
				expect(floor(row)):toBe(0)
				size(other, 50, 80)
				settle()
				expect(floor(other)):toBe(80)
				size(row, 30, 30)
				settle()
				expect(floor(row)):toBe(50)
				expect(floor(other)):toBe(0)
				stop()
			end,
		})
		it("matches lifted children from settled readings through growth and shrinking", {
			id = "native_layout::stack stretch matching::matches lifted children from settled readings through growth and shrinking",
			run = function()
				local extentMatch = require("../src/ui/extent_match")
				type Member = { content: number, padding: number, overshoot: number, lift: number, shown: number }
				local function layout(m: Member): number
					return math.max(m.content + m.padding, if m.lift > 0 then m.lift + m.overshoot else 0)
				end
				local state = extentMatch.new()
				local coin: Member = { content = 91, padding = 0, overshoot = 36, lift = 0, shown = 91 }
				local button: Member = { content = 87.5, padding = 16, overshoot = 16, lift = 0, shown = 40 }
				local padding = button.padding
				button.padding = -15.5
				local members = { coin, button }
				local widest = 0
				local function settle(): number
					for frame = 1, 80 do
						local measured: { [unknown]: number } = {}
						local content: { [unknown]: number } = {}
						for _, m in members do
							measured[m] = m.shown
							content[m] = m.content
						end
						local mins, settled = extentMatch.step(state, members, measured, content)
						for _, m in members do
							m.shown = layout(m)
							m.lift = mins[m] or 0
							widest = math.max(widest, m.shown)
						end
						if settled and frame > 4 then
							return frame
						end
					end
					return math.huge
				end
				expect(settle() < 80):toBe(true)
				button.padding = padding
				expect(settle() < 80):toBe(true)
				expect(layout(coin)):toBe(103.5)
				expect(layout(button)):toBe(103.5)
				coin.content = 178
				expect(settle() < 80):toBe(true)
				expect(layout(coin)):toBe(178)
				expect(layout(button)):toBe(178)
				expect(widest < 200):toBe(true)
				coin.content = 30
				expect(settle() < 80):toBe(true)
				expect(layout(coin)):toBe(103.5)
				expect(layout(button)):toBe(103.5)
				button.content = 140
				expect(settle() < 80):toBe(true)
				expect(layout(coin)):toBe(156)
				expect(layout(button)):toBe(156)
				expect(widest < 200):toBe(true)
			end,
		})
		it("matches the steady children while another one keeps changing", {
			id = "native_layout::stack stretch matching::matches the steady children while another one keeps changing",
			run = function()
				local extentMatch = require("../src/ui/extent_match")
				local state = extentMatch.new()
				local narrow, wide, pulsing = {}, {}, {}
				local members = { narrow, wide, pulsing }
				local lift = 0
				for frame = 1, 40 do
					local mins = extentMatch.step(
						state,
						members,
						{ [narrow] = math.max(50, lift), [wide] = 80, [pulsing] = 10 + frame % 2 },
						{ [narrow] = 50, [wide] = 80, [pulsing] = 10 + frame % 2 }
					)
					lift = mins[narrow] or 0
				end
				expect(lift):toBe(80)
			end,
		})
		it("stretches a fixed-width stack natively", {
			id = "native_layout::stack stretch matching::stretches a fixed-width stack natively",
			run = function()
				local root, engine, stop = build(nil, function(UI, Host)
					return UI.VStack { align = "stretch", width = 200, Host.Frame { Name = "Row" } }
				end, {})
				expect(child(root, "UIListLayout").HorizontalFlex):toBe(engine.types.Enum.UIFlexAlignment.Fill)
				stop()
			end,
		})
	end)

	describe("stack surface corners", function()
		local function insets(make: (FacetControls) -> Instance): string
			local root, _, stop = build(nil, function(UI)
				return make(UI)
			end)
			local padding = child(root, "UIPadding")
			local function side(value: UDim): string
				return if value.Scale ~= 0 then tostring(value.Scale) else tostring(value.Offset)
			end
			local text = if padding
				then `{side(padding.PaddingTop)} {side(padding.PaddingRight)} {side(padding.PaddingBottom)} {side(
					padding.PaddingLeft
				)}`
				else "none"
			stop()
			return text
		end
		local function pill(UI: FacetControls): Instance
			return UI.VStack "Tag" {
				surface = "panel",
				padding = { top = 4, bottom = 4, left = 8, right = 8 } :: Sides,
			}
		end

		it("widens a rounded surface's longer padding to its corner radius so content clears the curve", {
			id = "native_layout::stack surface corners::widens a rounded surface's longer padding to its corner radius so content clears the curve",
			run = function()
				expect(insets(pill)):toBe("4 12 4 12")
				expect(insets(function(UI): Instance
					return UI.HStack "Steps" {
						surface = "panel",
						padding = { top = "xs", bottom = "xs", left = "s", right = "s" },
					}
				end)):toBe("4 12 4 12")
				expect(insets(function(UI): Instance
					return UI.HStack "Square" { surface = "panel", padding = 6 }
				end)):toBe("6 12 6 12")
				expect(insets(function(UI): Instance
					return UI.VStack "Tall" {
						surface = "panel",
						padding = { top = 8, bottom = 8, left = 4, right = 4 } :: Sides,
					}
				end)):toBe("12 4 12 4")
				expect(insets(function(UI): Instance
					return UI.HStack "Chip" { surface = "surface", padding = 4 }
				end)):toBe("4 8 4 8")
			end,
		})

		it("keeps the padding of a surface that already clears its corners, bleeds or has no corners", {
			id = "native_layout::stack surface corners::keeps the padding of a surface that already clears its corners, bleeds or has no corners",
			run = function()
				local cases: { [string]: (FacetControls) -> Instance } = {
					["12 12 12 12"] = function(UI): Instance
						return UI.VStack "Roomy" { surface = "panel", padding = 12 }
					end,
					["16 4 16 4"] = function(UI): Instance
						return UI.VStack "Deep" {
							surface = "panel",
							padding = { top = 16, bottom = 16, left = 4, right = 4 } :: Sides,
						}
					end,
					["0 0 0 0"] = function(UI): Instance
						return UI.VStack "Bleed" { surface = "panel", padding = 0 }
					end,
					["4 4 4 4"] = function(UI): Instance
						return UI.VStack "Pane" { surface = "pane", padding = 4 }
					end,
					none = function(UI): Instance
						return UI.VStack "Bare" { surface = "panel" }
					end,
				}
				for expected, make in cases do
					expect(insets(make)):toBe(expected)
				end
				expect(insets(function(UI): Instance
					return UI.VStack "Plain" { padding = 4 }
				end)):toBe("4 4 4 4")
			end,
		})
	end)

	describe("stack corners option", function()
		type Corners = number | "pill" | "square" | "control" | "panel"
		local function measure(root: Instance): string
			local found = child(root, "UICorner")
			local padding = child(root, "UIPadding")
			local parts = { if found then `{found.CornerRadius.Scale},{found.CornerRadius.Offset}` else "theme" }
			for _, side in { "PaddingTop", "PaddingRight", "PaddingBottom", "PaddingLeft" } do
				table.insert(parts, if padding then tostring(padding[side].Offset) else "-")
			end
			return table.concat(parts, " ")
		end
		local function shaped(make: (FacetControls) -> Instance): string
			local root, _, stop = build(nil, function(UI)
				return make(UI)
			end)
			local text = measure(root)
			stop()
			return text
		end

		it("rounds a pill plate and grows its long sides to half its short side", {
			id = "native_layout::stack corners option::rounds a pill plate and grows its long sides to half its short side",
			run = function()
				local root, engine, stop = build(nil, function(UI)
					return UI.HStack "Readout" {
						surface = "panel",
						corners = "pill",
						padding = { top = 4, bottom = 4, left = 8, right = 8 } :: Sides,
					}
				end)
				local V2 = engine.types.Vector2
				expect(measure(root)):toBe("1,0 4 8 4 8")
				engine.environment.poke(root, "AbsoluteSize", V2.new(96, 28))
				expect(measure(root)):toBe("1,0 4 14 4 14")
				engine.environment.poke(root, "AbsoluteSize", V2.new(28, 96))
				expect(measure(root)):toBe("1,0 14 8 14 8")
				stop()
			end,
		})

		it("keeps a pill plate as round as a pill Button when the theme has square pills", {
			id = "native_layout::stack corners option::keeps a pill plate as round as a pill Button when the theme has square pills",
			run = function()
				local square = Facet.themes.neutralPackage()
				square.metrics.radii.pill = 0
				local root, engine, stop = build({ theme = square }, function(UI)
					return UI.HStack "Row" {
						surface = "panel",
						corners = "pill",
						UI.Button "Boost" { label = "Boost", corners = "pill" },
					}
				end)
				local plate = child(root, "UICorner")
				local button = child(root:FindFirstChild("Boost"), "UICorner")
				expect(plate.CornerRadius):toBe(engine.types.UDim.new(1, 0))
				expect(plate.CornerRadius):toBe(button.CornerRadius)
				stop()
			end,
		})

		it("takes a theme radius name or a pixel radius and clears content from it", {
			id = "native_layout::stack corners option::takes a theme radius name or a pixel radius and clears content from it",
			run = function()
				expect(shaped(function(UI): Instance
					return UI.HStack "Wide" {
						surface = "surface",
						corners = "panel",
						padding = { top = 4, bottom = 4, left = 8, right = 8 } :: Sides,
					}
				end)):toBe("0,12 4 12 4 12")
				expect(shaped(function(UI): Instance
					return UI.HStack "Tight" {
						surface = "panel",
						corners = "control",
						padding = { top = 4, bottom = 4, left = 8, right = 8 } :: Sides,
					}
				end)):toBe("0,8 4 8 4 8")
				expect(shaped(function(UI): Instance
					return UI.HStack "Tile" { surface = "pane", corners = 10, padding = 4 }
				end)):toBe("0,10 4 10 4 10")
				expect(shaped(function(UI): Instance
					return UI.HStack "Flat" {
						surface = "panel",
						corners = "square",
						padding = { top = 4, bottom = 4, left = 8, right = 8 } :: Sides,
					}
				end)):toBe("0,0 4 8 4 8")
				expect(shaped(function(UI): Instance
					return UI.VStack "Bare" { surface = "panel", corners = 6 }
				end)):toBe("0,6 - - - -")
			end,
		})

		it("keeps the theme corner and padding of a stack without corners", {
			id = "native_layout::stack corners option::keeps the theme corner and padding of a stack without corners",
			run = function()
				local root, _, stop = build(nil, function(UI)
					return UI.HStack "Steps" {
						surface = "panel",
						padding = { top = 4, bottom = 4, left = 8, right = 8 } :: Sides,
					}
				end)
				expect(measure(root)):toBe("theme 4 12 4 12")
				expect(root:FindFirstChild("CornerUnit")):toBe(nil)
				stop()
				expect(shaped(function(UI): Instance
					return UI.VStack "Pane" { surface = "pane", padding = 4 }
				end)):toBe("theme 4 4 4 4")
			end,
		})

		it("follows a corners cell with the corner and the padding", {
			id = "native_layout::stack corners option::follows a corners cell with the corner and the padding",
			run = function()
				local corners = Compose.cell("panel" :: Corners)
				local root, engine, stop = build(nil, function(UI)
					return UI.HStack "Live" {
						surface = "panel",
						corners = corners,
						padding = { top = 4, bottom = 4, left = 8, right = 8 } :: Sides,
					}
				end)
				expect(measure(root)):toBe("0,12 4 12 4 12")
				corners:set("square")
				expect(measure(root)):toBe("0,0 4 8 4 8")
				engine.environment.poke(root, "AbsoluteSize", engine.types.Vector2.new(96, 30))
				corners:set("pill")
				expect(measure(root)):toBe("1,0 4 15 4 15")
				stop()
			end,
		})

		it("follows the theme radius of a corners name when the theme changes", {
			id = "native_layout::stack corners option::follows the theme radius of a corners name when the theme changes",
			run = function()
				local theme = Compose.cell(Facet.themes.neutralPackage())
				local root, _, stop = build({ theme = theme }, function(UI)
					return UI.HStack "Themed" {
						surface = "surface",
						corners = "panel",
						padding = { top = 4, bottom = 4, left = 8, right = 8 } :: Sides,
					}
				end)
				expect(measure(root)):toBe("0,12 4 12 4 12")
				local rounder = Facet.themes.neutralPackage()
				rounder.metrics.radii.panel = 20
				theme:set(rounder)
				expect(measure(root)):toBe("0,20 4 20 4 20")
				expect(root:FindFirstChild("CornerUnit")):toBe(nil)
				stop()
			end,
		})

		it("refuses corners without a surface and an unknown corner value", {
			id = "native_layout::stack corners option::refuses corners without a surface and an unknown corner value",
			run = function()
				local bare = refusal(function(UI): Instance
					return UI.VStack "Bare" { corners = "pill" }
				end)
				expect(mentions(bare, "corners need a surface")):toBe(true)
				local odd = refusal(function(UI): Instance
					return UI.VStack "Odd" { surface = "panel", corners = ("round" :: unknown) :: number }
				end)
				expect(mentions(odd, "corners must be pill, square, control, panel")):toBe(true)
				local negative = refusal(function(UI): Instance
					return UI.VStack "Negative" { surface = "panel", corners = -2 }
				end)
				expect(mentions(negative, "corners must be pill, square, control, panel")):toBe(true)
			end,
		})
	end)

	describe("stack surface chrome and status", function()
		type Status = "neutral" | "info" | "success" | "warning" | "error" | "accent" | "voice" | "contrast"
		local styleRules = require("./lib/style_rules")

		it("gives a panel stack the theme's panel chrome, such as its shadow", {
			id = "native_layout::stack surface chrome and status::gives a panel stack the theme's panel chrome, such as its shadow",
			run = function()
				local package = Facet.themes.neutralPackage()
				assert(package.chrome).panel = { kind = "native" :: "native", shadow = "raised" }
				local panel, _, stop = build({ theme = package }, function(UI)
					return UI.VStack "Card" { surface = "panel", padding = "m", UI.Text { text = "A" } }
				end)
				expect(panel:FindFirstChildWhichIsA("UIShadow") ~= nil):toBe(true)
				stop()
				local plain, _, stopPlain = build({ theme = package }, function(UI)
					return UI.VStack "Plain" { padding = "m", UI.Text { text = "A" } }
				end)
				expect(plain:FindFirstChildWhichIsA("UIShadow")):toBe(nil)
				stopPlain()
				local bare, _, stopBare = build(nil, function(UI)
					return UI.VStack "Bare" { surface = "panel", padding = "m", UI.Text { text = "A" } }
				end)
				expect(bare:FindFirstChildWhichIsA("UIShadow")):toBe(nil)
				stopBare()
			end,
		})

		it("tints a status stack and the text, icons and progress inside it, and follows a status change", {
			id = "native_layout::stack surface chrome and status::tints a status stack and the text, icons and progress inside it, and follows a status change",
			run = function()
				local status = Compose.cell("warning" :: Status?)
				local root, engine, stop, runtime = build(nil, function(UI)
					return UI.VStack "Tag" {
						surface = "panel",
						status = status,
						padding = "s",
						UI.VStack "Inner" {
							UI.Text "Count" { text = "5 / 20" },
							UI.ProgressView "Bin" { value = 0.5 },
						},
					}
				end)
				local _, sheet = runtime.mount(function()
					return Facet.themes.createStyleSheet(
						runtime,
						Facet.themes.neutralPackage(),
						{ types = engine.types }
					)
				end, engine.new("Folder"))
				local count = root:FindFirstChild("Count", true)
				local fill = root:FindFirstChild("Fill1", true)
				expect(root:HasTag("facet-status-surface")):toBe(true)
				expect(root:HasTag("facet-status-warning")):toBe(true)
				expect(styleRules.resolve(sheet, root, "BackgroundColor3")):toBe("$FacetColor_warning")
				expect(styleRules.resolve(sheet, count, "TextColor3")):toBe("$FacetColor_onWarning")
				expect(styleRules.resolve(sheet, fill, "BackgroundColor3")):toBe("$FacetColor_onWarning")
				status:set("success")
				expect(root:HasTag("facet-status-warning")):toBe(false)
				expect(styleRules.resolve(sheet, count, "TextColor3")):toBe("$FacetColor_onSuccess")
				status:set(nil)
				expect(root:HasTag("facet-status-surface")):toBe(false)
				expect(root:HasTag("facet-status-success")):toBe(false)
				expect(styleRules.resolve(sheet, count, "TextColor3")):toBe("$FacetColor_content")
				stop()
			end,
		})
	end)

	describe("phone layout policy", function()
		it("reserves a visible horizontal scroll hint below overflowing genre chips", {
			id = "native_layout::phone layout policy::reserves a visible horizontal scroll hint below overflowing genre chips",
			run = function()
				for _, width in { 320, 360, 375, 389, 430 } do
					local root, engine, stop = build(nil, function(UI)
						local chip: Facet.ChipCellProps = { label = "Adventure", selected = Compose.cell(false) }
						return UI.ScrollView {
							axis = "x" :: "x",
							ScrollBarThickness = 2,
							UI.Chip(chip),
						}
					end)
					engine.environment.poke(root, "AbsoluteWindowSize", engine.types.Vector2.new(width, 36))
					engine.environment.poke(
						root:FindFirstChildWhichIsA("UIListLayout"),
						"AbsoluteContentSize",
						engine.types.Vector2.new(750, 36)
					)
					local hint = root:FindFirstChild("ScrollBarRoom")
					expect(hint ~= nil):toBe(true)
					expect(hint.MinSize.Y):toBe(38)
					expect(root.HorizontalScrollBarInset):toBe(engine.types.Enum.ScrollBarInset.ScrollBar)
					expect(root.CanvasSize.X.Offset):toBe(750)
					expect(root.ScrollBarThickness):toBe(2)
					stop()
				end
			end,
		})

		it("a scroll view that holds a control is not itself a gamepad stop", {
			id = "native_layout::phone layout policy::a scroll view that holds a control is not itself a gamepad stop",
			run = function()
				local shown = Compose.cell(true)
				local root, engine, stop = build(nil, function(UI)
					return UI.ScrollView {
						UI.Text { text = "Rules" },
						(Compose.show(shown, function()
							return UI.Button { label = "Retry" }
						end) :: unknown) :: GuiObject,
					}
				end)
				expect(root.Selectable):toBe(false)
				shown:set(false)
				for _ = 1, 3 do
					engine.heartbeat:Fire(1 / 60)
				end
				expect(root.Selectable):toBe(true)
				shown:set(true)
				for _ = 1, 3 do
					engine.heartbeat:Fire(1 / 60)
				end
				expect(root.Selectable):toBe(false)
				stop()
			end,
		})

		it("a scroll view rechecks its gamepad stop when hidden content appears", {
			id = "native_layout::phone layout policy::a scroll view rechecks its gamepad stop when hidden content appears",
			run = function()
				local visible = Compose.cell(false)
				local root, engine, stop = build(nil, function(UI)
					return UI.ScrollView {
						UI.Button "Retry" { label = "Retry", Visible = visible },
					}
				end)
				expect(root.Selectable):toBe(true)
				visible:set(true)
				engine.environment.poke(root, "AbsoluteCanvasSize", engine.types.Vector2.new(200, 44))
				for _ = 1, 3 do
					engine.heartbeat:Fire(1 / 60)
				end
				expect(root.Selectable):toBe(false)
				stop()
			end,
		})

		it("a single fitting candidate keeps its authored visibility on phone widths", {
			id = "native_layout::phone layout policy::a single fitting candidate keeps its authored visibility on phone widths",
			run = function()
				local outcomes: { string } = {}
				for _, width in { 320, 360, 375, 389, 430 } do
					local visible = Compose.cell(false)
					local root, engine, stop = build(nil, function(UI)
						return UI.ViewThatFits {
							width = "hug" :: "hug",
							UI.HStack { Visible = visible, UI.Button { label = "Spatial mode" } },
						}
					end)
					engine.environment.poke(root, "AbsoluteSize", engine.types.Vector2.new(width, 44))
					local candidate = root:FindFirstChildWhichIsA("Frame")
					local initiallyHidden = candidate.Visible == false
					visible:set(true)
					expect(candidate.Visible):toBe(true)
					visible:set(false)
					engine.environment.poke(root, "AbsoluteSize", engine.types.Vector2.new(width - 1, 44))
					table.insert(outcomes, `{width}:{initiallyHidden and candidate.Visible == false}`)
					stop()
				end
				expect(table.concat(outcomes, ",")):toBe("320:true,360:true,375:true,389:true,430:true")
			end,
		})
	end)

	describe("world marker", function()
		it("follows its anchor on screen and clamps to the edge with an arrow off screen", {
			id = "native_layout::world marker::follows its anchor on screen and clamps to the edge with an arrow off screen",
			run = function()
				local point = Compose.cell<<EnvironmentTypes.WorldAnchorPoint>>({
					visible = true,
					x = 400,
					y = 300,
					onscreen = true,
				})
				local edge = Compose.cell("clamp" :: "clamp" | "hide")
				local margin = Compose.cell<<SharedTypes.Padding>>(10)
				local holder, engine, stop = build(nil, function(UI, Host)
					return Host.Frame {
						Name = "Holder",
						UI.WorldMarker "Marker" {
							anchor = point,
							edge = edge,
							margin = margin,
							Host.Frame { Name = "Pin" },
						},
					}
				end)
				local V = engine.types.Vector2
				engine.environment.poke(holder, "AbsoluteSize", V.new(800, 600))
				local marker = holder:FindFirstChild("Marker")
				local arrow = marker:FindFirstChild("Arrow", true)
				engine.environment.poke(marker, "AbsoluteSize", V.new(40, 20))
				local function at(): (number, number)
					return marker.Position.X.Offset, marker.Position.Y.Offset
				end
				local x, y = at()
				expect(marker.Visible):toBe(true)
				expect(x):toBe(400)
				expect(y):toBe(300)
				expect(marker:GetAttribute("Clamped")):toBe(false)
				expect(arrow.Visible):toBe(false)
				point:set({ visible = true, x = 400.4, y = 300.3, onscreen = true })
				x, y = at()
				expect(x):toBe(400)
				expect(y):toBe(300)
				point:set({ visible = true, x = 1600, y = 300, onscreen = false })
				x, y = at()
				expect(x):toBe(770)
				expect(y):toBe(300)
				expect(marker:GetAttribute("Clamped")):toBe(true)
				expect(arrow.Visible):toBe(true)
				expect(arrow.Rotation):toBe(0)
				point:set({ visible = true, x = 1600, y = 310, onscreen = false })
				expect(arrow.Rotation):toBe(0)
				point:set({ visible = true, x = 400, y = -900, onscreen = false })
				x, y = at()
				expect(x):toBe(400)
				expect(y):toBe(20)
				expect(arrow.Rotation):toBe(-90)
				point:set({ visible = true, x = 795, y = 300, onscreen = true })
				x = at()
				expect(x):toBe(770)
				expect(marker:GetAttribute("Clamped")):toBe(true)
				margin:set({ top = 60 })
				point:set({ visible = true, x = 400, y = -900, onscreen = false })
				x, y = at()
				expect(y):toBe(70)
				edge:set("hide")
				expect(marker.Visible):toBe(false)
				point:set({ visible = true, x = 300, y = 200, onscreen = true })
				expect(marker.Visible):toBe(true)
				point:set({ visible = false })
				expect(marker.Visible):toBe(false)
				stop()
			end,
		})
	end)

	describe("native text layout", function()
		it("owns a glyph floor only while text can grow without wrapping or truncation", {
			id = "native_layout::native text layout::owns a glyph floor only while text can grow without wrapping or truncation",
			run = function()
				local root, engine, stop = build(nil, function(UI)
					return UI.Text {
						text = "Inventory",
						wrap = true,
						AutomaticSize = engineLib.types.Enum.AutomaticSize.XY,
					}
				end)
				expect(root:FindFirstChild("TextBoundsFloor")):toBe(nil)
				expect(root:FindFirstChild("TextBoundsUnit")):toBe(nil)
				engine.environment.poke(root, "TextBounds", engine.types.Vector2.new(80, 20))
				root.TextWrapped = false
				expect(root:FindFirstChild("TextBoundsFloor").MinSize):toBe(engine.types.Vector2.new(80, 20))
				root.TextTruncate = engine.types.Enum.TextTruncate.AtEnd
				expect(root:FindFirstChild("TextBoundsFloor")):toBe(nil)
				expect(root:FindFirstChild("TextBoundsUnit")):toBe(nil)
				root.TextTruncate = engine.types.Enum.TextTruncate.None
				expect(root:FindFirstChild("TextBoundsFloor").MinSize):toBe(engine.types.Vector2.new(80, 20))
				stop()
				expect(engine.census().connections):toBe(0)
			end,
		})
		it("defers fixed text layout resources until native automatic sizing starts", {
			id = "native_layout::native text layout::defers fixed text layout resources until native automatic sizing starts",
			run = function()
				local mode = Compose.cell(engineLib.types.Enum.AutomaticSize.None)
				local root, engine, stop = build(nil, function(UI)
					return UI.Text {
						text = "Player",
						Size = engineLib.types.UDim2.fromOffset(160, 40),
						AutomaticSize = mode,
					}
				end)
				expect(root:FindFirstChild("TextBoundsFloor")):toBe(nil)
				expect(root:FindFirstChild("TextBoundsUnit")):toBe(nil)
				engine.environment.poke(root, "TextBounds", engine.types.Vector2.new(60, 20))
				mode:set(engine.types.Enum.AutomaticSize.XY)
				local floor = root:FindFirstChild("TextBoundsFloor")
				expect(floor ~= nil):toBe(true)
				expect(floor.MinSize):toBe(engine.types.Vector2.new(60, 20))
				mode:set(engine.types.Enum.AutomaticSize.None)
				mode:set(engine.types.Enum.AutomaticSize.XY)
				expect(root:FindFirstChild("TextBoundsFloor")):toBe(floor)
				stop()
				expect(engine.census().connections):toBe(0)
			end,
		})

		it("keeps the Slider readout reservation across drag values", {
			id = "native_layout::native text layout::keeps the Slider readout reservation across drag values",
			run = function()
				local value = Compose.cell(0)
				local root, engine, stop = build(nil, function(UI)
					local slider: Facet.SliderCellProps = { value = value, min = 0, max = 100 }
					return UI.Slider(slider)
				end)
				local label = root:FindFirstChild("Value", true)
				local floor = label:FindFirstChild("TextBoundsFloor")
				for _, sample in { { 0, 8 }, { 50, 16 }, { 55.08, 36 }, { 100, 24 } } do
					value:set(sample[1])
					engine.environment.poke(label, "TextBounds", engine.types.Vector2.new(sample[2], 16))
					expect(floor.MaxSize.X):toBe(44)
				end
				label.Size = engine.types.UDim2.fromOffset(60, 0)
				expect(floor.MaxSize.X):toBe(60)
				label.Size = engine.types.UDim2.new(1, 0, 0, 0)
				expect(floor.MaxSize.X):toBe(math.huge)
				stop()
			end,
		})
		it("keeps the Stepper readout reservation when a digit is added", {
			id = "native_layout::native text layout::keeps the Stepper readout reservation when a digit is added",
			run = function()
				local value = Compose.cell(9)
				local root, engine, stop = build(nil, function(UI)
					local stepper: Facet.StepperCellProps = { value = value, max = 100 }
					return UI.Stepper(stepper)
				end)
				local label = root:FindFirstChild("Value", true)
				local floor = label:FindFirstChild("TextBoundsFloor")
				engine.environment.poke(label, "TextBounds", engine.types.Vector2.new(8, 16))
				expect(floor.MaxSize.X):toBe(40)
				value:set(10)
				engine.environment.poke(label, "TextBounds", engine.types.Vector2.new(13, 16))
				expect(floor.MaxSize.X):toBe(40)
				stop()
			end,
		})
		it("holds a counting Text at its widest and fits it again when its length changes", {
			id = "native_layout::native text layout::holds a counting Text at its widest and fits it again when its length changes",
			run = function()
				local text = Compose.cell("1,000,000")
				local root, engine, stop = build(nil, function(UI)
					return UI.Text { text = text }
				end)
				local floor = root:FindFirstChild("TextBoundsFloor")
				engine.environment.poke(root, "TextBounds", engine.types.Vector2.new(100, 20))
				expect(floor.MinSize.X):toBe(100)
				text:set("1,000,001")
				engine.environment.poke(root, "TextBounds", engine.types.Vector2.new(96, 20))
				expect(floor.MinSize.X):toBe(100)
				text:set("12")
				engine.environment.poke(root, "TextBounds", engine.types.Vector2.new(14, 20))
				expect(floor.MinSize.X):toBe(14)
				text:set("19")
				engine.environment.poke(root, "TextBounds", engine.types.Vector2.new(13, 20))
				expect(floor.MinSize.X):toBe(14)
				stop()
			end,
		})
		it("grows both ShortcutHint axes with a taller painted key", {
			id = "native_layout::native text layout::grows both ShortcutHint axes with a taller painted key",
			run = function()
				local root, engine, stop = build(nil, function(UI)
					local hint: Facet.ShortcutHintKeysProps = { keys = { { "K" } } }
					return UI.ShortcutHint(hint)
				end)
				engine.environment.poke(root, "TextBounds", engine.types.Vector2.new(6, 12))
				local before = root.Size.Y.Offset
				engine.environment.poke(root, "TextBounds", engine.types.Vector2.new(13, 26))
				expect(root.Size.Y.Offset > before):toBe(true)
				expect(root.Size.X.Offset):toBe(root.Size.Y.Offset)
				expect(root.Size.Y.Offset >= 34):toBe(true)
				expect(root.Size.Y.Offset < 44):toBe(true)
				engine.environment.poke(
					root:FindFirstChild("TextBoundsUnit"),
					"AbsoluteSize",
					engine.types.Vector2.new(50, 0.5)
				)
				engine.environment.poke(
					root:FindFirstChild("CapUnit"),
					"AbsoluteSize",
					engine.types.Vector2.new(50, 0.5)
				)
				engine.environment.poke(root, "TextBounds", engine.types.Vector2.new(6.5, 13))
				expect(root.Size.Y.Offset):toBe(34)
				stop()
			end,
		})
		it("keeps a ShortcutHint square while allowing a longer chord", {
			id = "native_layout::native text layout::keeps a ShortcutHint square while allowing a longer chord",
			run = function()
				local root, engine, stop = build(nil, function(UI)
					local hint: Facet.ShortcutHintKeysProps = { keys = { { "K" } } }
					return UI.ShortcutHint(hint)
				end)
				local floor = root:FindFirstChild("TextBoundsFloor")
				engine.environment.poke(root, "TextBounds", engine.types.Vector2.new(6, 12))
				expect(floor.MaxSize):toBe(engine.types.Vector2.new(root.Size.X.Offset, root.Size.Y.Offset))
				engine.environment.poke(root, "TextBounds", engine.types.Vector2.new(60, 26))
				expect(floor.MaxSize.X):toBe(60)
				expect(floor.MaxSize.Y):toBe(math.max(26, root.Size.Y.Offset))
				local padding = root:FindFirstChildWhichIsA("UIPadding")
				padding.PaddingLeft = engine.types.UDim.new(0, 8)
				padding.PaddingRight = engine.types.UDim.new(0, 8)
				expect(floor.MaxSize.X):toBe(76)
				padding.PaddingRight = engine.types.UDim.new(0, 12)
				expect(floor.MaxSize.X):toBe(80)
				stop()
			end,
		})
		it("yields the automatic glyph floor to a later wrapping constraint", {
			id = "native_layout::native text layout::yields the automatic glyph floor to a later wrapping constraint",
			run = function()
				local root, engine, stop = build(nil, function(UI)
					return UI.Text { text = "A long label" }
				end)
				engine.environment.poke(root, "TextBounds", engine.types.Vector2.new(300, 18))
				expect(root:FindFirstChild("TextBoundsFloor").MinSize.X):toBe(300)
				local cap = engine.new("UISizeConstraint")
				cap.MaxSize = engine.types.Vector2.new(100, math.huge)
				cap.Parent = root
				root.TextWrapped = true
				expect(root:FindFirstChild("TextBoundsFloor")):toBeNil()
				expect(root:FindFirstChildWhichIsA("UISizeConstraint")):toBe(cap)
				expect(cap.MaxSize.X):toBe(100)
				stop()
			end,
		})

		it("reflows a late clipped automatic box after styled metrics have settled", {
			id = "native_layout::native text layout::reflows a late clipped automatic box after styled metrics have settled",
			run = function()
				local engine: any = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local UI = Facet.controls(
					runtime,
					{
						types = engine.types,
						services = { RunService = { Heartbeat = engine.heartbeat } },
					} :: any
				)
				local stop, result = runtime.mount(function()
					return UI.Text "Value" { text = "50%" }
				end, engine.new("ScreenGui"))
				local label: any = result
				engine.heartbeat:Fire(1 / 60)
				expect(engineLib.connections(engine.heartbeat)):toBe(0)
				local pulse = 0
				engine.onWrite(function(node, property, value)
					if
						node == label
						and property == "AutomaticSize"
						and value == engine.types.Enum.AutomaticSize.XY
					then
						pulse += 1
						engine.environment.poke(label, "AbsoluteSize", label.TextBounds)
					end
				end)
				engine.environment.poke(label, "AbsoluteSize", engine.types.Vector2.new(44, 12))
				engine.environment.poke(label, "TextBounds", engine.types.Vector2.new(15, 13))
				expect(pulse):toBe(0)
				engine.heartbeat:Fire(1 / 60)
				expect(pulse):toBe(1)
				expect(label.AbsoluteSize.Y):toBe(13)
				expect(engineLib.connections(engine.heartbeat)):toBe(0)
				engine.heartbeat:Fire(1 / 60)
				expect(pulse):toBe(1)
				engine.environment.poke(label, "AbsoluteSize", engine.types.Vector2.new(44, 12))
				stop()
				runtime:dispose()
				engine.heartbeat:Fire(1 / 60)
				expect(pulse):toBe(1)
				expect(engineLib.connections(engine.heartbeat)):toBe(0)
			end,
		})
		it("leaves the first layout to the engine and reflows styled metric changes without local font overrides", {
			id = "native_layout::native text layout::leaves the first layout to the engine and reflows styled metric changes without local font overrides",
			run = function()
				local engine: any = engineLib.new()
				local points = 13
				local face = engine.types.Font.new("rbxasset://fonts/families/BuilderSans.json")
				local original = engine.new
				engine.new = function(className)
					local node = original(className)
					if className == "TextLabel" then
						engine.environment.fakeOn(node, "GetStyled", function(self, property)
							if property == "FontFace" then
								return face
							elseif property == "TextSize" then
								return points
							end
							return self[property]
						end)
					end
					return node
				end
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local UI = Facet.controls(
					runtime,
					{
						types = engine.types,
						services = { RunService = { Heartbeat = engine.heartbeat } },
					} :: any
				)
				local nativeMetrics = {}
				engine.onWrite(function(node, property, value)
					if
						node.Name == "Summary"
						and property == "AutomaticSize"
						and value == engine.types.Enum.AutomaticSize.XY
					then
						table.insert(nativeMetrics, { node.FontFace, node.TextSize })
					end
				end)
				local stop, result = runtime.mount(function()
					return UI.Text "Summary" { text = "Page 1 of 3" }
				end, engine.new("ScreenGui"))
				local root: any = result
				local initialFace, initialSize = root.FontFace, root.TextSize
				local mounted = #nativeMetrics
				engine.heartbeat:Fire(1 / 60)
				expect(nativeMetrics):toHaveLength(mounted)
				expect(root.FontFace):toBe(initialFace)
				expect(root.TextSize):toBe(initialSize)
				points = 17
				root.StyledPropertiesChanged:Fire()
				engine.heartbeat:Fire(1 / 60)
				expect(nativeMetrics[#nativeMetrics][1]):toBe(face)
				expect(nativeMetrics[#nativeMetrics][2]):toBe(17)
				expect(root.TextSize):toBe(initialSize)
				expect(engineLib.connections(engine.heartbeat)):toBe(0)
				points = 19
				root.StyledPropertiesChanged:Fire()
				stop()
				runtime:dispose()
				local count = #nativeMetrics
				engine.heartbeat:Fire(1 / 60)
				expect(nativeMetrics):toHaveLength(count)
				expect(engineLib.connections(engine.heartbeat)):toBe(0)
			end,
		})
		it("measures wrapped automatic-height text again with the styled size when its text changes", {
			id = "native_layout::native text layout::measures wrapped automatic-height text again with the styled size when its text changes",
			run = function()
				local points = 16
				local Enum, UDim2, Vector2 = engineLib.types.Enum, engineLib.types.UDim2, engineLib.types.Vector2
				local measured = {}
				local line = Compose.cell("Short.")
				local label, engine, stop = build(nil, function(UI)
					return UI.Text "Line" {
						text = line,
						wrap = true,
						Size = UDim2.fromOffset(168, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
					}
				end, {
					getStyled = function(node, property)
						if property == "TextSize" and node.ClassName == "TextLabel" then
							return points
						end
						return node[property]
					end,
				})
				engine.onWrite(function(node, property, value)
					if node.Name == "Line" and property == "AutomaticSize" and value == Enum.AutomaticSize.Y then
						table.insert(measured, node.TextSize)
					end
				end)
				line:set("Short, then longer.")
				engine.heartbeat:Fire(1 / 60)
				local settled = #measured
				expect(settled > 0):toBe(true)
				expect(measured[settled]):toBe(16)
				line:set("I tuned half these karts.  Including yours.  Drive it well.")
				engine.heartbeat:Fire(1 / 60)
				expect(#measured > settled):toBe(true)
				expect(measured[#measured]):toBe(16)
				expect(label.TextSize == 16):toBe(false)
				engine.environment.poke(label, "AbsoluteSize", Vector2.new(168, 19))
				local before = #measured
				engine.environment.poke(label, "TextBounds", Vector2.new(160, 38))
				engine.heartbeat:Fire(1 / 60)
				expect(#measured > before):toBe(true)
				stop()
				expect(engineLib.connections(engine.heartbeat)):toBe(0)
			end,
		})
		it("floors a wrapped automatic-height text at the height of its styled lines", {
			id = "native_layout::native text layout::floors a wrapped automatic-height text at the height of its styled lines",
			run = function()
				local Enum, UDim2, Vector2 = engineLib.types.Enum, engineLib.types.UDim2, engineLib.types.Vector2
				local asked: { number } = {}
				local lines = 3
				local textService = {
					GetTextBoundsAsync = function(_, params: { Width: number, Size: number }): Vector2
						table.insert(asked, params.Width)
						return Vector2.new(params.Width, lines * params.Size)
					end,
				}
				local line = Compose.cell("Use your Soda Rocket: tap ITEM")
				local label, engine, stop = build({ services = { TextService = textService } }, function(UI)
					return UI.Text "Line" {
						text = line,
						wrap = true,
						Size = UDim2.fromOffset(300, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
					}
				end, {
					getStyled = function(node, property)
						return node[property]
					end,
				})
				engine.environment.poke(label, "AbsoluteSize", Vector2.new(300, 27))
				local floor = label:FindFirstChild("TextBoundsFloor")
				expect(#asked > 0):toBe(true)
				expect(asked[#asked]):toBe(300)
				for _, sample in { { 1, 2, 1 }, { 2, 1.25, 2.25 }, { 3, 2, 5 } } do
					lines = sample[1]
					label.LineHeight = sample[2]
					line:set(string.rep("Line ", lines))
					expect(floor.MinSize.Y):toBe(math.ceil(sample[3] * label.TextSize))
				end
				label.TextWrapped = false
				expect(floor.MinSize.Y):toBe(0)
				stop()
			end,
		})
		it("reflows automatic text when font metrics change and preserves fixed text", {
			id = "native_layout::native text layout::reflows automatic text when font metrics change and preserves fixed text",
			run = function()
				local Enum = require("./lib/native_engine").types.Enum
				local frames = engineLib.new()
				local root, engine, stop = build(
					{ services = { RunService = { Heartbeat = frames.heartbeat } } },
					function(UI, Host)
						return Host.Frame {
							UI.Text "Automatic" { text = "Ranger rifle" },
							UI.Text "Fixed" { text = "Ranger rifle", AutomaticSize = Enum.AutomaticSize.None },
							UI.Slider "Slider" { value = Compose.cell(0.5) },
						}
					end
				)
				local automatic, fixed = root.Automatic, root.Fixed
				local states = {}
				local connection = automatic:GetPropertyChangedSignal("AutomaticSize"):Connect(function()
					table.insert(states, automatic.AutomaticSize)
				end)
				automatic.TextSize = 12
				expect(states):toHaveLength(2)
				expect(states[1]):toBe(engine.types.Enum.AutomaticSize.None)
				expect(states[2]):toBe(engine.types.Enum.AutomaticSize.XY)
				automatic.TextColor3 = engine.types.Color3.new(1, 0, 0)
				expect(states):toHaveLength(2)
				fixed.TextSize = 12
				expect(fixed.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.None)
				local readout = root.Slider:FindFirstChild("Value", true)
				local internal = {}
				local internalConnection = readout:GetPropertyChangedSignal("AutomaticSize"):Connect(function()
					table.insert(internal, readout.AutomaticSize)
				end)
				readout.TextSize = 12
				expect(internal):toHaveLength(2)
				expect(internal[1]):toBe(engine.types.Enum.AutomaticSize.None)
				expect(internal[2]):toBe(engine.types.Enum.AutomaticSize.XY)
				frames.heartbeat:Fire(1 / 60)
				expect(states):toHaveLength(4)
				expect(internal):toHaveLength(4)
				expect(engineLib.connections(frames.heartbeat)):toBe(0)
				frames.heartbeat:Fire(1 / 60)
				expect(states):toHaveLength(4)
				expect(internal):toHaveLength(4)
				automatic.TextSize = 14
				stop()
				local released = #states
				frames.heartbeat:Fire(1 / 60)
				expect(states):toHaveLength(released)
				expect(engineLib.connections(frames.heartbeat)):toBe(0)
				internalConnection:Disconnect()
				connection:Disconnect()
				stop()
			end,
		})
	end)

	describe("native layout primitives", function()
		describe("VStack and HStack", function()
			it("maps align and distribute to the native list alignment and flex", {
				id = "native_layout::VStack and HStack::maps align and distribute to the native list alignment and flex",
				run = function()
					local align = Compose.cell("center" :: "center" | "end" | "start" | "stretch")
					local root, engine, stop = build(nil, function(UI)
						return UI.HStack {
							align = align,
							height = 40,
							distribute = "spaceBetween" :: "spaceBetween",
							UI.Text { text = "A" },
						}
					end)
					local E = engine.types.Enum
					local layout = child(root, "UIListLayout")
					expect(layout.VerticalAlignment):toBe(E.VerticalAlignment.Center)
					expect(layout.ItemLineAlignment):toBe(E.ItemLineAlignment.Automatic)
					expect(layout.HorizontalFlex):toBe(E.UIFlexAlignment.SpaceBetween)
					expect(layout.HorizontalAlignment):toBe(E.HorizontalAlignment.Left)
					expect(layout.VerticalFlex):toBe(E.UIFlexAlignment.None)
					align:set("stretch")
					expect(layout.ItemLineAlignment):toBe(E.ItemLineAlignment.Stretch)
					expect(layout.VerticalFlex):toBe(E.UIFlexAlignment.Fill)
					expect(layout.HorizontalFlex):toBe(E.UIFlexAlignment.SpaceBetween)
					expect(layout.VerticalAlignment):toBe(E.VerticalAlignment.Top)
					align:set("end")
					expect(layout.VerticalAlignment):toBe(E.VerticalAlignment.Bottom)
					expect(layout.VerticalFlex):toBe(E.UIFlexAlignment.None)
					stop()
					local column = build(nil, function(UI)
						return UI.VStack { align = "end" :: "end", distribute = "center" :: "center" }
					end)
					local list = child(column, "UIListLayout")
					expect(list.HorizontalAlignment):toBe(E.HorizontalAlignment.Right)
					expect(list.VerticalAlignment):toBe(E.VerticalAlignment.Center)
					expect(list.VerticalFlex):toBe(E.UIFlexAlignment.None)
				end,
			})

			it("turns off auto localization only for text the author binds", {
				id = "native_layout::VStack and HStack::turns off auto localization only for text the author binds",
				run = function()
					local words = Compose.cell("Coins 10")
					local root, _engine, stop = build(nil, function(UI)
						return UI.VStack {
							UI.Text "Static" { text = "Play" },
							UI.Text "Bound" { text = words },
							UI.Text "Chosen" { text = words, AutoLocalize = true },
							UI.Picker "Language" {
								label = "Word language",
								options = { { value = "en", label = "English" } },
								selected = Compose.cell("en"),
								style = "cards",
							},
						}
					end)
					expect((root:FindFirstChild("Static", true) :: TextLabel).AutoLocalize):toBe(true)
					expect((root:FindFirstChild("Bound", true) :: TextLabel).AutoLocalize):toBe(false)
					expect((root:FindFirstChild("Chosen", true) :: TextLabel).AutoLocalize):toBe(true)
					local found = {}
					for _, node in root:GetDescendants() do
						if
							(node:IsA("TextLabel") or node:IsA("TextButton"))
							and (node.Text == "Word language" or node.Text == "English")
						then
							table.insert(found, `{node.Text}={node.AutoLocalize}`)
						end
					end
					local joined = table.concat(found, ",")
					expect(string.find(joined, "Word language=true", 1, true) ~= nil):toBe(true)
					expect((string.find(joined, "=false", 1, true))):toBeNil()
					stop()
				end,
			})

			it("treats a transiently negative computed extent as zero pixels", {
				id = "native_layout::VStack and HStack::treats a transiently negative computed extent as zero pixels",
				run = function()
					local viewport = Compose.cell(0)
					local root, _engine, stop = build(nil, function(UI)
						return UI.VStack {
							width = function(use: Use): number
								return use(viewport) - 80
							end,
							height = 40,
						}
					end)
					expect(root.Size.X.Offset):toBe(0)
					viewport:set(400)
					expect(root.Size.X.Offset):toBe(320)
					stop()
				end,
			})

			it("reserves wrapped row height in a hugging parent and releases it after reflow", function(_own, t)
				local root, engine, stop = build(nil, function(UI)
					local filter: Facet.TextInputCellProps = { placeholder = "Filter files", value = Compose.cell("") }
					return UI.VStack "FilterArea" {
						width = "fill",
						UI.HStack "Filters" {
							width = "fill",
							wrap = true,
							UI.TextInput(filter),
							UI.Button { label = "Clear filter" },
						},
						UI.Text { text = "18 of 27 items" },
					}
				end)
				t:defer(stop)
				local filters = root.Filters
				local list = filters:FindFirstChildWhichIsA("UIListLayout")
				for _, height in { 44, 96, 44 } do
					engine.environment.poke(
						VerifyRoblox.assertInstance(list),
						"AbsoluteContentSize",
						engine.types.Vector2.new(320, height)
					)
					t:expect(filters.Lift.MinSize.Y):toBe(height)
				end
			end)

			it("lets a hugging fill stack take its size along a bounded parent row from the flex", {
				id = "native_layout::VStack and HStack::lets a hugging fill stack take its size along a bounded parent row from the flex",
				run = function()
					local types = require("./lib/native_engine").types
					local root, engine, stop = build(nil, function(UI, Host)
						return UI.VStack {
							UI.HStack {
								Name = "Row",
								width = "fill" :: "fill",
								Host.Frame { Name = "List", Size = types.UDim2.fromOffset(380, 100) },
								UI.VStack { Name = "Detail", UI.fill() },
								UI.VStack {
									Name = "Authored",
									AutomaticSize = types.Enum.AutomaticSize.XY,
									UI.fill(),
								},
							},
							UI.HStack {
								Name = "Hug",
								UI.VStack { Name = "Grown", UI.fill() },
							},
						}
					end)
					local AutomaticSize = engine.types.Enum.AutomaticSize
					local row = root:FindFirstChild("Row")
					local detail = row:FindFirstChild("Detail")
					expect(detail.AutomaticSize):toBe(AutomaticSize.Y)
					expect(row:FindFirstChild("Authored").AutomaticSize):toBe(AutomaticSize.XY)
					expect(root:FindFirstChild("Hug"):FindFirstChild("Grown").AutomaticSize):toBe(AutomaticSize.XY)
					row:FindFirstChildWhichIsA("UIListLayout").FillDirection = engine.types.Enum.FillDirection.Vertical
					expect(detail.AutomaticSize):toBe(AutomaticSize.XY)
					stop()
				end,
			})

			it("keeps a keyed child's rows in keyed order between their siblings, and a row's own LayoutOrder wins", {
				id = "native_layout::VStack and HStack::keeps a keyed child's rows in keyed order between their siblings, and a row's own LayoutOrder wins",
				run = function()
					local items = Compose.cell({ "A", "B", "C" })
					local root, _, stop = build(nil, function(UI)
						return UI.VStack {
							UI.Text { text = "Top" },
							Compose.keyed({
								from = items,
								render = function(
									value: ComposeTypes.ReadOnlyValue<string>,
									index: ComposeTypes.ReadOnlyValue<number>
								): GuiObject
									return UI.Text {
										text = value,
										LayoutOrder = index,
									}
								end,
							}),
							Compose.keyed({
								from = items,
								render = function(value: ComposeTypes.ReadOnlyValue<string>): GuiObject
									return UI.Text {
										text = function(use: Use)
											return string.lower(use(value))
										end,
									}
								end,
							}),
							UI.Text { text = "End" },
						}
					end)
					expect((painted(root))):toBe("Top A B C a b c End")
					items:set({ "B", "C", "A" })
					expect((painted(root))):toBe("Top B C A b c a End")
					items:set({ "C", "D", "B" })
					expect((painted(root))):toBe("Top C D B c d b End")
					stop()
				end,
			})
			it("grows a padded stack's padding to hold its children's shadows", {
				id = "native_layout::VStack and HStack::grows a padded stack's padding to hold its children's shadows",
				run = function()
					local root, engine, stop = build(nil, function(UI: FacetControls, C)
						return UI.HStack {
							padding = { top = 3, bottom = 3, left = 8, right = 8 },
							(C.Frame :: FrameConstructor) { Name = "Plated" },
						}
					end)
					local T = engine.types
					local padding = child(root, "UIPadding")
					expect(padding.PaddingBottom):toBe(T.UDim.new(0, 3))
					local plated = root:FindFirstChild("Plated")
					local plate = engine.new("UIShadow")
					plate.Offset = T.UDim2.new(0, 0, 0, 5)
					plate.Parent = plated
					expect(padding.PaddingBottom):toBe(T.UDim.new(0, 8))
					expect(padding.PaddingTop):toBe(T.UDim.new(0, 3))
					expect(padding.PaddingLeft):toBe(T.UDim.new(0, 8))
					plate.Spread = T.UDim2.new(0, 1, 0, 1)
					plate.BlurRadius = T.UDim.new(0, 2)
					expect(padding.PaddingBottom):toBe(T.UDim.new(0, 11))
					expect(padding.PaddingTop):toBe(T.UDim.new(0, 3))
					expect(padding.PaddingRight):toBe(T.UDim.new(0, 11))
					plated.Visible = false
					expect(padding.PaddingBottom):toBe(T.UDim.new(0, 3))
					plated.Visible = true
					plate.Enabled = false
					expect(padding.PaddingBottom):toBe(T.UDim.new(0, 3))
					plate.Enabled = true
					expect(padding.PaddingBottom):toBe(T.UDim.new(0, 11))
					plate.Parent = nil
					expect(padding.PaddingBottom):toBe(T.UDim.new(0, 3))
					expect(padding.PaddingRight):toBe(T.UDim.new(0, 8))
					stop()
				end,
			})
			it("grows a padded AdaptiveStack's padding to hold its children's shadows", {
				id = "native_layout::VStack and HStack::grows a padded AdaptiveStack's padding to hold its children's shadows",
				run = function()
					local root, engine, stop = build(nil, function(UI: FacetControls, C)
						return UI.AdaptiveStack {
							padding = 4,
							(C.Frame :: FrameConstructor) { Name = "Plated" },
						}
					end)
					local padding = child(root, "UIPadding")
					local plate = engine.new("UIShadow")
					plate.Offset = engine.types.UDim2.new(0, 0, 0, 5)
					plate.Parent = root:FindFirstChild("Plated")
					expect(padding.PaddingBottom):toBe(engine.types.UDim.new(0, 9))
					expect(padding.PaddingTop):toBe(engine.types.UDim.new(0, 4))
					stop()
				end,
			})
			it("leaves a stack without padding unpadded under shadowed children", {
				id = "native_layout::VStack and HStack::leaves a stack without padding unpadded under shadowed children",
				run = function()
					local root, engine, stop = build(nil, function(UI: FacetControls, C)
						return UI.VStack { (C.Frame :: FrameConstructor) { Name = "Plated" } }
					end)
					local plate = engine.new("UIShadow")
					plate.Offset = engine.types.UDim2.new(0, 0, 0, 5)
					plate.Parent = root:FindFirstChild("Plated")
					expect((child(root, "UIPadding"))):toBe(nil)
					stop()
				end,
			})
		end)

		describe("Screen", function()
			it("unmounts a screen while overscan remains active", function()
				local engine, runtime, UI, fixture = make({ environment = { viewingDistance = "ten-foot" } }, {})
				local tracking = fixture.track()
				local layer = engine.new("ScreenGui")
				engine.environment.poke(layer, "AbsoluteSize", engine.types.Vector2.new(1920, 1080))
				local stop = runtime.mount(function()
					return UI.Screen { padding = 0 }
				end, layer)
				local before = #tracking.created
				stop()
				expect(#tracking.created):toBe(before)
				tracking.stop()
				runtime:dispose()
			end)
			it("fills its parent, pads the content by the m step and stacks vertically", {
				id = "native_layout::Screen::fills its parent, pads the content by the m step and stacks vertically",
				run = function()
					local root, engine, stop = build(nil, function(UI)
						return UI.Screen "Home" { gap = "s", UI.Text { text = "A" } }
					end)
					local E = engine.types.Enum
					expect(root.Name):toBe("Home")
					expect(root.Size):toBe(engine.types.UDim2.fromScale(1, 1))
					expect(root.AutomaticSize):toBe(E.AutomaticSize.None)
					expect((root:HasTag("facet-layout"))):toBe(true)
					expect(child(root, "UIPadding").PaddingTop):toBe(engine.types.UDim.new(0, 16))
					expect(child(root, "UIListLayout").FillDirection):toBe(E.FillDirection.Vertical)
					expect(child(root, "UIListLayout").Padding):toBe(engine.types.UDim.new(0, 8))
					stop()
					local bare = build(nil, function(UI)
						return UI.Screen { padding = 0 }
					end)
					expect(child(bare, "UIPadding").PaddingLeft):toBe(engine.types.UDim.new(0, 0))
				end,
			})

			it("keeps its content below the engine top bar, the background still fills", {
				id = "native_layout::Screen::keeps its content below the engine top bar, the background still fills",
				run = function()
					for _, ignoresInset in { true, false } do
						local engine: any = engineLib.new()
						local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
						local gui = (engine.new("GuiService") :: unknown) :: GuiService
						local T = engine.types
						local insetTop = if ignoresInset then 58 else 36
						engine.environment.fakeOn(VerifyRoblox.assertInstance(gui), "GetGuiInset", function()
							return T.Vector2.new(0, insetTop), T.Vector2.zero
						end)
						engine.environment.poke(gui, "TopbarInset", T.Rect.new(104, 0, 1000, 58))
						local UI = Facet.controls(
							runtime,
							{ types = T, guiService = gui, services = { GuiService = gui } } :: any
						)
						local layer = engine.new("ScreenGui")
						layer.IgnoreGuiInset = ignoresInset
						local root: any
						runtime.mount(function()
							root = UI.Screen { UI.Text { text = "A" } }
							return root
						end, layer)
						engine.environment.poke(
							root,
							"AbsolutePosition",
							T.Vector2.new(0, if ignoresInset then -58 else 0)
						)
						local padding = child(root, "UIPadding")
						expect(padding.PaddingTop):toBe(T.UDim.new(0, 16 + 58 - insetTop - root.AbsolutePosition.Y))
						expect(padding.PaddingLeft):toBe(T.UDim.new(0, 16))
						expect(root.Size):toBe(T.UDim2.fromScale(1, 1))
						engine.environment.poke(gui, "TopbarInset", T.Rect.new(0, 0, 0, 0))
						expect(padding.PaddingTop):toBe(T.UDim.new(0, 16))
						engine.environment.poke(gui, "TopbarInset", T.Rect.new(104, 0, 1000, 58))
						engine.environment.poke(root, "AbsolutePosition", T.Vector2.new(0, 200))
						expect(padding.PaddingTop):toBe(T.UDim.new(0, 16))
						runtime:dispose()
					end
				end,
			})

			it("refreshes top-bar clearance when the native inset changes without a property event", {
				id = "native_layout::Screen::refreshes top-bar clearance when the native inset changes without a property event",
				run = function()
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local gui = (engine.new("GuiService") :: unknown) :: GuiService
					local T = engine.types
					local inset = 30
					engine.environment.fakeOn(VerifyRoblox.assertInstance(gui), "GetGuiInset", function()
						return T.Vector2.new(0, inset), T.Vector2.zero
					end)
					engine.environment.poke(gui, "TopbarInset", T.Rect.new(104, 0, 1000, 58))
					local UI = Facet.controls(
						runtime,
						{
							types = T,
							guiService = gui,
							services = { GuiService = gui, RunService = { Heartbeat = engine.heartbeat } },
						} :: any
					)
					local root: any
					runtime.mount(function()
						root = UI.Screen { UI.Text { text = "Clock" } }
						return root
					end, engine.new("ScreenGui"))
					local padding = child(root, "UIPadding")
					expect(padding.PaddingTop):toBe(T.UDim.new(0, 44))
					inset = 58
					engine.heartbeat:Fire(1 / 60)
					expect(padding.PaddingTop):toBe(T.UDim.new(0, 16))
					inset = 30
					engine.heartbeat:Fire(1 / 60)
					expect(padding.PaddingTop):toBe(T.UDim.new(0, 44))
					runtime:dispose()
				end,
			})

			it("chrome band rides the free top-bar band, and edge also drops the overscan", {
				id = "native_layout::Screen::chrome band rides the free top-bar band, and edge also drops the overscan",
				run = function()
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local gui = (engine.new("GuiService") :: unknown) :: GuiService
					local input = (engine.new("UserInputService") :: unknown) :: UserInputService
					local T = engine.types
					engine.environment.fakeOn(VerifyRoblox.assertInstance(gui), "GetGuiInset", function()
						return T.Vector2.new(0, 58), T.Vector2.zero
					end)
					engine.environment.fakeOn(VerifyRoblox.assertInstance(input), "GetLastInputType", function()
						return T.Enum.UserInputType.Keyboard
					end)
					engine.environment.poke(gui, "TopbarInset", T.Rect.new(104, 0, 1000, 58))
					engine.environment.poke(gui, "ViewportDisplaySize", T.Enum.DisplaySize.Large)
					local UI = Facet.controls(
						runtime,
						{
							types = T,
							guiService = gui,
							userInputService = input,
							services = { GuiService = gui, UserInputService = input },
						} :: any
					)
					local layer = engine.new("ScreenGui")
					layer.IgnoreGuiInset = true
					local roots = {}
					for _, chrome in { "device", "band", "edge" } do
						runtime.mount(function()
							roots[chrome] = UI.Screen { chrome = chrome :: "band" | "device" | "edge" }
							return roots[chrome]
						end, layer)
						engine.environment.poke(roots[chrome], "AbsolutePosition", T.Vector2.new(0, -58))
					end
					local function top(chrome: string): any
						return child(roots[chrome], "UIPadding").PaddingTop
					end
					expect((top("device"))):toBe(T.UDim.new(60 / 1080, 24 + 58))
					expect((top("band"))):toBe(T.UDim.new(60 / 1080, 24))
					expect((top("edge"))):toBe(T.UDim.new(0, 24))
					expect(child(roots.edge, "UIPadding").PaddingLeft):toBe(T.UDim.new(0, 24))
					expect((pcall(function()
						runtime.mount(function()
							return UI.Screen({ chrome = "glass" } :: any)
						end, layer)
					end))):toBe(false)
					runtime:dispose()
				end,
			})

			it("clears only the remaining overscan at each edge, including nested screens", {
				id = "native_layout::Screen::clears only the remaining overscan at each edge, including nested screens",
				run = function()
					local engine = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local T = engine.types
					local margins = cells.overscan(nil)
					local distance = Compose.cell("ten-foot" :: ("automatic" | "near" | "ten-foot")?)
					local UI = Facet.controls(runtime, {
						types = T,
						environment = { viewingDistance = distance, overscanInsets = margins },
					})
					local layer = engine.new("ScreenGui")
					engine.environment.poke(layer, "AbsoluteSize", T.Vector2.new(1920, 1080))
					local nested
					local stop, root: any = runtime.mount(function()
						nested = UI.Screen { padding = 0 }
						return UI.Screen { padding = 0, nested }
					end, layer)
					engine.environment.poke(root, "AbsoluteSize", layer.AbsoluteSize)
					engine.environment.poke(
						VerifyRoblox.assertInstance(nested),
						"AbsoluteSize",
						T.Vector2.new(1700, 900)
					)
					engine.environment.poke(
						VerifyRoblox.assertInstance(nested),
						"AbsolutePosition",
						T.Vector2.new(100, 100)
					)
					local outer, inner = child(root, "UIPadding"), child(nested, "UIPadding")
					expect(outer.PaddingTop):toBe(T.UDim.new(0, 60))
					expect(outer.PaddingLeft):toBe(T.UDim.new(0, 90))
					expect(inner.PaddingTop):toBe(T.UDim.new(0, 0))
					expect(inner.PaddingLeft):toBe(T.UDim.new(0, 0))
					engine.environment.poke(
						VerifyRoblox.assertInstance(nested),
						"AbsolutePosition",
						T.Vector2.new(30, 20)
					)
					expect(inner.PaddingTop):toBe(T.UDim.new(0, 40))
					expect(inner.PaddingLeft):toBe(T.UDim.new(0, 60))
					margins:set({ top = 30, left = 40, bottom = 30, right = 40 })
					expect(inner.PaddingTop):toBe(T.UDim.new(0, 10))
					expect(inner.PaddingLeft):toBe(T.UDim.new(0, 10))
					margins:set(nil)
					distance:set("near")
					expect(outer.PaddingTop):toBe(T.UDim.new(0, 0))
					expect(inner.PaddingLeft):toBe(T.UDim.new(0, 0))
					stop()
					runtime:dispose()
				end,
			})

			local PORTRAIT: GlassBands = { width = 390, height = 844, top = 106, left = 0, bottom = 34, right = 0 }

			local function glassWorld(bands: GlassBands, build: (FacetControls) -> Frame)
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local T = engine.types
				local gui = engine.new("GuiService")
				local service = (gui :: unknown) :: VerifyRoblox.Instance
				local function guiInset(_self: VerifyRoblox.Instance): (Vector2, Vector2)
					return T.Vector2.new(bands.left, bands.top), T.Vector2.new(bands.right, bands.bottom)
				end
				local function insetArea(_self: VerifyRoblox.Instance, inset: Enum.ScreenInsets): Rect
					if inset == T.Enum.ScreenInsets.None then
						return T.Rect.new(0, 0, bands.width, bands.height)
					end
					return T.Rect.new(bands.left, bands.top, bands.width - bands.right, bands.height - bands.bottom)
				end
				engine.environment.fakeOn(service, "GetGuiInset", guiInset)
				engine.environment.fakeOn(service, "GetInsetArea", insetArea)
				engine.environment.poke(service, "TopbarInset", T.Rect.new(0, 0, bands.width, bands.top))
				local UI = Facet.controls(runtime, {
					types = T,
					guiService = gui,
					motionLevel = "none",
					services = { GuiService = gui },
				})
				local layer = engine.new("ScreenGui")
				layer.ScreenInsets = T.Enum.ScreenInsets.CoreUISafeInsets
				layer.ClipToDeviceSafeArea = true
				local wide, tall = bands.width - bands.left - bands.right, bands.height - bands.top - bands.bottom
				local safe = T.Vector2.new(wide, tall)
				engine.environment.poke(layer, "AbsoluteSize", safe)
				local built: Frame? = nil
				local stop = runtime.mount(function()
					local node = build(UI)
					built = node
					return node
				end, layer)
				local function poke(node: Instance, property: string, value: unknown)
					engine.environment.poke((node :: unknown) :: VerifyRoblox.Instance, property, value)
				end
				return {
					T = T,
					layer = layer,
					root = assert(built),
					safe = safe,
					poke = poke,
					stop = function()
						stop()
						runtime:dispose()
					end,
				}
			end

			it("paints a surface Screen to the glass at its safe edges and keeps the content safe", {
				id = "native_layout::Screen::paints a surface Screen to the glass at its safe edges and keeps the content safe",
				run = function()
					local world = glassWorld(PORTRAIT, function(UI): Frame
						return UI.Screen "Shop" { surface = "surface", UI.Text { text = "Shop" } }
					end)
					local T, corner = world.T, 8
					world.poke(world.root, "AbsoluteSize", world.safe)
					local glass = world.root:FindFirstChild("Glass") :: Instance
					local backdrop = world.root:FindFirstChild("Backdrop", true) :: Frame
					expect(glass:IsA("Folder")):toBe(true)
					expect((backdrop:IsDescendantOf(glass))):toBe(true)
					expect((backdrop:HasTag("facet-surface"))):toBe(true)
					expect(backdrop.ZIndex):toBe(0)
					expect(backdrop.Position):toBe(T.UDim2.fromOffset(-corner, -106 - corner))
					expect(backdrop.Size):toBe(T.UDim2.new(1, 2 * corner, 1, 106 + 34 + 2 * corner))
					local padding = world.root:FindFirstChildWhichIsA("UIPadding") :: UIPadding
					expect(padding.PaddingTop):toBe(T.UDim.new(0, 16))
					expect(padding.PaddingBottom):toBe(T.UDim.new(0, 16))
					expect(padding.PaddingLeft):toBe(T.UDim.new(0, 16))
					expect(world.layer.ClipToDeviceSafeArea):toBe(false)
					world.stop()
					expect(world.layer.ClipToDeviceSafeArea):toBe(true)
				end,
			})

			it("ends the surface plate at the screen bounds away from the safe edges", {
				id = "native_layout::Screen::ends the surface plate at the screen bounds away from the safe edges",
				run = function()
					local world = glassWorld(PORTRAIT, function(UI): Frame
						return UI.VStack {
							UI.Screen "Plain" { padding = 0 },
							UI.Screen "Painted" { surface = "surface" },
						}
					end)
					local T, corner = world.T, 8
					local V2 = T.Vector2
					local plain = world.root:FindFirstChild("Plain") :: Frame
					local painted = world.root:FindFirstChild("Painted") :: Frame
					world.poke(painted, "AbsolutePosition", V2.new(100, 50))
					world.poke(painted, "AbsoluteSize", V2.new(200, 300))
					local backdrop = painted:FindFirstChild("Backdrop", true) :: Frame
					expect((plain:FindFirstChild("Glass"))):toBeNil()
					expect((plain:FindFirstChild("Backdrop", true))):toBeNil()
					expect(backdrop.Position):toBe(T.UDim2.fromOffset(0, 0))
					expect(backdrop.Size):toBe(T.UDim2.fromScale(1, 1))
					expect(world.layer.ClipToDeviceSafeArea):toBe(true)
					world.poke(painted, "AbsolutePosition", V2.new(0, 50))
					expect(backdrop.Position):toBe(T.UDim2.fromOffset(-corner, 0))
					expect(backdrop.Size):toBe(T.UDim2.new(1, corner, 1, 0))
					expect(world.layer.ClipToDeviceSafeArea):toBe(true)
					world.poke(painted, "AbsolutePosition", V2.new(0, 0))
					expect(backdrop.Position):toBe(T.UDim2.fromOffset(-corner, -106 - corner))
					expect(world.layer.ClipToDeviceSafeArea):toBe(false)
					world.stop()
					expect(world.layer.ClipToDeviceSafeArea):toBe(true)
					local wrong = refusal(function(UI)
						return UI.Screen(({ surface = "card" } :: unknown) :: Facet.ScreenProps)
					end)
					expect(mentions(wrong, "surface must be surface, panel or pane")):toBe(true)
				end,
			})

			it("follows a landscape cutout on either side with the surface plate", {
				id = "native_layout::Screen::follows a landscape cutout on either side with the surface plate",
				run = function()
					for _, side in { { left = 47, right = 0 }, { left = 0, right = 47 } } do
						local landscape: GlassBands = {
							width = 844,
							height = 390,
							top = 58,
							left = side.left,
							bottom = 21,
							right = side.right,
						}
						local world = glassWorld(landscape, function(UI): Frame
							return UI.Screen { surface = "surface", UI.Text { text = "Garage" } }
						end)
						local T, corner = world.T, 8
						world.poke(world.root, "AbsoluteSize", world.safe)
						local backdrop = world.root:FindFirstChild("Backdrop", true) :: Frame
						local wide = side.left + side.right + 2 * corner
						expect(backdrop.Position):toBe(T.UDim2.fromOffset(-side.left - corner, -58 - corner))
						expect(backdrop.Size):toBe(T.UDim2.new(1, wide, 1, 58 + 21 + 2 * corner))
						local padding = world.root:FindFirstChildWhichIsA("UIPadding") :: UIPadding
						expect(padding.PaddingLeft):toBe(T.UDim.new(0, 16))
						expect(padding.PaddingRight):toBe(T.UDim.new(0, 16))
						expect(padding.PaddingTop):toBe(T.UDim.new(0, 16))
						world.stop()
					end
				end,
			})

			it("shares the device clipping lease between a surface Screen and a modal", {
				id = "native_layout::Screen::shares the device clipping lease between a surface Screen and a modal",
				run = function()
					local open = Compose.cell(false)
					local world = glassWorld(PORTRAIT, function(UI): Frame
						local confirmation: Facet.AlertSpec<unknown> = {
							isPresented = open,
							title = "Buy?",
							actions = { { id = "ok", label = "OK" } },
						}
						return UI.Screen {
							surface = "surface",
							UI.Alert "Confirm"(confirmation),
						}
					end)
					local V2 = world.T.Vector2
					world.poke(world.root, "AbsoluteSize", world.safe)
					expect(world.layer.ClipToDeviceSafeArea):toBe(false)
					open:set(true)
					expect(world.layer.ClipToDeviceSafeArea):toBe(false)
					open:set(false)
					expect(world.layer.ClipToDeviceSafeArea):toBe(false)
					world.poke(world.root, "AbsolutePosition", V2.new(0, 40))
					world.poke(world.root, "AbsoluteSize", V2.new(390, 600))
					expect(world.layer.ClipToDeviceSafeArea):toBe(true)
					open:set(true)
					expect(world.layer.ClipToDeviceSafeArea):toBe(false)
					open:set(false)
					expect(world.layer.ClipToDeviceSafeArea):toBe(true)
					world.stop()
				end,
			})
		end)

		describe("ZStack", function()
			it("aligns children by offset along a hugging axis", {
				id = "native_layout::ZStack::aligns children by offset along a hugging axis",
				run = function()
					local root, engine, stop = build(nil, function(UI, Host)
						return UI.ZStack {
							width = 60,
							alignH = "end" :: "end",
							alignV = "end" :: "end",
							Host.Frame { Name = "Card" },
							Host.Frame { Name = "Dot" },
						}
					end)
					local V2, D2 = engine.types.Vector2, engine.types.UDim2
					local card, dot = root:FindFirstChild("Card"), root:FindFirstChild("Dot")
					engine.environment.poke(card, "AbsoluteSize", V2.new(60, 40))
					engine.environment.poke(dot, "AbsoluteSize", V2.new(16, 16))
					expect(dot.AnchorPoint):toBe(V2.new(1, 0))
					expect(dot.Position):toBe(D2.new(1, 0, 0, 24))
					expect(card.Position):toBe(D2.new(1, 0, 0, 0))
					engine.environment.poke(dot, "AbsoluteSize", V2.new(16, 50))
					expect(card.Position):toBe(D2.new(1, 0, 0, 10))
					expect(dot.Position):toBe(D2.new(1, 0, 0, 0))
					stop()
				end,
			})
		end)

		describe("ScrollView", function()
			it("keeps room inside its canvas for the theme's plate glow and edge", {
				id = "native_layout::ScrollView::keeps room inside its canvas for the theme's plate glow and edge",
				run = function()
					local edge: ThemeTypes.AuthoredRuleProperties = { Thickness = 2 }
					local definition: Facet.ThemeDefinition = {
						identity = { id = "glowing" },
						chrome = {
							panel = {
								kind = "native",
								shadow = {
									blurRadius = { scale = 0, offset = 18 },
									offset = { y = { scale = 0, offset = 4 } },
								},
							},
						},
						rules = { { selector = ".facet-panel::UIStroke", properties = edge } },
					}
					local glowing = assert((Facet.themes.define(definition)))
					local root, _, stop = build({ theme = glowing }, function(UI)
						return UI.ScrollView { UI.VStack { width = "fill", surface = "panel" } }
					end)
					local padding = child(root, "UIPadding")
					expect(padding ~= nil):toBe(true)
					expect(padding.PaddingLeft.Offset):toBe(22)
					expect(padding.PaddingTop.Offset):toBe(22)
					stop()
					root, _, stop = build({ theme = glowing }, function(UI)
						return UI.ScrollView { padding = 8 }
					end)
					expect(child(root, "UIPadding").PaddingRight.Offset):toBe(30)
					stop()
					root, _, stop = build(nil, function(UI)
						return UI.ScrollView {}
					end)
					expect(child(root, "UIPadding")):toBe(nil)
					stop()
				end,
			})

			it("keeps a horizontal canvas floor at the native layout extent and respects an authored canvas", {
				id = "native_layout::ScrollView::keeps a horizontal canvas floor at the native layout extent and respects an authored canvas",
				run = function()
					local root, engine, stop = build(nil, function(UI)
						return UI.ScrollView { axis = "x" :: "x", padding = { left = 4, right = 6 } }
					end)
					local V2 = engine.types.Vector2
					engine.environment.poke(root, "AbsoluteWindowSize", V2.new(353, 44))
					engine.environment.poke(child(root, "UIListLayout"), "AbsoluteContentSize", V2.new(376, 40))
					expect(root.AutomaticCanvasSize):toBe(engine.types.Enum.AutomaticSize.X)
					expect(root.CanvasSize.X.Offset):toBe(386)
					engine.environment.poke(root:FindFirstChild("LayoutUnit"), "AbsoluteSize", V2.new(200, 2))
					engine.environment.poke(root, "AbsoluteWindowSize", V2.new(706, 88))
					engine.environment.poke(child(root, "UIListLayout"), "AbsoluteContentSize", V2.new(752, 80))
					expect(root.CanvasSize.X.Offset):toBe(386)
					engine.environment.poke(root:FindFirstChild("LayoutUnit"), "AbsoluteSize", V2.new(100, 1))
					engine.environment.poke(child(root, "UIListLayout"), "AbsoluteContentSize", V2.new(250, 40))
					expect(root.CanvasSize.X.Offset):toBe(260)
					stop()
					root, engine, stop = build(nil, function(UI)
						return UI.ScrollView {
							axis = "x" :: "x",
							CanvasSize = engine.types.UDim2.fromOffset(500, 0),
						}
					end)
					engine.environment.poke(
						child(root, "UIListLayout"),
						"AbsoluteContentSize",
						engine.types.Vector2.new(700, 40)
					)
					expect(root.CanvasSize.X.Offset):toBe(500)
					stop()
				end,
			})

			it("restores an initial offset after native canvas bounds arrive without overriding input", {
				id = "native_layout::ScrollView::restores an initial offset after native canvas bounds arrive without overriding input",
				run = function()
					local frame, engine, stop = build(nil, function(UI)
						return UI.ScrollView {
							CanvasPosition = require("./lib/native_engine").types.Vector2.new(130, 0),
							axis = "x",
						}
					end)
					local V2 = engine.types.Vector2
					frame.CanvasPosition = V2.zero
					engine.environment.poke(frame, "AbsoluteWindowSize", V2.new(365, 220))
					expect(frame.CanvasPosition):toBe(V2.zero)
					engine.environment.poke(frame, "AbsoluteCanvasSize", V2.new(624, 220))
					expect(frame.CanvasPosition):toBe(V2.new(130, 0))
					frame.CanvasPosition = V2.new(20, 0)
					engine.environment.poke(frame, "AbsoluteCanvasSize", V2.new(800, 220))
					expect(frame.CanvasPosition):toBe(V2.new(20, 0))
					stop()
					frame, engine, stop = build(nil, function(UI)
						return UI.ScrollView { CanvasPosition = V2.new(130, 0), axis = "x" }
					end)
					frame.CanvasPosition = V2.zero
					frame.InputBegan:Fire({ UserInputType = engine.types.Enum.UserInputType.Touch })
					engine.environment.poke(frame, "AbsoluteWindowSize", V2.new(365, 220))
					engine.environment.poke(frame, "AbsoluteCanvasSize", V2.new(624, 220))
					expect(frame.CanvasPosition):toBe(V2.zero)
					stop()
				end,
			})

			it("gives a fill-height child the padded window as a floor so its bottom stays reachable", {
				id = "native_layout::ScrollView::gives a fill-height child the padded window as a floor so its bottom stays reachable",
				run = function()
					local roblox = require("./lib/native_engine").types
					local root, engine, stop = build(nil, function(UI, Host)
						return UI.ScrollView "Page" {
							padding = 16,
							Host.Frame {
								Name = "Body",
								Size = roblox.UDim2.fromScale(1, 1),
								AutomaticSize = roblox.Enum.AutomaticSize.Y,
							},
						}
					end)
					local V2 = engine.types.Vector2
					local body = root:FindFirstChild("Body")
					expect(body.Size):toBe(engine.types.UDim2.new(1, 0, 0, 0))
					engine.environment.poke(root, "AbsoluteSize", V2.new(389, 648))
					expect(child(body, "UISizeConstraint").MinSize):toBe(V2.new(0, 616))
					stop()
				end,
			})

			it("lets a fill-height stack grow its scroll canvas around constrained content", {
				id = "native_layout::ScrollView::lets a fill-height stack grow its scroll canvas around constrained content",
				run = function()
					local root, engine, stop = build(nil, function(UI, Host)
						return UI.ScrollView {
							UI.VStack {
								Name = "Page",
								width = "fill" :: "fill",
								height = "fill" :: "fill",
								UI.fill(),
								Host.Frame { Size = require("./lib/native_engine").types.UDim2.new(1, 0, 0, 500) },
								UI.VStack {
									Name = "Pane",
									height = "fill" :: "fill",
									UI.fill(),
									Host.UISizeConstraint {
										MinSize = require("./lib/native_engine").types.Vector2.new(0, 320),
									},
								},
							},
						}
					end)
					local page = root:FindFirstChild("Page")
					expect(page.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.Y)
					expect(page:FindFirstChildWhichIsA("UIFlexItem").FlexMode):toBe(engine.types.Enum.UIFlexMode.Grow)
					engine.environment.poke(root, "AbsoluteSize", engine.types.Vector2.new(390, 600))
					expect(page:FindFirstChildWhichIsA("UISizeConstraint").MinSize.Y):toBe(600)
					stop()
				end,
			})

			it("lets a grown fill-height child shrink back when the padded window shrinks", {
				id = "native_layout::ScrollView::lets a grown fill-height child shrink back when the padded window shrinks",
				run = function()
					local roblox = require("./lib/native_engine").types
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local gui = (engine.new("GuiService") :: unknown) :: GuiService
					local UI = Facet.controls(
						runtime,
						{
							types = engine.types,
							guiService = gui,
							services = { GuiService = gui, RunService = { Heartbeat = engine.heartbeat } },
						} :: any
					)
					local root: any
					runtime.mount(function()
						root = UI.ScrollView "Page" {
							padding = 16,
							Facet.host(runtime).Frame {
								Name = "Body",
								Size = roblox.UDim2.fromScale(1, 1),
								AutomaticSize = roblox.Enum.AutomaticSize.Y,
							},
						}
						return root
					end, engine.new("ScreenGui"))
					local V2, E = engine.types.Vector2, engine.types.Enum
					local body = root:FindFirstChild("Body")
					engine.environment.poke(root, "AbsoluteSize", V2.new(389, 648))
					expect(child(body, "UISizeConstraint").MinSize):toBe(V2.new(0, 616))
					engine.environment.poke(root, "AbsoluteSize", V2.new(749, 300))
					expect(child(body, "UISizeConstraint").MinSize):toBe(V2.new(0, 268))
					expect(body.AutomaticSize):toBe(E.AutomaticSize.None)
					expect(body.Size.Y.Offset):toBe(268)
					engine.heartbeat:Fire(1 / 60)
					expect(body.AutomaticSize):toBe(E.AutomaticSize.Y)
					expect(body.Size):toBe(engine.types.UDim2.new(1, 0, 0, 0))
					engine.environment.poke(root, "AbsoluteSize", V2.new(389, 648))
					expect(body.AutomaticSize):toBe(E.AutomaticSize.Y)
					runtime:dispose()
				end,
			})

			it("a fill-height child's shrink keeps the scroll, its own size constraint and a bound size", {
				id = "native_layout::ScrollView::a fill-height child's shrink keeps the scroll, its own size constraint and a bound size",
				run = function()
					local roblox = require("./lib/native_engine").types
					local height = Compose.cell(0)
					local root, engine, stop = build(nil, function(UI, Host)
						return UI.ScrollView "Page" {
							padding = 16,
							Host.Frame {
								Name = "Body",
								Size = roblox.UDim2.fromScale(1, 1),
								AutomaticSize = roblox.Enum.AutomaticSize.Y,
								Host.UISizeConstraint { MinSize = roblox.Vector2.new(10, 700) },
							},
							Host.Frame {
								Name = "Bound",
								Size = function(use: Use)
									return roblox.UDim2.new(1, 0, if use(height) > 0 then 0 else 1, use(height))
								end,
								AutomaticSize = roblox.Enum.AutomaticSize.Y,
							},
						}
					end)
					local V2, E = engine.types.Vector2, engine.types.Enum
					local body, bound = root:FindFirstChild("Body"), root:FindFirstChild("Bound")
					local constraints = 0
					for _, node in body:GetChildren() do
						if node:IsA("UISizeConstraint") then
							constraints += 1
						end
					end
					expect(constraints):toBe(1)
					engine.environment.poke(root, "AbsoluteSize", V2.new(389, 648))
					expect(child(body, "UISizeConstraint").MinSize):toBe(V2.new(10, 700))
					engine.environment.poke(root, "AbsoluteSize", V2.new(389, 1000))
					expect(child(body, "UISizeConstraint").MinSize):toBe(V2.new(10, 968))
					height:set(120)
					root.CanvasPosition = V2.new(0, 200)
					engine.environment.poke(root, "AbsoluteSize", V2.new(749, 300))
					expect(bound.AutomaticSize):toBe(E.AutomaticSize.Y)
					expect(bound.Size.Y.Offset):toBe(120)
					expect(body.AutomaticSize):toBe(E.AutomaticSize.None)
					root.CanvasPosition = V2.new(0, 0)
					engine.heartbeat:Fire(1 / 60)
					expect(body.AutomaticSize):toBe(E.AutomaticSize.Y)
					engine.heartbeat:Fire(1 / 60)
					expect(root.CanvasPosition):toBe(V2.new(0, 200))
					stop()
				end,
			})

			it("runs a horizontal axis as a horizontal list with a horizontal canvas", {
				id = "native_layout::ScrollView::runs a horizontal axis as a horizontal list with a horizontal canvas",
				run = function()
					local root, engine, stop = build(nil, function(UI)
						return UI.ScrollView { axis = "x" :: "x" }
					end)
					local E = engine.types.Enum
					expect(child(root, "UIListLayout").FillDirection):toBe(E.FillDirection.Horizontal)
					expect(root.AutomaticCanvasSize):toBe(E.AutomaticSize.X)
					expect(root.ScrollingDirection):toBe(E.ScrollingDirection.X)
					expect(root.HorizontalScrollBarInset):toBe(E.ScrollBarInset.ScrollBar)
					expect(root.AutomaticSize):toBe(E.AutomaticSize.Y)
					expect(root.Size.Y.Scale == 0 and root.Size.X.Scale == 1):toBe(true)
					stop()
					local filled = build(nil, function(UI)
						return UI.ScrollView {
							axis = "x" :: "x",
							UI.VStack { height = "fill" :: "fill", UI.Text { text = "A" } },
						}
					end)
					expect(filled.AutomaticSize):toBe(E.AutomaticSize.None)
					expect(filled.Size.Y.Scale):toBe(1)
					local both = build(nil, function(UI)
						return UI.ScrollView { axis = "xy" :: "xy" }
					end)
					expect(both.AutomaticCanvasSize):toBe(E.AutomaticSize.XY)
					expect(both.ScrollingDirection):toBe(E.ScrollingDirection.XY)
				end,
			})
		end)

		describe("Grid", function()
			it("fills columns first with flow column and follows the child count", {
				id = "native_layout::Grid::fills columns first with flow column and follows the child count",
				run = function()
					local root, engine, stop = build(nil, function(UI, Host)
						return UI.Grid "Board" {
							columns = 2,
							flow = "column" :: "column",
							Host.Frame { Name = "A" },
							Host.Frame { Name = "B" },
							Host.Frame { Name = "C" },
							Host.Frame { Name = "D" },
							Host.Frame { Name = "E" },
						}
					end)
					local E = engine.types.Enum
					local grid = child(root, "UIGridLayout")
					expect(grid.FillDirection):toBe(E.FillDirection.Vertical)
					expect(grid.FillDirectionMaxCells):toBe(3)
					expect(grid.CellSize.X.Scale):toBeCloseTo(1 / 2, 1e-4)
					local extra = engine.new("Frame")
					extra.Parent = root
					local more = engine.new("Frame")
					more.Parent = root
					expect(grid.FillDirectionMaxCells):toBe(4)
					more.Parent = nil
					extra.Parent = nil
					expect(grid.FillDirectionMaxCells):toBe(3)
					stop()
					expect((mentions(
						refusal(function(UI: FacetControls)
							local grid: Facet.GridProps = { columns = 2, flow = "diagonal" :: any }
							return UI.Grid(grid)
						end),
						"flow must be row or column"
					))):toBe(true)
				end,
			})
		end)

		describe("layout paint belongs to the StyleSheet", function()
			local styleRules = require("./lib/style_rules")

			local function painted(engine: any, sheet: any, node: any, property: string): any
				local default = engine.new(node.ClassName)[property]
				if node[property] ~= default then
					return node[property]
				end
				local ruled = styleRules.resolve(sheet, node, property)
				return if ruled == nil then default else ruled
			end
			local primitives: { [string]: (any, any) -> any } = {
				VStack = function(UI)
					return UI.VStack { UI.Text { text = "A" } }
				end,
				HStack = function(UI)
					return UI.HStack { UI.Text { text = "A" } }
				end,
				ZStack = function(UI)
					return UI.ZStack { UI.Text { text = "A" } }
				end,
				Screen = function(UI)
					return UI.Screen { UI.Text { text = "A" } }
				end,
				ScrollView = function(UI)
					return UI.ScrollView { UI.Text { text = "A" } }
				end,
				Grid = function(UI)
					return UI.Grid { columns = 2, UI.Text { text = "A" } }
				end,
				AdaptiveStack = function(UI)
					return UI.AdaptiveStack { UI.Text { text = "A" } }
				end,
				ViewThatFits = function(UI)
					return UI.ViewThatFits { UI.Text { text = "A" } }
				end,
				Spacer = function(UI)
					return UI.Spacer {}
				end,
				ErrorBoundary = function(UI)
					return UI.ErrorBoundary {
						view = function()
							return UI.Text { text = "A" }
						end,
						fallback = function()
							return UI.Text { text = "B" }
						end,
					}
				end,
				Region = function(UI)
					return UI.Region { zone = "center" :: "center", rank = 1, UI.Text { text = "A" } }
				end,
				Composition = function(UI)
					return UI.Composition { UI.Region { zone = "center" :: "center", rank = 1, UI.Text { text = "A" } } }
				end,
			}
		end)
	end)
end
