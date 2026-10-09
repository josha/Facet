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

	verifyHarness:suite("native composition rest measurements", function()
		verifyHarness:case("sizes a simplified Region without an automatic parent and hit target feedback loop", {
			id = "native_layout::native composition rest measurements::sizes a simplified Region without an automatic parent and hit target feedback loop",
			run = function()
				local root, engine, stop = build(nil, function(UI: FacetControls, Host: RobloxHost)
					return UI.Composition {
						UI.Region "Health" {
							zone = "bottomLeft" :: "bottomLeft",
							rank = 1,
							Host.Frame "Full" {} :: unknown,
							Host.Frame "Compact" {},
						},
					}
				end)
				local region = root:FindFirstChild("Health", true)
				local full, compact = region:FindFirstChild("Full", true), region:FindFirstChild("Compact", true)
				local V2 = engine.types.Vector2
				full.AbsoluteSize = V2.new(147, 26)
				compact.AbsoluteSize = V2.new(32, 20)
				root:FindFirstChild("Zones").AbsoluteSize = V2.new(166, 200)
				Verify.expect(region:GetAttribute("FacetForm")):toBe(2)
				compact.AbsoluteSize = V2.new(39, 26)
				Verify.expect(region.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.None)
				Verify.expect(region.Size):toBe(engine.types.UDim2.fromOffset(44, 44))
				local trigger = region:FindFirstChildWhichIsA("TextButton", true)
				Verify.expect(trigger.Size):toBe(engine.types.UDim2.fromScale(1, 1))
				root:FindFirstChild("Zones").AbsoluteSize = V2.new(1079, 745)
				root:FindFirstChild("Zones").AbsoluteSize = V2.new(166, 200)
				Verify.expect(region.Size):toBe(engine.types.UDim2.fromOffset(44, 44))
				stop()
			end,
		})
		verifyHarness:case("keeps a simplified Region rectangle after a scaled viewport round trip", {
			id = "native_layout::native composition rest measurements::keeps a simplified Region rectangle after a scaled viewport round trip",
			run = function()
				local root, engine, stop = build(nil, function(UI: FacetControls, Host: RobloxHost)
					return UI.Composition {
						UI.Region "Health" {
							zone = "bottomLeft" :: "bottomLeft",
							rank = 1,
							Host.Frame "Full" {} :: unknown,
							Host.Frame "Compact" {},
						},
					}
				end)
				local region = root:FindFirstChild("Health", true)
				local full, compact = region:FindFirstChild("Full", true), region:FindFirstChild("Compact", true)
				local V2 = engine.types.Vector2
				root:FindFirstChild("Zones"):FindFirstChild("LayoutUnit").AbsoluteSize = V2.new(100, 1)
				full.AbsoluteSize, compact.AbsoluteSize = V2.new(90, 35), V2.new(41.5, 35)
				root:FindFirstChild("Zones").AbsoluteSize = V2.new(166, 200)
				Verify.expect(region:GetAttribute("FacetForm")):toBe(2)
				local trigger = region:FindFirstChildWhichIsA("TextButton", true)
				local initial = trigger.Size
				for _, unit in { 0.94, 0.5, 1 } do
					local a, b = full:FindFirstChild("LayoutUnit"), compact:FindFirstChild("LayoutUnit")
					if a then
						a.AbsoluteSize = V2.new(100 * unit, unit)
					end
					if b then
						b.AbsoluteSize = V2.new(100 * unit, unit)
					end
					full.AbsoluteSize = V2.new(90 * unit, 35 * unit)
					compact.AbsoluteSize = V2.new(41.5 * unit, 35 * unit)
					Verify.expect(region:GetAttribute("FacetForm")):toBe(2)
					Verify.expect(trigger.Size):toBe(initial)
				end
				stop()
			end,
		})
	end)

	verifyHarness:suite("phone layout policy", function()
		verifyHarness:case("reserves a visible horizontal scroll hint below overflowing genre chips", {
			id = "native_layout::phone layout policy::reserves a visible horizontal scroll hint below overflowing genre chips",
			run = function()
				for _, width in { 320, 360, 375, 389, 430 } do
					local root, engine, stop = build(nil, function(UI: FacetControls)
						return UI.ScrollView {
							axis = "x" :: "x",
							ScrollBarThickness = 2,
							UI.Chip { label = "Adventure", selected = Compose.cell(false) },
						}
					end)
					root.AbsoluteWindowSize = engine.types.Vector2.new(width, 36)
					root:FindFirstChildWhichIsA("UIListLayout").AbsoluteContentSize = engine.types.Vector2.new(750, 36)
					local hint = root:FindFirstChild("ScrollBarRoom")
					Verify.expect(hint ~= nil):toBe(true)
					Verify.expect(hint.MinSize.Y):toBe(38)
					Verify.expect(root.HorizontalScrollBarInset):toBe(engine.types.Enum.ScrollBarInset.ScrollBar)
					Verify.expect(root.CanvasSize.X.Offset):toBe(750)
					Verify.expect(root.ScrollBarThickness):toBe(2)
					stop()
				end
			end,
		})

		verifyHarness:case("a single fitting candidate keeps its authored visibility on phone widths", {
			id = "native_layout::phone layout policy::a single fitting candidate keeps its authored visibility on phone widths",
			run = function()
				local outcomes: { string } = {}
				for _, width in { 320, 360, 375, 389, 430 } do
					local visible = Compose.cell(false)
					local root, engine, stop = build(nil, function(UI: FacetControls)
						return UI.ViewThatFits {
							width = "hug" :: "hug",
							UI.HStack { Visible = visible, UI.Button { label = "Spatial mode" } },
						}
					end)
					root.AbsoluteSize = engine.types.Vector2.new(width, 44)
					local candidate = root:FindFirstChildWhichIsA("Frame")
					local initiallyHidden = candidate.Visible == false
					visible:set(true)
					Verify.expect(candidate.Visible):toBe(true)
					visible:set(false)
					root.AbsoluteSize = engine.types.Vector2.new(width - 1, 44)
					table.insert(outcomes, `{width}:{initiallyHidden and candidate.Visible == false}`)
					stop()
				end
				Verify.expect(table.concat(outcomes, ",")):toBe("320:true,360:true,375:true,389:true,430:true")
			end,
		})
	end)

	verifyHarness:suite("native text layout", function()
		verifyHarness:case("keeps the Slider readout reservation across drag values", {
			id = "native_layout::native text layout::keeps the Slider readout reservation across drag values",
			run = function()
				local value = Compose.cell(0)
				local root, engine, stop = build(nil, function(UI)
					return UI.Slider { value = value, min = 0, max = 100 }
				end)
				local label = root:FindFirstChild("Value", true)
				local floor = label:FindFirstChild("TextBoundsFloor")
				for _, sample in { { 0, 8 }, { 50, 16 }, { 55.08, 36 }, { 100, 24 } } do
					value:set(sample[1])
					label.TextBounds = engine.types.Vector2.new(sample[2], 16)
					Verify.expect(floor.MaxSize.X):toBe(44)
				end
				label.Size = engine.types.UDim2.fromOffset(60, 0)
				Verify.expect(floor.MaxSize.X):toBe(60)
				label.Size = engine.types.UDim2.new(1, 0, 0, 0)
				Verify.expect(floor.MaxSize.X):toBe(math.huge)
				stop()
			end,
		})
		verifyHarness:case("keeps the Stepper readout reservation when a digit is added", {
			id = "native_layout::native text layout::keeps the Stepper readout reservation when a digit is added",
			run = function()
				local value = Compose.cell(9)
				local root, engine, stop = build(nil, function(UI)
					return UI.Stepper { value = value, max = 100 }
				end)
				local label = root:FindFirstChild("Value", true)
				local floor = label:FindFirstChild("TextBoundsFloor")
				label.TextBounds = engine.types.Vector2.new(8, 16)
				Verify.expect(floor.MaxSize.X):toBe(40)
				value:set(10)
				label.TextBounds = engine.types.Vector2.new(13, 16)
				Verify.expect(floor.MaxSize.X):toBe(40)
				stop()
			end,
		})
		verifyHarness:case("grows both ShortcutHint axes with a taller painted key", {
			id = "native_layout::native text layout::grows both ShortcutHint axes with a taller painted key",
			run = function()
				local root, engine, stop = build(nil, function(UI)
					return UI.ShortcutHint { keys = { { "K" } } }
				end)
				root.TextBounds = engine.types.Vector2.new(6, 12)
				local before = root.Size.Y.Offset
				root.TextBounds = engine.types.Vector2.new(13, 26)
				Verify.expect(root.Size.Y.Offset > before):toBe(true)
				Verify.expect(root.Size.X.Offset):toBe(root.Size.Y.Offset)
				Verify.expect(root.Size.Y.Offset >= 34):toBe(true)
				Verify.expect(root.Size.Y.Offset < 44):toBe(true)
				root:FindFirstChild("TextBoundsUnit").AbsoluteSize = engine.types.Vector2.new(50, 0.5)
				root:FindFirstChild("CapUnit").AbsoluteSize = engine.types.Vector2.new(50, 0.5)
				root.TextBounds = engine.types.Vector2.new(6.5, 13)
				Verify.expect(root.Size.Y.Offset):toBe(34)
				stop()
			end,
		})
		verifyHarness:case("keeps a ShortcutHint square while allowing a longer chord", {
			id = "native_layout::native text layout::keeps a ShortcutHint square while allowing a longer chord",
			run = function()
				local root, engine, stop = build(nil, function(UI)
					return UI.ShortcutHint { keys = { { "K" } } }
				end)
				local floor = root:FindFirstChild("TextBoundsFloor")
				root.TextBounds = engine.types.Vector2.new(6, 12)
				Verify.expect(floor.MaxSize):toBe(engine.types.Vector2.new(root.Size.X.Offset, root.Size.Y.Offset))
				root.TextBounds = engine.types.Vector2.new(60, 26)
				Verify.expect(floor.MaxSize.X):toBe(60)
				Verify.expect(floor.MaxSize.Y):toBe(math.max(26, root.Size.Y.Offset))
				stop()
			end,
		})
		verifyHarness:case("yields the automatic glyph floor to a later wrapping constraint", {
			id = "native_layout::native text layout::yields the automatic glyph floor to a later wrapping constraint",
			run = function()
				local root, engine, stop = build(nil, function(UI: FacetControls)
					return UI.Text { text = "A long label" }
				end)
				root.TextBounds = engine.types.Vector2.new(300, 18)
				Verify.expect(root:FindFirstChild("TextBoundsFloor").MinSize.X):toBe(300)
				local cap = engine.new("UISizeConstraint")
				cap.MaxSize = engine.types.Vector2.new(100, math.huge)
				cap.Parent = root
				root.TextWrapped = true
				Verify.expect(root:FindFirstChild("TextBoundsFloor")):toBeNil()
				Verify.expect(root:FindFirstChildWhichIsA("UISizeConstraint")):toBe(cap)
				Verify.expect(cap.MaxSize.X):toBe(100)
				stop()
			end,
		})

		verifyHarness:case("reflows a late clipped automatic box after styled metrics have settled", {
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
				Verify.expect(engineLib.connections(engine.heartbeat)):toBe(0)
				local pulse = 0
				engine.onWrite(function(node, property, value)
					if
						node == label
						and property == "AutomaticSize"
						and value == engine.types.Enum.AutomaticSize.XY
					then
						pulse += 1
						label.AbsoluteSize = label.TextBounds
					end
				end)
				label.AbsoluteSize = engine.types.Vector2.new(44, 12)
				label.TextBounds = engine.types.Vector2.new(15, 13)
				Verify.expect(pulse):toBe(0)
				engine.heartbeat:Fire(1 / 60)
				Verify.expect(pulse):toBe(1)
				Verify.expect(label.AbsoluteSize.Y):toBe(13)
				Verify.expect(engineLib.connections(engine.heartbeat)):toBe(0)
				engine.heartbeat:Fire(1 / 60)
				Verify.expect(pulse):toBe(1)
				label.AbsoluteSize = engine.types.Vector2.new(44, 12)
				stop()
				runtime:dispose()
				engine.heartbeat:Fire(1 / 60)
				Verify.expect(pulse):toBe(1)
				Verify.expect(engineLib.connections(engine.heartbeat)):toBe(0)
			end,
		})
		verifyHarness:case("reflows initial styled metrics without keeping local font overrides", {
			id = "native_layout::native text layout::reflows initial styled metrics without keeping local font overrides",
			run = function()
				local engine: any = engineLib.new()
				local points = 13
				local face = engine.types.Font.new("rbxasset://fonts/families/BuilderSans.json")
				local original = engine.new
				engine.new = function(className)
					local node = original(className)
					if className == "TextLabel" then
						local defaults = { FontFace = node.FontFace, TextSize = node.TextSize }
						node.GetStyled = function(self, property)
							if property == "FontFace" then
								return face
							elseif property == "TextSize" then
								return points
							end
							return self[property]
						end
						node.ResetPropertyToDefault = function(self, property)
							self[property] = defaults[property]
						end
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
				engine.heartbeat:Fire(1 / 60)
				Verify.expect(nativeMetrics[#nativeMetrics][1]):toBe(face)
				Verify.expect(nativeMetrics[#nativeMetrics][2]):toBe(13)
				Verify.expect(root.FontFace):toBe(initialFace)
				Verify.expect(root.TextSize):toBe(initialSize)
				points = 17
				root:GetPropertyChangedSignal("TextSize"):Fire()
				engine.heartbeat:Fire(1 / 60)
				Verify.expect(nativeMetrics[#nativeMetrics][2]):toBe(17)
				Verify.expect(root.TextSize):toBe(initialSize)
				Verify.expect(engineLib.connections(engine.heartbeat)):toBe(0)
				points = 19
				root:GetPropertyChangedSignal("TextSize"):Fire()
				stop()
				runtime:dispose()
				local count = #nativeMetrics
				engine.heartbeat:Fire(1 / 60)
				Verify.expect(nativeMetrics):toHaveLength(count)
				Verify.expect(engineLib.connections(engine.heartbeat)):toBe(0)
			end,
		})
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

	verifyHarness:suite("native layout primitives", function()
		verifyHarness:suite("VStack and HStack", function()
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
		end)

		verifyHarness:suite("ZStack", function()
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
			verifyHarness:case(
				"keeps a horizontal canvas floor at the native layout extent and respects an authored canvas",
				{
					id = "native_layout::ScrollView::keeps a horizontal canvas floor at the native layout extent and respects an authored canvas",
					run = function()
						local root, engine, stop = build(nil, function(UI: FacetControls)
							return UI.ScrollView({ axis = "x" :: "x", padding = { left = 4, right = 6 } })
						end)
						local V2 = engine.types.Vector2
						root.AbsoluteWindowSize = V2.new(353, 44)
						child(root, "UIListLayout").AbsoluteContentSize = V2.new(376, 40)
						Verify.expect(root.AutomaticCanvasSize):toBe(engine.types.Enum.AutomaticSize.X)
						Verify.expect(root.CanvasSize.X.Offset):toBe(386)
						root:FindFirstChild("LayoutUnit").AbsoluteSize = V2.new(200, 2)
						root.AbsoluteWindowSize = V2.new(706, 88)
						child(root, "UIListLayout").AbsoluteContentSize = V2.new(752, 80)
						Verify.expect(root.CanvasSize.X.Offset):toBe(386)
						root:FindFirstChild("LayoutUnit").AbsoluteSize = V2.new(100, 1)
						child(root, "UIListLayout").AbsoluteContentSize = V2.new(250, 40)
						Verify.expect(root.CanvasSize.X.Offset):toBe(260)
						stop()
						root, engine, stop = build(nil, function(UI: FacetControls)
							return UI.ScrollView({
								axis = "x" :: "x",
								CanvasSize = engine.types.UDim2.fromOffset(500, 0),
							})
						end)
						child(root, "UIListLayout").AbsoluteContentSize = engine.types.Vector2.new(700, 40)
						Verify.expect(root.CanvasSize.X.Offset):toBe(500)
						stop()
					end,
				}
			)

			verifyHarness:case(
				"restores an initial offset after native canvas bounds arrive without overriding input",
				{
					id = "native_layout::ScrollView::restores an initial offset after native canvas bounds arrive without overriding input",
					run = function()
						local frame, engine, stop = build(nil, function(UI)
							return UI.ScrollView({
								CanvasPosition = require("@lune/roblox").Vector2.new(130, 0),
								axis = "x",
							})
						end)
						local V2 = engine.types.Vector2
						frame.CanvasPosition = V2.zero
						frame.AbsoluteWindowSize = V2.new(365, 220)
						Verify.expect(frame.CanvasPosition):toBe(V2.zero)
						frame.AbsoluteCanvasSize = V2.new(624, 220)
						Verify.expect(frame.CanvasPosition):toBe(V2.new(130, 0))
						frame.CanvasPosition = V2.new(20, 0)
						frame.AbsoluteCanvasSize = V2.new(800, 220)
						Verify.expect(frame.CanvasPosition):toBe(V2.new(20, 0))
						stop()
						frame, engine, stop = build(nil, function(UI)
							return UI.ScrollView({ CanvasPosition = V2.new(130, 0), axis = "x" })
						end)
						frame.CanvasPosition = V2.zero
						frame.InputBegan:Fire({ UserInputType = engine.types.Enum.UserInputType.Touch })
						frame.AbsoluteWindowSize = V2.new(365, 220)
						frame.AbsoluteCanvasSize = V2.new(624, 220)
						Verify.expect(frame.CanvasPosition):toBe(V2.zero)
						stop()
					end,
				}
			)

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
		end)
	end)
end
