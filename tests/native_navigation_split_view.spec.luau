--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local Compose = require("../src/vendor/compose/core")
	local Roblox = require("../src/vendor/compose/roblox")
	local controls = require("../src/ui")
	local engines = require("./lib/native_engine")
	type Runtime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	local function world(preferredInput: string?, axis: ("x" | "y")?, compact: number?)
		local engine = engines.new()
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		local gamepad = engine.new("GamepadService")
		gamepad.GamepadCursorEnabled = false
		input.GetFocusedTextBox = function()
			return nil
		end
		local runtime: Runtime = Roblox.createRuntime(engine)
		local distance = Compose.cell("near")
		local UI = controls(Compose, runtime, {
			types = engine.types,
			preferredInput = preferredInput,
			services = { GuiService = gui, UserInputService = input, GamepadService = gamepad },
			environment = { viewingDistance = distance :: any },
		})
		local shown, width, column = Compose.cell(true), Compose.cell(360), Compose.cell("sidebar")
		local resizable, alwaysShow = Compose.cell(true), Compose.cell(false)
		local screen = engine.new("ScreenGui")
		local root: any
		local builds = { sidebar = 0, detail = 0 }
		local stop = runtime.mount(function()
			root = UI.NavigationSplitView {
				axis = axis,
				compactWidth = compact,
				compactHeight = compact,
				resizable = resizable,
				alwaysShowResizeHandle = alwaysShow,
				sidebarHeight = if axis == "y" then width else nil,
				detailVisible = shown,
				sidebarWidth = width,
				preferredCompactColumn = column :: any,
				sidebar = function(): Instance
					builds.sidebar += 1
					return UI.Button { Name = "File", label = "File" }
				end,
				detail = function(): Instance
					builds.detail += 1
					return UI.Button { Name = "Inspector", label = "Inspector" }
				end,
			}
			return root
		end, screen)
		root.AbsoluteSize = engine.types.Vector2.new(1000, 600)
		return {
			root = root,
			gui = gui,
			input = input,
			gamepad = gamepad,
			engine = engine,
			screen = screen,
			shown = shown,
			resizable = resizable,
			alwaysShow = alwaysShow,
			width = width,
			column = column,
			distance = distance,
			builds = builds,
			stop = stop,
		}
	end
	local function find(root: any, name: string): any
		return root:FindFirstChild(name, true)
	end

	verifyHarness:suite("native split navigation", function()
		for _, axis in { "x", "y" } do
			verifyHarness:case("makes " .. axis .. " resizing optional without blocking pane focus", {
				id = "native_navigation_split_view::"
					.. "native split navigation"
					.. "::"
					.. "makes "
					.. axis
					.. " resizing optional without blocking pane focus",
				run = function()
					local w = world(nil, axis :: "x" | "y")
					local resize, detector = find(w.root, "Resize"), find(w.root, "UIDragDetector")
					local file, inspector = find(w.root, "File"), find(w.root, "Inspector")
					w.gui.SelectedObject = file
					w.gui.SelectedObject = resize
					detector.DragStart.fire(w.engine.types.Vector2.new(360, 360))
					w.resizable:set(false)
					Verify.expect(detector.Enabled):toBe(false)
					Verify.expect(resize.Selectable):toBe(false)
					Verify.expect(resize.Active):toBe(false)
					Verify.expect(find(resize, "Grip").Visible):toBe(false)
					Verify.expect(w.gui.SelectedObject):toBe(file)
					detector.DragContinue.fire(w.engine.types.Vector2.new(400, 400))
					detector.DragEnd.fire(w.engine.types.Vector2.new(400, 400))
					Verify.expect((w.width:peek())):toBe(360)
					w.gui.SelectedObject = inspector
					Verify.expect(w.gui.SelectedObject):toBe(inspector)
					w.width:set(380)
					Verify.expect(
						if axis == "x"
							then find(w.root, "Sidebar").Size.X.Offset
							else find(w.root, "Sidebar").Size.Y.Offset
					):toBe(380)
					w.resizable:set(true)
					Verify.expect(detector.Enabled and resize.Selectable):toBe(true)
					w.gui.SelectedObject = file
					Verify.expect(w.gui.SelectedObject):toBe(resize)
					w.stop()
				end,
			})
		end
		for _, axis in { "x", "y" } do
			verifyHarness:case("collapses " .. axis .. " only when pane minimums and the input divider cannot fit", {
				id = "native_navigation_split_view::"
					.. "native split navigation"
					.. "::"
					.. "collapses "
					.. axis
					.. " only when pane minimums and the input divider cannot fit",
				run = function()
					local w = world(nil, axis :: "x" | "y")
					w.input.PreferredInput = w.engine.types.Enum.PreferredInput.Touch
					local minimum = if axis == "x" then 560 else 240
					local divider = find(w.root, "Resize").Size
					local gutter = if axis == "x" then divider.X.Offset else divider.Y.Offset
					Verify.expect(gutter >= 28):toBe(true)
					local function size(value: number)
						w.root.AbsoluteSize = w.engine.types.Vector2.new(
							if axis == "x" then value else 390,
							if axis == "y" then value else 360
						)
					end
					size(minimum + gutter)
					Verify.expect((w.root:GetAttribute("FacetSplitCollapsed"))):toBe(false)
					Verify.expect(find(w.root, "Sidebar").Visible and find(w.root, "Detail").Visible):toBe(true)
					size(minimum + gutter - 1)
					Verify.expect((w.root:GetAttribute("FacetSplitCollapsed"))):toBe(true)
					w.resizable:set(false)
					size(minimum + 1)
					Verify.expect((w.root:GetAttribute("FacetSplitCollapsed"))):toBe(false)
					size(minimum)
					Verify.expect((w.root:GetAttribute("FacetSplitCollapsed"))):toBe(true)
					w.stop()
					local explicit = world(nil, axis :: "x" | "y", 800)
					explicit.root.AbsoluteSize = explicit.engine.types.Vector2.new(799, 799)
					Verify.expect((explicit.root:GetAttribute("FacetSplitCollapsed"))):toBe(true)
					explicit.root.AbsoluteSize = explicit.engine.types.Vector2.new(800, 800)
					Verify.expect((explicit.root:GetAttribute("FacetSplitCollapsed"))):toBe(false)
					explicit.stop()
				end,
			})
		end

		verifyHarness:case("can keep the resize handle visible without pointer hover", {
			id = "native_navigation_split_view::native split navigation::can keep the resize handle visible without pointer hover",
			run = function()
				local w = world()
				local resize, pill = find(w.root, "Resize"), find(w.root, "Pill")
				Verify.expect(pill.Visible):toBe(false)
				w.alwaysShow:set(true)
				Verify.expect(pill.Visible):toBe(true)
				resize.MouseEnter.fire()
				resize.MouseLeave.fire()
				Verify.expect(pill.Visible):toBe(true)
				w.alwaysShow:set(false)
				Verify.expect(pill.Visible):toBe(false)
				w.stop()
			end,
		})

		verifyHarness:case("stacks panes vertically and clamps dragging along the height", {
			id = "native_navigation_split_view::native split navigation::stacks panes vertically and clamps dragging along the height",
			run = function()
				local w = world(nil, "y")
				local sidebar, detail = find(w.root, "Sidebar"), find(w.root, "Detail")
				local detector = find(w.root, "UIDragDetector")
				Verify.expect(sidebar.Size.Y.Offset):toBe(360)
				Verify.expect(sidebar.Size.X.Scale):toBe(1)
				Verify.expect(detail.Position.Y.Offset):toBe(372)
				Verify.expect(detail.Size.Y.Offset):toBe(-372)
				Verify.expect(detector.DragAxis):toBe(w.engine.types.Vector2.new(0, 1))
				detector.DragStart.fire(w.engine.types.Vector2.new(200, 360))
				detector.DragContinue.fire(w.engine.types.Vector2.new(500, 360))
				Verify.expect((w.width:peek())):toBe(360)
				detector.DragContinue.fire(w.engine.types.Vector2.new(500, 10000))
				Verify.expect((w.width:peek())):toBe(468)
				detector.DragContinue.fire(w.engine.types.Vector2.new(500, -10000))
				Verify.expect((w.width:peek())):toBe(120)
				w.root.AbsoluteSize = w.engine.types.Vector2.new(390, 700)
				Verify.expect((w.root:GetAttribute("FacetSplitCollapsed"))):toBe(false)
				w.column:set("detail")
				w.root.AbsoluteSize = w.engine.types.Vector2.new(700, 230)
				Verify.expect((w.root:GetAttribute("FacetSplitCollapsed"))):toBe(true)
				Verify.expect(sidebar.Visible):toBe(false)
				find(w.root, "Back").Activated.fire()
				Verify.expect(sidebar.Visible):toBe(true)
				w.root.AbsoluteSize = w.engine.types.Vector2.new(390, 700)
				Verify.expect(w.builds.sidebar + w.builds.detail):toBe(2)
				w.distance:set("ten-foot")
				Verify.expect(find(w.root, "Resize").Visible):toBe(false)
				w.stop()
			end,
		})

		verifyHarness:case("uses a horizontal grip and up/down focus exits for stacked panes", {
			id = "native_navigation_split_view::native split navigation::uses a horizontal grip and up/down focus exits for stacked panes",
			run = function()
				local w = world(nil, "y")
				local resize = find(w.root, "Resize")
				local file, inspector = find(w.root, "File"), find(w.root, "Inspector")
				w.gui.SelectedObject = file
				w.gui.SelectedObject = inspector
				Verify.expect(w.gui.SelectedObject):toBe(resize)
				w.gui.SelectedObject = inspector
				Verify.expect(resize.NextSelectionUp):toBe(file)
				Verify.expect(resize.NextSelectionDown):toBe(inspector)
				Verify.expect(find(resize, "Grip").Size):toBe(w.engine.types.UDim2.fromOffset(36, 8))
				Verify.expect(find(resize, "Line").Size):toBe(w.engine.types.UDim2.new(1, 0, 0, 1))
				local detector = find(resize, "UIDragDetector")
				Verify.expect(detector.CursorIcon):toBe("rbxasset://SystemCursors/SizeNS")
				w.gamepad.GamepadCursorEnabled = true
				detector.DragStart.fire(w.engine.types.Vector2.new(200, 360))
				detector.DragEnd.fire(w.engine.types.Vector2.new(200, 420))
				Verify.expect((w.width:peek())):toBe(420)
				w.shown:set(false)
				Verify.expect(find(w.root, "Sidebar").Size.Y.Scale):toBe(1)
				w.stop()
			end,
		})

		verifyHarness:case("keeps both panes mounted across compact, Back and expanded transitions", {
			id = "native_navigation_split_view::native split navigation::keeps both panes mounted across compact, Back and expanded transitions",
			run = function()
				local w = world()
				local sidebar, detail = find(w.root, "Sidebar"), find(w.root, "Detail")
				Verify.expect((w.root:GetAttribute("FacetSplitCollapsed"))):toBe(false)
				Verify.expect(sidebar.Size.X.Offset):toBe(360)
				w.column:set("detail")
				w.root.AbsoluteSize = w.engine.types.Vector2.new(390, 700)
				Verify.expect(sidebar.Visible):toBe(false)
				Verify.expect(detail.Visible):toBe(true)
				find(w.root, "Back").Activated.fire()
				Verify.expect((w.column:peek())):toBe("sidebar")
				Verify.expect(sidebar.Visible):toBe(true)
				Verify.expect(detail.Visible):toBe(false)
				find(w.root, "ShowDetail").Activated.fire()
				Verify.expect((w.column:peek())):toBe("detail")
				w.root.AbsoluteSize = w.engine.types.Vector2.new(1000, 600)
				Verify.expect(sidebar.Visible and detail.Visible):toBe(true)
				Verify.expect(w.builds.sidebar + w.builds.detail):toBe(2)
				w.stop()
			end,
		})
		verifyHarness:case("collapses on TV, but keeps a wide near-distance gamepad split", {
			id = "native_navigation_split_view::native split navigation::collapses on TV, but keeps a wide near-distance gamepad split",
			run = function()
				local w = world()
				w.input.PreferredInput = w.engine.types.Enum.PreferredInput.Gamepad
				Verify.expect((w.root:GetAttribute("FacetSplitCollapsed"))):toBe(false)
				Verify.expect(find(w.root, "UIDragDetector").Enabled):toBe(false)
				w.distance:set("ten-foot")
				Verify.expect((w.root:GetAttribute("FacetSplitCollapsed"))):toBe(true)
				Verify.expect(find(w.root, "Resize").Visible):toBe(false)
				w.stop()
			end,
		})
		verifyHarness:case("keeps native mouse dragging available in a gamepad appearance preview", {
			id = "native_navigation_split_view::native split navigation::keeps native mouse dragging available in a gamepad appearance preview",
			run = function()
				local w = world("Gamepad")
				w.input.PreferredInput = w.engine.types.Enum.PreferredInput.KeyboardAndMouse
				Verify.expect(find(w.root, "UIDragDetector").Enabled):toBe(true)
				local resize = find(w.root, "Resize")
				for _, child in resize:GetDescendants() do
					Verify.expect((child:IsA("GuiButton"))):toBe(false)
				end
				w.stop()
			end,
		})

		verifyHarness:case("restores focus after compact Back and stops a cross-pane walk on the divider", {
			id = "native_navigation_split_view::native split navigation::restores focus after compact Back and stops a cross-pane walk on the divider",
			run = function()
				local w = world()
				local file, inspector = find(w.root, "File"), find(w.root, "Inspector")
				w.gui.SelectedObject = file
				w.gui.SelectedObject = inspector
				Verify.expect(w.gui.SelectedObject):toBe(find(w.root, "Resize"))
				w.gui.SelectedObject = inspector
				w.column:set("detail")
				w.root.AbsoluteSize = w.engine.types.Vector2.new(390, 700)
				w.column:set("sidebar")
				Verify.expect(w.gui.SelectedObject):toBe(file)
				w.stop()
			end,
		})

		verifyHarness:case("clamps native dragging and releases the gesture when collapsed", {
			id = "native_navigation_split_view::native split navigation::clamps native dragging and releases the gesture when collapsed",
			run = function()
				local w = world()
				local detector = find(w.root, "UIDragDetector")
				detector.DragStart.fire(w.engine.types.Vector2.new(360, 200))
				detector.DragContinue.fire(w.engine.types.Vector2.new(10000, 200))
				Verify.expect((w.width:peek())):toBe(600)
				detector.DragContinue.fire(w.engine.types.Vector2.new(-10000, 200))
				Verify.expect((w.width:peek())):toBe(240)
				w.root.AbsoluteSize = w.engine.types.Vector2.new(390, 700)
				detector.DragContinue.fire(w.engine.types.Vector2.new(10000, 200))
				Verify.expect((w.width:peek())):toBe(240)
				w.stop()
			end,
		})
		verifyHarness:case("applies the final virtual cursor drag position without a continue event", {
			id = "native_navigation_split_view::native split navigation::applies the final virtual cursor drag position without a continue event",
			run = function()
				local w = world()
				w.input.PreferredInput = w.engine.types.Enum.PreferredInput.Gamepad
				w.gui.SelectedObject = find(w.root, "File")
				w.gamepad.GamepadCursorEnabled = true
				local detector = find(w.root, "UIDragDetector")
				Verify.expect(detector.Enabled):toBe(true)
				Verify.expect(w.gui.SelectedObject):toBe(nil)
				detector.DragStart.fire(w.engine.types.Vector2.new(360, 200))
				detector.DragEnd.fire(w.engine.types.Vector2.new(460, 200))
				Verify.expect((w.width:peek())):toBe(460)
				detector.DragContinue.fire(w.engine.types.Vector2.new(500, 200))
				Verify.expect((w.width:peek())):toBe(460)
				w.stop()
			end,
		})
		verifyHarness:case("keeps one divider focus stop and leaves arrows for traversal", {
			id = "native_navigation_split_view::native split navigation::keeps one divider focus stop and leaves arrows for traversal",
			run = function()
				local w = world()
				local resize = find(w.root, "Resize")
				Verify.expect(resize.Selectable):toBe(true)
				Verify.expect((resize:GetAttribute("FacetFocusPart"))):toBe("Grip")
				Verify.expect((resize:GetAttribute("axis"))):toBe(nil)
				Verify.expect(find(resize, "Grip").Selectable):toBe(false)
				Verify.expect(find(resize, "Grip").Active):toBe(false)
				Verify.expect(find(resize, "Grip").ClassName):toBe("Frame")
				Verify.expect(find(resize, "UIDragDetector").CursorIcon):toBe("rbxasset://SystemCursors/SizeEW")
				w.gui.SelectedObject = resize
				local increase: any
				for _, child in w.screen:GetChildren() do
					if child:IsA("InputContext") and child.Enabled then
						increase = child:FindFirstChild("Increase") or increase
						Verify.expect((child:FindFirstChild("IncreaseArrow"))):toBe(nil)
					end
				end
				Verify.expect(increase ~= nil):toBe(true)
				increase.Pressed.fire()
				increase.Released.fire()
				Verify.expect((w.width:peek())):toBe(376)
				w.shown:set(false)
				Verify.expect(resize.Visible):toBe(false)
				Verify.expect(find(w.root, "Sidebar").Size.X.Scale):toBe(1)
				w.stop()
			end,
		})
	end)
end
