--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local cells = require("./lib/cells")
	local Compose: ComposeModule = Facet.Compose
	local themes = Facet.themes

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

	local function build(options: { [string]: any }?, body: (any, any) -> any): (any, any, () -> (), any)
		local engine, runtime, UI = make(options)
		local root: any
		local unmount = runtime.mount(function()
			root = body(UI, runtime.constructors)
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

	local function wide(): any
		return assert(themes.define({
			identity = { id = "wide-spacing" },
			metrics = { space = { xs = 6, s = 12, m = 20, l = 30, xl = 48 } },
		} :: any))
	end

	local function refusal(body: (any, any) -> any): string?
		local engine, runtime, UI = make()
		local ok, message = pcall(function()
			runtime.mount(function()
				return body(UI, runtime.constructors)
			end, engine.new("ScreenGui"))
		end)
		runtime:dispose()
		return if ok then nil else tostring(message)
	end

	local function painted(root: any): string
		local nodes = {}
		for _, node in root:GetChildren() do
			if node:IsA("GuiObject") then
				table.insert(nodes, node)
			end
		end
		table.sort(nodes, function(a, b)
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

	verifyHarness:suite("native text layout", function()
		verifyHarness:case("reflows automatic text when font metrics change and preserves fixed text", {
			id = "native_layout::native text layout::reflows automatic text when font metrics change and preserves fixed text",
			run = function()
				local Enum = require("@lune/roblox").Enum
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
				Verify.expect(states):toHaveLength(2)
				Verify.expect(states[1]):toBe(engine.types.Enum.AutomaticSize.None)
				Verify.expect(states[2]):toBe(engine.types.Enum.AutomaticSize.XY)
				automatic.TextColor3 = engine.types.Color3.new(1, 0, 0)
				Verify.expect(states):toHaveLength(2)
				fixed.TextSize = 12
				Verify.expect(fixed.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.None)
				local readout = root.Slider:FindFirstChild("Value", true)
				local internal = {}
				local internalConnection = readout:GetPropertyChangedSignal("AutomaticSize"):Connect(function()
					table.insert(internal, readout.AutomaticSize)
				end)
				readout.TextSize = 12
				Verify.expect(internal):toHaveLength(2)
				Verify.expect(internal[1]):toBe(engine.types.Enum.AutomaticSize.None)
				Verify.expect(internal[2]):toBe(engine.types.Enum.AutomaticSize.XY)
				frames.heartbeat:Fire(1 / 60)
				Verify.expect(states):toHaveLength(4)
				Verify.expect(internal):toHaveLength(4)
				Verify.expect(engineLib.connections(frames.heartbeat)):toBe(0)
				frames.heartbeat:Fire(1 / 60)
				Verify.expect(states):toHaveLength(4)
				Verify.expect(internal):toHaveLength(4)
				automatic.TextSize = 14
				stop()
				local released = #states
				frames.heartbeat:Fire(1 / 60)
				Verify.expect(states):toHaveLength(released)
				Verify.expect(engineLib.connections(frames.heartbeat)):toBe(0)
				internalConnection:Disconnect()
				connection:Disconnect()
				stop()
			end,
		})
	end)
	verifyHarness:suite("native maximum layout width", function()
		verifyHarness:case("caps every sized container with one reactive native constraint", {
			id = "native_layout::native maximum layout width::caps every sized container with one reactive native constraint",
			run = function()
				for _, name in
					{
						"Screen",
						"VStack",
						"HStack",
						"ZStack",
						"ScrollView",
						"Grid",
						"AdaptiveStack",
						"ViewThatFits",
						"ErrorBoundary",
					}
				do
					local maximum = Compose.cell(480)
					local root, engine, stop = build(nil, function(UI: FacetControls, Host: RobloxHost)
						local spec = {
							width = "fill" :: "fill",
							height = 120,
							maxWidth = function(use: Use)
								return use(maximum)
							end,
						}
						if name == "Grid" then
							spec.columns = 2
						end
						if name == "ViewThatFits" then
							spec[1] = Host.Frame({})
						end
						if name == "ErrorBoundary" then
							spec.view = function()
								return Host.Frame({})
							end
							spec.fallback = function()
								return Host.Frame({})
							end
						end
						return UI[name](spec)
					end)
					local cap = child(root, "UISizeConstraint")
					Verify.expect(cap ~= nil):toBe(true)
					Verify.expect(root.Size):toBe(engine.types.UDim2.new(1, 0, 0, 120))
					Verify.expect(cap.MaxSize):toBe(engine.types.Vector2.new(480, math.huge))
					maximum:set(300)
					Verify.expect((child(root, "UISizeConstraint"))):toBe(cap)
					Verify.expect(cap.MaxSize.X):toBe(300)
					stop()
				end
			end,
		})

		verifyHarness:case("keeps fixed width semantics and does not add a cap unless requested", {
			id = "native_layout::native maximum layout width::keeps fixed width semantics and does not add a cap unless requested",
			run = function()
				local maximum = Compose.cell(480)
				local root, engine, stop = build(nil, function(UI: FacetControls)
					return UI.VStack {
						width = 600,
						UI.HStack { width = 600, maxWidth = maximum } :: unknown,
						UI.ZStack { width = "fill" :: "fill", maxWidth = 0 },
					}
				end)
				Verify.expect(root.Size.X.Offset):toBe(600)
				Verify.expect((child(root, "UISizeConstraint"))):toBeNil()
				local rows = {}
				for _, node in root:GetChildren() do
					if node:IsA("GuiObject") then
						rows[node.LayoutOrder] = node
					end
				end
				Verify.expect(rows[1].Size.X.Offset):toBe(600)
				maximum:set(320)
				Verify.expect(child(rows[1], "UISizeConstraint").MaxSize.X):toBe(320)
				Verify.expect(rows[1].Size.X.Offset):toBe(600)
				Verify.expect(child(rows[2], "UISizeConstraint").MaxSize.X):toBe(0)
				stop()
			end,
		})

		verifyHarness:case("rejects invalid maximum widths before passing them to Roblox", {
			id = "native_layout::native maximum layout width::rejects invalid maximum widths before passing them to Roblox",
			run = function()
				for _, maximum in { -1 :: any, math.huge, 0 / 0, "fill", false } :: { unknown } do
					Verify.expect((mentions(
						refusal(function(UI: FacetControls)
							return UI.VStack({ maxWidth = maximum } :: any)
						end),
						"maxWidth must be a finite number"
					))):toBe(true)
				end
			end,
		})
	end)

	verifyHarness:suite("native layout primitives", function()
		verifyHarness:suite("VStack and HStack", function()
			verifyHarness:case("build a plain Frame with a list layout and number the children in declaration order", {
				id = "native_layout::VStack and HStack::build a plain Frame with a list layout and number the children in declaration order",
				run = function()
					local root, engine, stop = build(nil, function(UI: FacetControls)
						return UI.VStack {
							UI.Text { text = "One" } :: unknown,
							UI.Text { text = "Two" },
							UI.Button { label = "Three", onActivate = function() end },
						}
					end)
					local E = engine.types.Enum
					Verify.expect(root.ClassName):toBe("Frame")
					Verify.expect((root:HasTag("facet-layout"))):toBe(true)
					Verify.expect(root.BorderSizePixel):toBe(0)
					Verify.expect(root.Size):toBe(engine.types.UDim2.new(0, 0, 0, 0))
					Verify.expect(root.AutomaticSize):toBe(E.AutomaticSize.XY)
					local layout = child(root, "UIListLayout")
					Verify.expect(layout.FillDirection):toBe(E.FillDirection.Vertical)
					Verify.expect(layout.SortOrder):toBe(E.SortOrder.LayoutOrder)
					Verify.expect(layout.Padding):toBe(engine.types.UDim.new(0, 0))
					Verify.expect((child(root, "UIPadding"))):toBeNil()
					local orders = {}
					for _, node in root:GetChildren() do
						if node:IsA("GuiObject") then
							orders[node.Text] = node.LayoutOrder
						end
					end
					Verify.expect(orders):toEqual({ One = 1, Two = 2, Three = 3 })
					stop()
				end,
			})

			verifyHarness:case("lays an HStack out horizontally and accepts a constructor name", {
				id = "native_layout::VStack and HStack::lays an HStack out horizontally and accepts a constructor name",
				run = function()
					local root, engine, stop = build(nil, function(UI: FacetControls)
						return UI.HStack "Toolbar" { gap = 4, UI.Text { text = "A" } }
					end)
					Verify.expect(root.Name):toBe("Toolbar")
					Verify.expect(child(root, "UIListLayout").FillDirection)
						:toBe(engine.types.Enum.FillDirection.Horizontal)
					Verify.expect(child(root, "UIListLayout").Padding):toBe(engine.types.UDim.new(0, 4))
					stop()
				end,
			})

			verifyHarness:case("resolves gap and padding spacing steps from the theme package", {
				id = "native_layout::VStack and HStack::resolves gap and padding spacing steps from the theme package",
				run = function()
					local root, engine, stop = build(nil, function(UI: FacetControls)
						return UI.VStack { gap = "s", padding = "m", UI.Text { text = "A" } }
					end)
					local space = themes.neutralPackage().metrics.space
					local padding = child(root, "UIPadding")
					Verify.expect(child(root, "UIListLayout").Padding):toBe(engine.types.UDim.new(0, space.s))
					for _, side in { "PaddingTop", "PaddingRight", "PaddingBottom", "PaddingLeft" } do
						Verify.expect(padding[side]):toBe(engine.types.UDim.new(0, space.m))
					end
					stop()
				end,
			})

			verifyHarness:case("pads each side on its own and keeps literal pixel values", {
				id = "native_layout::VStack and HStack::pads each side on its own and keeps literal pixel values",
				run = function()
					local root, engine, stop = build(nil, function(UI: FacetControls)
						return UI.VStack { gap = 7, padding = { left = "xs", top = 3 } }
					end)
					local padding = child(root, "UIPadding")
					local D = engine.types.UDim
					Verify.expect(child(root, "UIListLayout").Padding):toBe(D.new(0, 7))
					Verify.expect(padding.PaddingLeft):toBe(D.new(0, themes.neutralPackage().metrics.space.xs))
					Verify.expect(padding.PaddingTop):toBe(D.new(0, 3))
					Verify.expect(padding.PaddingRight):toBe(D.new(0, 0))
					Verify.expect(padding.PaddingBottom):toBe(D.new(0, 0))
					stop()
				end,
			})

			verifyHarness:case("moves gap and padding when the theme package changes", {
				id = "native_layout::VStack and HStack::moves gap and padding when the theme package changes",
				run = function()
					local theme = Compose.cell(themes.neutralPackage())
					local root, engine, stop = build({ theme = theme }, function(UI: FacetControls)
						return UI.VStack { gap = "s", padding = { left = "m" }, UI.Text { text = "A" } }
					end)
					local D = engine.types.UDim
					local layout, padding = child(root, "UIListLayout"), child(root, "UIPadding")
					Verify.expect(layout.Padding):toBe(D.new(0, 8))
					Verify.expect(padding.PaddingLeft):toBe(D.new(0, 16))
					theme:set(wide())
					Verify.expect((child(root, "UIListLayout"))):toBe(layout)
					Verify.expect(layout.Padding):toBe(D.new(0, 12))
					Verify.expect(padding.PaddingLeft):toBe(D.new(0, 20))
					stop()
				end,
			})

			verifyHarness:case("maps align and distribute to the native list alignment and flex", {
				id = "native_layout::VStack and HStack::maps align and distribute to the native list alignment and flex",
				run = function()
					local align = Compose.cell("center" :: "center" | "end" | "start" | "stretch")
					local root, engine, stop = build(nil, function(UI: FacetControls)
						return UI.HStack {
							align = align,
							distribute = "spaceBetween" :: "spaceBetween",
							UI.Text { text = "A" },
						}
					end)
					local E = engine.types.Enum
					local layout = child(root, "UIListLayout")
					Verify.expect(layout.VerticalAlignment):toBe(E.VerticalAlignment.Center)
					Verify.expect(layout.ItemLineAlignment):toBe(E.ItemLineAlignment.Automatic)
					Verify.expect(layout.HorizontalFlex):toBe(E.UIFlexAlignment.SpaceBetween)
					Verify.expect(layout.HorizontalAlignment):toBe(E.HorizontalAlignment.Left)
					Verify.expect(layout.VerticalFlex):toBe(E.UIFlexAlignment.None)
					align:set("stretch")
					Verify.expect(layout.ItemLineAlignment):toBe(E.ItemLineAlignment.Stretch)
					Verify.expect(layout.VerticalFlex):toBe(E.UIFlexAlignment.Fill)
					Verify.expect(layout.HorizontalFlex):toBe(E.UIFlexAlignment.SpaceBetween)
					Verify.expect(layout.VerticalAlignment):toBe(E.VerticalAlignment.Top)
					align:set("end")
					Verify.expect(layout.VerticalAlignment):toBe(E.VerticalAlignment.Bottom)
					Verify.expect(layout.VerticalFlex):toBe(E.UIFlexAlignment.None)
					stop()
					local column = build(nil, function(UI: FacetControls)
						return UI.VStack { align = "end" :: "end", distribute = "center" :: "center" }
					end)
					local list = child(column, "UIListLayout")
					Verify.expect(list.HorizontalAlignment):toBe(E.HorizontalAlignment.Right)
					Verify.expect(list.VerticalAlignment):toBe(E.VerticalAlignment.Center)
					Verify.expect(list.VerticalFlex):toBe(E.UIFlexAlignment.None)
				end,
			})

			verifyHarness:case("spreads the leftover space with every native flex distribution", {
				id = "native_layout::VStack and HStack::spreads the leftover space with every native flex distribution",
				run = function()
					local E = engineLib.new().types.Enum
					for name, flex in
						{
							spaceBetween = E.UIFlexAlignment.SpaceBetween,
							spaceAround = E.UIFlexAlignment.SpaceAround,
							spaceEvenly = E.UIFlexAlignment.SpaceEvenly,
						}
					do
						local row, _, stopRow = build(nil, function(UI: FacetControls)
							return UI.HStack { distribute = name :: "spaceBetween" | "spaceAround" | "spaceEvenly" }
						end)
						Verify.expect(child(row, "UIListLayout").HorizontalFlex):toBe(flex)
						stopRow()
						local column, _, stopColumn = build(nil, function(UI: FacetControls)
							return UI.VStack { distribute = name :: "spaceBetween" | "spaceAround" | "spaceEvenly" }
						end)
						Verify.expect(child(column, "UIListLayout").VerticalFlex):toBe(flex)
						stopColumn()
					end
					local screen, _, stopScreen = build(nil, function(UI: FacetControls)
						return UI.Screen { distribute = "end" :: "end" }
					end)
					Verify.expect(child(screen, "UIListLayout").VerticalAlignment):toBe(E.VerticalAlignment.Bottom)
					stopScreen()
				end,
			})

			verifyHarness:case("accepts distribute only on the list containers", {
				id = "native_layout::VStack and HStack::accepts distribute only on the list containers",
				run = function()
					Verify.expect((mentions(
						refusal(function(UI: FacetControls)
							return UI.ZStack { distribute = "center" :: "center" }
						end),
						"distribute"
					))):toBe(true)
					Verify.expect((mentions(
						refusal(function(UI: FacetControls)
							return UI.Grid { columns = 2, distribute = "center" :: "center" }
						end),
						"distribute"
					))):toBe(true)
					Verify.expect((refusal(function(UI: FacetControls)
						return UI.ScrollView { distribute = "center" :: "center" }
					end))):toBeNil()
				end,
			})

			verifyHarness:case("writes no alignment property that the author did not ask for", {
				id = "native_layout::VStack and HStack::writes no alignment property that the author did not ask for",
				run = function()
					local root, engine, stop = build(nil, function(UI: FacetControls)
						return UI.VStack {}
					end)
					local E = engine.types.Enum
					local layout = child(root, "UIListLayout")
					local native = engine.new("UIListLayout")
					Verify.expect(layout.HorizontalAlignment):toBe(native.HorizontalAlignment)
					Verify.expect(layout.VerticalAlignment):toBe(native.VerticalAlignment)
					Verify.expect(layout.ItemLineAlignment):toBe(native.ItemLineAlignment)
					Verify.expect(layout.HorizontalFlex):toBe(E.UIFlexAlignment.None)
					Verify.expect(layout.Wraps):toBe(false)
					stop()
				end,
			})

			verifyHarness:case("sizes by fill, hug and pixels on each axis", {
				id = "native_layout::VStack and HStack::sizes by fill, hug and pixels on each axis",
				run = function()
					local width = Compose.cell("fill" :: any)
					local root, engine, stop = build(nil, function(UI: FacetControls)
						return UI.VStack { width = width, height = 40 }
					end)
					local E, D2 = engine.types.Enum, engine.types.UDim2
					Verify.expect(root.Size):toBe(D2.new(1, 0, 0, 40))
					Verify.expect(root.AutomaticSize):toBe(E.AutomaticSize.None)
					width:set(120)
					Verify.expect(root.Size):toBe(D2.new(0, 120, 0, 40))
					width:set("hug")
					Verify.expect(root.AutomaticSize):toBe(E.AutomaticSize.X)
					stop()
				end,
			})

			verifyHarness:case("passes native properties through and lets them win over the defaults", {
				id = "native_layout::VStack and HStack::passes native properties through and lets them win over the defaults",
				run = function()
					local D2 = engineLib.new().types.UDim2
					local root, engine, stop = build(nil, function(UI: FacetControls)
						return UI.VStack { BackgroundTransparency = 0.25, Size = D2.fromOffset(10, 10) }
					end)
					Verify.expect(root.BackgroundTransparency):toBe(0.25)
					Verify.expect(root.Size):toBe(engine.types.UDim2.fromOffset(10, 10))
					stop()
				end,
			})

			verifyHarness:case("numbers the nodes that a Compose directive child adds later", {
				id = "native_layout::VStack and HStack::numbers the nodes that a Compose directive child adds later",
				run = function()
					local shown = Compose.cell(false)
					local root, _, stop = build(nil, function(UI: FacetControls)
						return UI.VStack {
							UI.Text { text = "First" } :: unknown,
							Compose.show(shown, function()
								return UI.Text { text = "Middle" }
							end),
							UI.Text { text = "Last" },
						}
					end)
					shown:set(true)
					Verify.expect((painted(root))):toBe("First Middle Last")
					stop()
				end,
			})

			verifyHarness:case(
				"keeps a keyed child's rows in keyed order between their siblings, and a row's own LayoutOrder wins",
				{
					id = "native_layout::VStack and HStack::keeps a keyed child's rows in keyed order between their siblings, and a row's own LayoutOrder wins",
					run = function()
						local items = Compose.cell({ "A", "B", "C" })
						local root, _, stop = build(nil, function(UI: FacetControls)
							return UI.VStack {
								UI.Text { text = "Top" } :: unknown,
								Compose.keyed({
									from = items,
									render = function(value, index): GuiObject
										return UI.Text {
											text = value,
											LayoutOrder = index,
										}
									end,
								}),
								Compose.keyed({
									from = items,
									render = function(value): GuiObject
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
						Verify.expect((painted(root))):toBe("Top A B C a b c End")
						items:set({ "B", "C", "A" })
						Verify.expect((painted(root))):toBe("Top B C A b c a End")
						items:set({ "C", "D", "B" })
						Verify.expect((painted(root))):toBe("Top C D B c d b End")
						stop()
					end,
				}
			)

			verifyHarness:case("refuses an unknown spacing step, alignment or option and names the vocabulary", {
				id = "native_layout::VStack and HStack::refuses an unknown spacing step, alignment or option and names the vocabulary",
				run = function()
					local engine, runtime, UI = make()
					local function refused(body: () -> any, fragment: string)
						local ok, message = pcall(function()
							runtime.mount(body, engine.new("ScreenGui"))
						end)
						Verify.expect(ok):toBe(false)
						Verify.expect(string.find(tostring(message), fragment, 1, true) ~= nil):toBe(true)
					end
					refused(function()
						return UI.VStack { gap = "enormous" }
					end, "xs, s, m, l, xl")
					refused(function()
						return UI.VStack { padding = "enormous" }
					end, "enormous")
					refused(function()
						return UI.VStack { padding = { left = "enormous" } }
					end, "enormous")
					refused(function()
						return UI.HStack { align = "middle" :: "middle" }
					end, "start, center, end or stretch")
					refused(function()
						return UI.VStack { distribute = "around" :: "around" }
					end, "spaceBetween")
					refused(function()
						return UI.VStack { width = "stretch" :: "stretch" }
					end, "fill, hug")
					refused(function()
						return UI.VStack { gpa = "s" }
					end, "gpa")
					runtime:dispose()
				end,
			})
		end)

		verifyHarness:suite("fill", function()
			verifyHarness:case("refuses a weight that is not a positive number", {
				id = "native_layout::fill::refuses a weight that is not a positive number",
				run = function()
					Verify.expect((mentions(
						refusal(function(UI: FacetControls)
							return UI.HStack { UI.Text { text = "A", UI.fill(0) } }
						end),
						"positive"
					))):toBe(true)
					Verify.expect((mentions(
						refusal(function(UI: FacetControls)
							return UI.HStack { UI.Text { text = "A", UI.fill(-1) } }
						end),
						"positive"
					))):toBe(true)
				end,
			})

			verifyHarness:case("makes a native flex item that fills the main axis, by weight when given", {
				id = "native_layout::fill::makes a native flex item that fills the main axis, by weight when given",
				run = function()
					local root, engine, stop = build(nil, function(UI: FacetControls)
						return UI.HStack {
							UI.Text { text = "A", UI.fill() } :: unknown,
							UI.Text { text = "B", UI.fill(2) },
						}
					end)
					local E = engine.types.Enum
					local items = {}
					for _, node in root:GetChildren() do
						if node:IsA("GuiObject") then
							items[node.Text] = child(node, "UIFlexItem")
						end
					end
					Verify.expect(items.A.FlexMode):toBe(E.UIFlexMode.Fill)
					Verify.expect(items.B.FlexMode):toBe(E.UIFlexMode.Custom)
					Verify.expect(items.B.GrowRatio):toBe(2)
					Verify.expect(items.B.ShrinkRatio):toBe(2)
					stop()
				end,
			})
		end)

		verifyHarness:suite("Screen", function()
			verifyHarness:case("fills its parent, pads the content by the m step and stacks vertically", {
				id = "native_layout::Screen::fills its parent, pads the content by the m step and stacks vertically",
				run = function()
					local root, engine, stop = build(nil, function(UI: FacetControls)
						return UI.Screen "Home" { gap = "s", UI.Text { text = "A" } }
					end)
					local E = engine.types.Enum
					Verify.expect(root.Name):toBe("Home")
					Verify.expect(root.Size):toBe(engine.types.UDim2.fromScale(1, 1))
					Verify.expect(root.AutomaticSize):toBe(E.AutomaticSize.None)
					Verify.expect((root:HasTag("facet-layout"))):toBe(true)
					Verify.expect(child(root, "UIPadding").PaddingTop):toBe(engine.types.UDim.new(0, 16))
					Verify.expect(child(root, "UIListLayout").FillDirection):toBe(E.FillDirection.Vertical)
					Verify.expect(child(root, "UIListLayout").Padding):toBe(engine.types.UDim.new(0, 8))
					stop()
					local bare = build(nil, function(UI: FacetControls)
						return UI.Screen { padding = 0 }
					end)
					Verify.expect(child(bare, "UIPadding").PaddingLeft):toBe(engine.types.UDim.new(0, 0))
				end,
			})

			verifyHarness:case("keeps its content below the engine top bar, the background still fills", {
				id = "native_layout::Screen::keeps its content below the engine top bar, the background still fills",
				run = function()
					for _, ignoresInset in { true, false } do
						local engine: any = engineLib.new()
						local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
						local gui = engine.new("GuiService")
						local T = engine.types
						local insetTop = if ignoresInset then 58 else 36
						gui.GetGuiInset = function()
							return T.Vector2.new(0, insetTop), T.Vector2.zero
						end
						gui.TopbarInset = T.Rect.new(104, 0, 1000, 58)
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
						root.AbsolutePosition = T.Vector2.new(0, if ignoresInset then -58 else 0)
						local padding = child(root, "UIPadding")
						Verify.expect(padding.PaddingTop)
							:toBe(T.UDim.new(0, 16 + 58 - insetTop - root.AbsolutePosition.Y))
						Verify.expect(padding.PaddingLeft):toBe(T.UDim.new(0, 16))
						Verify.expect(root.Size):toBe(T.UDim2.fromScale(1, 1))
						gui.TopbarInset = T.Rect.new(0, 0, 0, 0)
						Verify.expect(padding.PaddingTop):toBe(T.UDim.new(0, 16))
						gui.TopbarInset = T.Rect.new(104, 0, 1000, 58)
						root.AbsolutePosition = T.Vector2.new(0, 200)
						Verify.expect(padding.PaddingTop):toBe(T.UDim.new(0, 16))
						runtime:dispose()
					end
				end,
			})

			verifyHarness:case("refreshes top-bar clearance when the native inset changes without a property event", {
				id = "native_layout::Screen::refreshes top-bar clearance when the native inset changes without a property event",
				run = function()
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local gui = engine.new("GuiService")
					local T = engine.types
					local inset = 30
					gui.GetGuiInset = function()
						return T.Vector2.new(0, inset), T.Vector2.zero
					end
					gui.TopbarInset = T.Rect.new(104, 0, 1000, 58)
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
					Verify.expect(padding.PaddingTop):toBe(T.UDim.new(0, 44))
					inset = 58
					engine.heartbeat:Fire(1 / 60)
					Verify.expect(padding.PaddingTop):toBe(T.UDim.new(0, 16))
					inset = 30
					engine.heartbeat:Fire(1 / 60)
					Verify.expect(padding.PaddingTop):toBe(T.UDim.new(0, 44))
					runtime:dispose()
				end,
			})

			verifyHarness:case("chrome band rides the free top-bar band, and edge also drops the overscan", {
				id = "native_layout::Screen::chrome band rides the free top-bar band, and edge also drops the overscan",
				run = function()
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local gui = engine.new("GuiService")
					local input = engine.new("UserInputService")
					local T = engine.types
					gui.GetGuiInset = function()
						return T.Vector2.new(0, 58), T.Vector2.zero
					end
					gui.TopbarInset = T.Rect.new(104, 0, 1000, 58)
					gui.ViewportDisplaySize = T.Enum.DisplaySize.Large
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
						roots[chrome].AbsolutePosition = T.Vector2.new(0, -58)
					end
					local function top(chrome: string): any
						return child(roots[chrome], "UIPadding").PaddingTop
					end
					Verify.expect((top("device"))):toBe(T.UDim.new(60 / 1080, 24 + 58))
					Verify.expect((top("band"))):toBe(T.UDim.new(60 / 1080, 24))
					Verify.expect((top("edge"))):toBe(T.UDim.new(0, 24))
					Verify.expect(child(roots.edge, "UIPadding").PaddingLeft):toBe(T.UDim.new(0, 24))
					Verify.expect((pcall(function()
						runtime.mount(function()
							return UI.Screen({ chrome = "glass" } :: any)
						end, layer)
					end))):toBe(false)
					runtime:dispose()
				end,
			})

			verifyHarness:case("clears only the remaining overscan at each edge, including nested screens", {
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
					layer.AbsoluteSize = T.Vector2.new(1920, 1080)
					local nested
					local stop, root: any = runtime.mount(function()
						nested = UI.Screen { padding = 0 }
						return UI.Screen { padding = 0, nested :: unknown }
					end, layer)
					root.AbsoluteSize = layer.AbsoluteSize
					nested.AbsoluteSize = T.Vector2.new(1700, 900)
					nested.AbsolutePosition = T.Vector2.new(100, 100)
					local outer, inner = child(root, "UIPadding"), child(nested, "UIPadding")
					Verify.expect(outer.PaddingTop):toBe(T.UDim.new(0, 60))
					Verify.expect(outer.PaddingLeft):toBe(T.UDim.new(0, 90))
					Verify.expect(inner.PaddingTop):toBe(T.UDim.new(0, 0))
					Verify.expect(inner.PaddingLeft):toBe(T.UDim.new(0, 0))
					nested.AbsolutePosition = T.Vector2.new(30, 20)
					Verify.expect(inner.PaddingTop):toBe(T.UDim.new(0, 40))
					Verify.expect(inner.PaddingLeft):toBe(T.UDim.new(0, 60))
					margins:set({ top = 30, left = 40, bottom = 30, right = 40 })
					Verify.expect(inner.PaddingTop):toBe(T.UDim.new(0, 10))
					Verify.expect(inner.PaddingLeft):toBe(T.UDim.new(0, 10))
					margins:set(nil)
					distance:set("near")
					Verify.expect(outer.PaddingTop):toBe(T.UDim.new(0, 0))
					Verify.expect(inner.PaddingLeft):toBe(T.UDim.new(0, 0))
					stop()
					runtime:dispose()
				end,
			})

			verifyHarness:case("ignores the top bar on a SurfaceGui", {
				id = "native_layout::Screen::ignores the top bar on a SurfaceGui",
				run = function()
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local gui = engine.new("GuiService")
					local T = engine.types
					gui.GetGuiInset = function()
						return T.Vector2.zero, T.Vector2.zero
					end
					gui.TopbarInset = T.Rect.new(104, 0, 1000, 58)
					local UI =
						Facet.controls(runtime, { types = T, guiService = gui, services = { GuiService = gui } } :: any)
					local root: any
					runtime.mount(function()
						root = UI.Screen {}
						return root
					end, engine.new("SurfaceGui"))
					Verify.expect(child(root, "UIPadding").PaddingTop):toBe(T.UDim.new(0, 16))
					runtime:dispose()
				end,
			})
		end)

		verifyHarness:suite("ZStack", function()
			verifyHarness:case("layers later children above earlier ones and keeps an authored ZIndex", {
				id = "native_layout::ZStack::layers later children above earlier ones and keeps an authored ZIndex",
				run = function()
					local root, _, stop = build(nil, function(UI: FacetControls, Host: RobloxHost)
						return UI.ZStack {
							Host.Frame { Name = "Back" } :: unknown,
							Host.Frame { Name = "Front" },
							Host.Frame { Name = "Pinned", ZIndex = 9 },
						}
					end)
					Verify.expect(root:FindFirstChild("Back").ZIndex):toBe(1)
					Verify.expect(root:FindFirstChild("Front").ZIndex):toBe(2)
					Verify.expect(root:FindFirstChild("Pinned").ZIndex):toBe(9)
					Verify.expect((child(root, "UIListLayout"))):toBeNil()
					stop()
				end,
			})

			verifyHarness:case("refuses an alignment outside start, center and end", {
				id = "native_layout::ZStack::refuses an alignment outside start, center and end",
				run = function()
					Verify.expect((mentions(
						refusal(function(UI: FacetControls, Host: RobloxHost)
							return UI.ZStack({ alignH = "stretch" :: "stretch", Host.Frame {} } :: any)
						end),
						"start, center or end"
					))):toBe(true)
				end,
			})

			verifyHarness:case("aligns every child by anchor point and scale position", {
				id = "native_layout::ZStack::aligns every child by anchor point and scale position",
				run = function()
					local horizontal = Compose.cell("center" :: "center" | "end" | "start")
					local root, engine, stop = build(nil, function(UI: FacetControls, Host: RobloxHost)
						return UI.ZStack {
							width = "fill" :: "fill",
							height = "fill" :: "fill",
							alignH = horizontal,
							alignV = "end" :: "end",
							Host.Frame { Name = "Badge" },
						}
					end)
					local badge = root:FindFirstChild("Badge")
					Verify.expect(badge.AnchorPoint):toBe(engine.types.Vector2.new(0.5, 1))
					Verify.expect(badge.Position):toBe(engine.types.UDim2.fromScale(0.5, 1))
					horizontal:set("end")
					Verify.expect(badge.AnchorPoint):toBe(engine.types.Vector2.new(1, 1))
					Verify.expect(badge.Position):toBe(engine.types.UDim2.fromScale(1, 1))
					stop()
				end,
			})

			verifyHarness:case("aligns children by offset along a hugging axis", {
				id = "native_layout::ZStack::aligns children by offset along a hugging axis",
				run = function()
					local root, engine, stop = build(nil, function(UI: FacetControls, Host: RobloxHost)
						return UI.ZStack {
							width = 60,
							alignH = "end" :: "end",
							alignV = "end" :: "end",
							Host.Frame { Name = "Card" } :: unknown,
							Host.Frame { Name = "Dot" },
						}
					end)
					local V2, D2 = engine.types.Vector2, engine.types.UDim2
					local card, dot = root:FindFirstChild("Card"), root:FindFirstChild("Dot")
					card.AbsoluteSize = V2.new(60, 40)
					dot.AbsoluteSize = V2.new(16, 16)
					Verify.expect(dot.AnchorPoint):toBe(V2.new(1, 0))
					Verify.expect(dot.Position):toBe(D2.new(1, 0, 0, 24))
					Verify.expect(card.Position):toBe(D2.new(1, 0, 0, 0))
					dot.AbsoluteSize = V2.new(16, 50)
					Verify.expect(card.Position):toBe(D2.new(1, 0, 0, 10))
					Verify.expect(dot.Position):toBe(D2.new(1, 0, 0, 0))
					stop()
				end,
			})
		end)

		verifyHarness:suite("ScrollView", function()
			verifyHarness:case("sizes vertical content to the scroll window with a list layout and automatic canvas", {
				id = "native_layout::ScrollView::sizes vertical content to the scroll window with a list layout and automatic canvas",
				run = function()
					local root, engine, stop = build(nil, function(UI: FacetControls)
						return UI.ScrollView "Page" {
							gap = "s",
							padding = "m",
							UI.Text { text = "A" } :: unknown,
							UI.Text { text = "B" },
						}
					end)
					local E, D2 = engine.types.Enum, engine.types.UDim2
					Verify.expect(root.ClassName):toBe("ScrollingFrame")
					Verify.expect(root.Name):toBe("Page")
					Verify.expect(root.Size):toBe(D2.fromScale(1, 1))
					Verify.expect(root.CanvasSize):toBe(D2.new())
					Verify.expect(root.AutomaticCanvasSize):toBe(E.AutomaticSize.Y)
					Verify.expect(root.ScrollingDirection):toBe(E.ScrollingDirection.Y)
					Verify.expect(root.VerticalScrollBarInset):toBe(E.ScrollBarInset.Always)
					Verify.expect((root:HasTag("facet-layout"))):toBe(true)
					local layout = child(root, "UIListLayout")
					Verify.expect(layout.FillDirection):toBe(E.FillDirection.Vertical)
					Verify.expect(layout.Padding):toBe(engine.types.UDim.new(0, 8))
					Verify.expect(child(root, "UIPadding").PaddingTop):toBe(engine.types.UDim.new(0, 16))
					local orders = {}
					for _, node in root:GetChildren() do
						if node:IsA("GuiObject") then
							orders[node.Text] = node.LayoutOrder
						end
					end
					Verify.expect(orders):toEqual({ A = 1, B = 2 })
					stop()
				end,
			})

			verifyHarness:case("gives a fill-height child the padded window as a floor so its bottom stays reachable", {
				id = "native_layout::ScrollView::gives a fill-height child the padded window as a floor so its bottom stays reachable",
				run = function()
					local roblox = require("@lune/roblox")
					local root, engine, stop = build(nil, function(UI: FacetControls, Host: RobloxHost)
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
					Verify.expect(body.Size):toBe(engine.types.UDim2.new(1, 0, 0, 0))
					root.AbsoluteSize = V2.new(389, 648)
					Verify.expect(child(body, "UISizeConstraint").MinSize):toBe(V2.new(0, 616))
					stop()
				end,
			})

			verifyHarness:case("lets a fill-height stack grow its scroll canvas around constrained content", {
				id = "native_layout::ScrollView::lets a fill-height stack grow its scroll canvas around constrained content",
				run = function()
					local root, engine, stop = build(nil, function(UI: FacetControls, Host: RobloxHost)
						return UI.ScrollView {
							UI.VStack {
								Name = "Page",
								width = "fill" :: "fill",
								height = "fill" :: "fill",
								UI.fill() :: unknown,
								Host.Frame { Size = require("@lune/roblox").UDim2.new(1, 0, 0, 500) },
								UI.VStack {
									Name = "Pane",
									height = "fill" :: "fill",
									UI.fill() :: unknown,
									Host.UISizeConstraint { MinSize = require("@lune/roblox").Vector2.new(0, 320) },
								},
							},
						}
					end)
					local page = root:FindFirstChild("Page")
					Verify.expect(page.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.Y)
					Verify.expect(page:FindFirstChildWhichIsA("UIFlexItem").FlexMode)
						:toBe(engine.types.Enum.UIFlexMode.Grow)
					root.AbsoluteSize = engine.types.Vector2.new(390, 600)
					Verify.expect(page:FindFirstChildWhichIsA("UISizeConstraint").MinSize.Y):toBe(600)
					stop()
				end,
			})

			verifyHarness:case("lets a grown fill-height child shrink back when the padded window shrinks", {
				id = "native_layout::ScrollView::lets a grown fill-height child shrink back when the padded window shrinks",
				run = function()
					local roblox = require("@lune/roblox")
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local gui = engine.new("GuiService")
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
							((runtime.constructors.Frame :: unknown) :: FrameConstructor) {
								Name = "Body",
								Size = roblox.UDim2.fromScale(1, 1),
								AutomaticSize = roblox.Enum.AutomaticSize.Y,
							},
						}
						return root
					end, engine.new("ScreenGui"))
					local V2, E = engine.types.Vector2, engine.types.Enum
					local body = root:FindFirstChild("Body")
					root.AbsoluteSize = V2.new(389, 648)
					Verify.expect(child(body, "UISizeConstraint").MinSize):toBe(V2.new(0, 616))
					root.AbsoluteSize = V2.new(749, 300)
					Verify.expect(child(body, "UISizeConstraint").MinSize):toBe(V2.new(0, 268))
					Verify.expect(body.AutomaticSize):toBe(E.AutomaticSize.None)
					Verify.expect(body.Size.Y.Offset):toBe(268)
					engine.heartbeat:Fire(1 / 60)
					Verify.expect(body.AutomaticSize):toBe(E.AutomaticSize.Y)
					Verify.expect(body.Size):toBe(engine.types.UDim2.new(1, 0, 0, 0))
					root.AbsoluteSize = V2.new(389, 648)
					Verify.expect(body.AutomaticSize):toBe(E.AutomaticSize.Y)
					runtime:dispose()
				end,
			})

			verifyHarness:case(
				"a fill-height child's shrink keeps the scroll, its own size constraint and a bound size",
				{
					id = "native_layout::ScrollView::a fill-height child's shrink keeps the scroll, its own size constraint and a bound size",
					run = function()
						local roblox = require("@lune/roblox")
						local height = Compose.cell(0)
						local root, engine, stop = build(nil, function(UI: FacetControls, Host: RobloxHost)
							return UI.ScrollView "Page" {
								padding = 16,
								Host.Frame {
									Name = "Body",
									Size = roblox.UDim2.fromScale(1, 1),
									AutomaticSize = roblox.Enum.AutomaticSize.Y,
									Host.UISizeConstraint { MinSize = roblox.Vector2.new(10, 700) },
								} :: unknown,
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
						Verify.expect(constraints):toBe(1)
						root.AbsoluteSize = V2.new(389, 648)
						Verify.expect(child(body, "UISizeConstraint").MinSize):toBe(V2.new(10, 700))
						root.AbsoluteSize = V2.new(389, 1000)
						Verify.expect(child(body, "UISizeConstraint").MinSize):toBe(V2.new(10, 968))
						height:set(120)
						root.CanvasPosition = V2.new(0, 200)
						root.AbsoluteSize = V2.new(749, 300)
						Verify.expect(bound.AutomaticSize):toBe(E.AutomaticSize.Y)
						Verify.expect(bound.Size.Y.Offset):toBe(120)
						Verify.expect(body.AutomaticSize):toBe(E.AutomaticSize.None)
						root.CanvasPosition = V2.new(0, 0)
						engine.heartbeat:Fire(1 / 60)
						Verify.expect(body.AutomaticSize):toBe(E.AutomaticSize.Y)
						engine.heartbeat:Fire(1 / 60)
						Verify.expect(root.CanvasPosition):toBe(V2.new(0, 200))
						stop()
					end,
				}
			)

			verifyHarness:case("stretches the children across the scroll window when align is stretch", {
				id = "native_layout::ScrollView::stretches the children across the scroll window when align is stretch",
				run = function()
					local root, engine, stop = build(nil, function(UI: FacetControls)
						return UI.ScrollView { align = "stretch" :: "stretch", UI.Text { text = "A" } }
					end)
					local layout = child(root, "UIListLayout")
					Verify.expect(layout.ItemLineAlignment):toBe(engine.types.Enum.ItemLineAlignment.Stretch)
					Verify.expect(layout.HorizontalFlex):toBe(engine.types.Enum.UIFlexAlignment.Fill)
					stop()
				end,
			})

			verifyHarness:case("runs a horizontal axis as a horizontal list with a horizontal canvas", {
				id = "native_layout::ScrollView::runs a horizontal axis as a horizontal list with a horizontal canvas",
				run = function()
					local root, engine, stop = build(nil, function(UI: FacetControls)
						return UI.ScrollView { axis = "x" :: "x" }
					end)
					local E = engine.types.Enum
					Verify.expect(child(root, "UIListLayout").FillDirection):toBe(E.FillDirection.Horizontal)
					Verify.expect(root.AutomaticCanvasSize):toBe(E.AutomaticSize.X)
					Verify.expect(root.ScrollingDirection):toBe(E.ScrollingDirection.X)
					Verify.expect(root.HorizontalScrollBarInset):toBe(E.ScrollBarInset.ScrollBar)
					Verify.expect(root.AutomaticSize):toBe(E.AutomaticSize.Y)
					Verify.expect(root.Size.Y.Scale == 0 and root.Size.X.Scale == 1):toBe(true)
					stop()
					local filled = build(nil, function(UI: FacetControls)
						return UI.ScrollView {
							axis = "x" :: "x",
							UI.VStack { height = "fill" :: "fill", UI.Text { text = "A" } },
						}
					end)
					Verify.expect(filled.AutomaticSize):toBe(E.AutomaticSize.None)
					Verify.expect(filled.Size.Y.Scale):toBe(1)
					local both = build(nil, function(UI: FacetControls)
						return UI.ScrollView { axis = "xy" :: "xy" }
					end)
					Verify.expect(both.AutomaticCanvasSize):toBe(E.AutomaticSize.XY)
					Verify.expect(both.ScrollingDirection):toBe(E.ScrollingDirection.XY)
				end,
			})
		end)

		verifyHarness:suite("Grid", function()
			verifyHarness:case("divides the width into columns with a native grid layout", {
				id = "native_layout::Grid::divides the width into columns with a native grid layout",
				run = function()
					local root, engine, stop = build(nil, function(UI: FacetControls, Host: RobloxHost)
						return UI.Grid "Tiles" {
							columns = 3,
							gap = "s",
							Host.Frame { Name = "A" } :: unknown,
							Host.Frame { Name = "B" },
							Host.Frame { Name = "C" },
							Host.Frame { Name = "D" },
						}
					end)
					local E, D2 = engine.types.Enum, engine.types.UDim2
					local grid = child(root, "UIGridLayout")
					Verify.expect(root.Size):toBe(D2.new(1, 0, 0, 0))
					Verify.expect(root.AutomaticSize):toBe(E.AutomaticSize.Y)
					Verify.expect(grid.SortOrder):toBe(E.SortOrder.LayoutOrder)
					Verify.expect(grid.FillDirection):toBe(E.FillDirection.Horizontal)
					Verify.expect(grid.FillDirectionMaxCells):toBe(3)
					Verify.expect(grid.CellPadding):toBe(D2.fromOffset(8, 8))
					local height = themes.neutralPackage().metrics.controlSizes.regular.height
					Verify.expect(grid.CellSize.X.Scale):toBeCloseTo(1 / 3, 1e-4)
					Verify.expect(grid.CellSize.X.Offset):toBe(-6)
					for width = 60, 900 do
						local row = 3 * (grid.CellSize.X.Scale * width + grid.CellSize.X.Offset)
							+ 2 * grid.CellPadding.X.Offset
						Verify.expect(row <= width):toBe(true)
					end
					Verify.expect(grid.CellSize.Y.Offset):toBe(height)
					Verify.expect(root:FindFirstChild("D").LayoutOrder):toBe(4)
					stop()
				end,
			})

			verifyHarness:case("fills columns first with flow column and follows the child count", {
				id = "native_layout::Grid::fills columns first with flow column and follows the child count",
				run = function()
					local root, engine, stop = build(nil, function(UI: FacetControls, Host: RobloxHost)
						return UI.Grid "Board" {
							columns = 2,
							flow = "column" :: "column",
							Host.Frame { Name = "A" } :: unknown,
							Host.Frame { Name = "B" },
							Host.Frame { Name = "C" },
							Host.Frame { Name = "D" },
							Host.Frame { Name = "E" },
						}
					end)
					local E = engine.types.Enum
					local grid = child(root, "UIGridLayout")
					Verify.expect(grid.FillDirection):toBe(E.FillDirection.Vertical)
					Verify.expect(grid.FillDirectionMaxCells):toBe(3)
					Verify.expect(grid.CellSize.X.Scale):toBeCloseTo(1 / 2, 1e-4)
					local extra = engine.new("Frame")
					extra.Parent = root
					local more = engine.new("Frame")
					more.Parent = root
					Verify.expect(grid.FillDirectionMaxCells):toBe(4)
					more.Parent = nil
					extra.Parent = nil
					Verify.expect(grid.FillDirectionMaxCells):toBe(3)
					stop()
					Verify.expect((mentions(
						refusal(function(UI: FacetControls)
							return UI.Grid { columns = 2, flow = "diagonal" :: any }
						end),
						"flow must be row or column"
					))):toBe(true)
				end,
			})

			verifyHarness:case("takes a separate row gap, a cell height and an aspect ratio", {
				id = "native_layout::Grid::takes a separate row gap, a cell height and an aspect ratio",
				run = function()
					local columns = Compose.cell(2)
					local root, engine, stop = build(nil, function(UI: FacetControls)
						return UI.Grid { columns = columns, gap = 4, rowGap = "m", cellHeight = 60, aspectRatio = 1.5 }
					end)
					local grid = child(root, "UIGridLayout")
					Verify.expect(grid.CellPadding):toBe(engine.types.UDim2.fromOffset(4, 16))
					Verify.expect(grid.CellSize.Y.Offset):toBe(60)
					Verify.expect(child(grid, "UIAspectRatioConstraint").AspectRatio):toBe(1.5)
					columns:set(4)
					Verify.expect(grid.FillDirectionMaxCells):toBe(4)
					Verify.expect(grid.CellSize.X.Scale):toBeCloseTo(0.25, 1e-4)
					Verify.expect(grid.CellSize.X.Offset):toBe(-3)
					stop()
				end,
			})

			verifyHarness:case("moves the row gap with the theme and keeps the column count", {
				id = "native_layout::Grid::moves the row gap with the theme and keeps the column count",
				run = function()
					local theme = Compose.cell(themes.neutralPackage())
					local root, engine, stop = build({ theme = theme }, function(UI: FacetControls)
						return UI.Grid { columns = 3, gap = 4, rowGap = "s" }
					end)
					local grid = child(root, "UIGridLayout")
					Verify.expect(grid.CellPadding):toBe(engine.types.UDim2.fromOffset(4, 8))
					theme:set(wide())
					Verify.expect(grid.CellPadding):toBe(engine.types.UDim2.fromOffset(4, 12))
					Verify.expect(grid.FillDirectionMaxCells):toBe(3)
					stop()
				end,
			})

			verifyHarness:case("refuses a column count that is not a whole number", {
				id = "native_layout::Grid::refuses a column count that is not a whole number",
				run = function()
					local engine, runtime, UI = make()
					local ok, message = pcall(function()
						runtime.mount(function()
							return UI.Grid { columns = 1.5 }
						end, engine.new("ScreenGui"))
					end)
					Verify.expect(ok):toBe(false)
					Verify.expect(string.find(tostring(message), "whole number", 1, true) ~= nil):toBe(true)
					runtime:dispose()
				end,
			})
		end)

		verifyHarness:suite("layout paint belongs to the StyleSheet", function()
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
				VStack = function(UI: FacetControls)
					return UI.VStack { UI.Text { text = "A" } }
				end,
				HStack = function(UI: FacetControls)
					return UI.HStack { UI.Text { text = "A" } }
				end,
				ZStack = function(UI: FacetControls)
					return UI.ZStack { UI.Text { text = "A" } }
				end,
				Screen = function(UI: FacetControls)
					return UI.Screen { UI.Text { text = "A" } }
				end,
				ScrollView = function(UI: FacetControls)
					return UI.ScrollView { UI.Text { text = "A" } }
				end,
				Grid = function(UI: FacetControls)
					return UI.Grid { columns = 2, UI.Text { text = "A" } }
				end,
				AdaptiveStack = function(UI: FacetControls)
					return UI.AdaptiveStack { UI.Text { text = "A" } }
				end,
				ViewThatFits = function(UI: FacetControls)
					return UI.ViewThatFits { UI.Text { text = "A" } }
				end,
				Spacer = function(UI: FacetControls)
					return UI.Spacer {}
				end,
				ErrorBoundary = function(UI: FacetControls)
					return UI.ErrorBoundary {
						view = function()
							return UI.Text { text = "A" }
						end,
						fallback = function()
							return UI.Text { text = "B" }
						end,
					}
				end,
				Region = function(UI: FacetControls)
					return UI.Region { zone = "center" :: "center", rank = 1, UI.Text { text = "A" } }
				end,
				Composition = function(UI: FacetControls)
					return UI.Composition { UI.Region { zone = "center" :: "center", rank = 1, UI.Text { text = "A" } } }
				end,
			}

			verifyHarness:case(
				"a plain layout primitive stays transparent and one given a panel paints the theme panel",
				{
					id = "native_layout::layout paint belongs to the StyleSheet::a plain layout primitive stays transparent and one given a panel paints the theme panel",
					run = function()
						local package = themes.neutralPackage()
						local panel = package.style.themes[1].colors.surfaceStrong
						for name, body in primitives do
							local root, engine, stop, runtime = build(nil, body)
							local _, sheet: any = runtime.mount(function()
								return themes.createStyleSheet(runtime, package, { types = engine.types } :: any)
							end, engine.new("Folder"))
							Verify.expect(`{name} plain {painted(engine, sheet, root, "BackgroundTransparency")}`)
								:toBe(`{name} plain 1`)
							root:AddTag("facet-panel")
							Verify.expect(`{name} panel {painted(engine, sheet, root, "BackgroundTransparency")}`)
								:toBe(`{name} panel 0`)
							Verify.expect((painted(engine, sheet, root, "BackgroundColor3")))
								:toBe(engine.types.Color3.new(panel.r, panel.g, panel.b))
							stop()
						end
					end,
				}
			)

			verifyHarness:case("a caller's own BackgroundTransparency still owns the paint, even the default 0", {
				id = "native_layout::layout paint belongs to the StyleSheet::a caller's own BackgroundTransparency still owns the paint, even the default 0",
				run = function()
					local package = themes.neutralPackage()
					for _, value in { 0, 0.25 } do
						local root, engine, stop, runtime = build(nil, function(UI: FacetControls)
							return UI.VStack { BackgroundTransparency = value }
						end)
						local _, sheet: any = runtime.mount(function()
							return themes.createStyleSheet(runtime, package, { types = engine.types } :: any)
						end, engine.new("Folder"))
						Verify.expect((painted(engine, sheet, root, "BackgroundTransparency"))):toBe(value)
						stop()
					end
				end,
			})
		end)

		verifyHarness:suite("theme spacing steps", function()
			verifyHarness:case("validates the spacing scale of a theme package", {
				id = "native_layout::theme spacing steps::validates the spacing scale of a theme package",
				run = function()
					local package, report =
						themes.define({ identity = { id = "bad-space" }, metrics = { space = { s = -2 } } } :: any)
					Verify.expect(package):toBeNil()
					Verify.expect(report.errors[1].field):toBe("metrics.space.s")
					local good = wide()
					Verify.expect(good.metrics.space.s):toBe(12)
				end,
			})
		end)
	end)
end
