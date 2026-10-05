--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local Roblox = require("../src/vendor/compose/roblox")
local controls = require("../src/ui")
local engines = require("./lib/native_engine")
type Runtime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
local function world(preferredInput: string?)
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
	local screen = engine.new("ScreenGui")
	local root: any
	local builds = { sidebar = 0, detail = 0 }
	local stop = runtime.mount(function()
		root = UI.NavigationSplitView {
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

t.describe("native split navigation", function()
	t.it("keeps both panes mounted across compact, Back and expanded transitions", function()
		local w = world()
		local sidebar, detail = find(w.root, "Sidebar"), find(w.root, "Detail")
		t.expect(w.root:GetAttribute("FacetSplitCollapsed")).toBe(false)
		t.expect(sidebar.Size.X.Offset).toBe(360)
		w.column:set("detail")
		w.root.AbsoluteSize = w.engine.types.Vector2.new(390, 700)
		t.expect(sidebar.Visible).toBe(false)
		t.expect(detail.Visible).toBe(true)
		find(w.root, "Back").Activated.fire()
		t.expect(w.column:peek()).toBe("sidebar")
		t.expect(sidebar.Visible).toBe(true)
		t.expect(detail.Visible).toBe(false)
		find(w.root, "ShowDetail").Activated.fire()
		t.expect(w.column:peek()).toBe("detail")
		w.root.AbsoluteSize = w.engine.types.Vector2.new(1000, 600)
		t.expect(sidebar.Visible and detail.Visible).toBe(true)
		t.expect(w.builds.sidebar + w.builds.detail).toBe(2)
		w.stop()
	end)
	t.it("collapses on TV, but keeps a wide near-distance gamepad split", function()
		local w = world()
		w.input.PreferredInput = w.engine.types.Enum.PreferredInput.Gamepad
		t.expect(w.root:GetAttribute("FacetSplitCollapsed")).toBe(false)
		t.expect(find(w.root, "UIDragDetector").Enabled).toBe(false)
		w.distance:set("ten-foot")
		t.expect(w.root:GetAttribute("FacetSplitCollapsed")).toBe(true)
		t.expect(find(w.root, "Resize").Visible).toBe(false)
		w.stop()
	end)
	t.it("keeps native mouse dragging available in a gamepad appearance preview", function()
		local w = world("Gamepad")
		w.input.PreferredInput = w.engine.types.Enum.PreferredInput.KeyboardAndMouse
		t.expect(find(w.root, "UIDragDetector").Enabled).toBe(true)
		local resize = find(w.root, "Resize")
		for _, child in resize:GetDescendants() do
			t.expect(child:IsA("GuiButton")).toBe(false)
		end
		w.stop()
	end)

	t.it("restores focus after compact Back and stops a cross-pane walk on the divider", function()
		local w = world()
		local file, inspector = find(w.root, "File"), find(w.root, "Inspector")
		w.gui.SelectedObject = file
		w.gui.SelectedObject = inspector
		t.expect(w.gui.SelectedObject).toBe(find(w.root, "Resize"))
		w.gui.SelectedObject = inspector
		w.column:set("detail")
		w.root.AbsoluteSize = w.engine.types.Vector2.new(390, 700)
		w.column:set("sidebar")
		t.expect(w.gui.SelectedObject).toBe(file)
		w.stop()
	end)

	t.it("clamps native dragging and releases the gesture when collapsed", function()
		local w = world()
		local detector = find(w.root, "UIDragDetector")
		detector.DragStart.fire(w.engine.types.Vector2.new(360, 200))
		detector.DragContinue.fire(w.engine.types.Vector2.new(10000, 200))
		t.expect(w.width:peek()).toBe(600)
		detector.DragContinue.fire(w.engine.types.Vector2.new(-10000, 200))
		t.expect(w.width:peek()).toBe(240)
		w.root.AbsoluteSize = w.engine.types.Vector2.new(390, 700)
		detector.DragContinue.fire(w.engine.types.Vector2.new(10000, 200))
		t.expect(w.width:peek()).toBe(240)
		w.stop()
	end)
	t.it("applies the final virtual cursor drag position without a continue event", function()
		local w = world()
		w.input.PreferredInput = w.engine.types.Enum.PreferredInput.Gamepad
		w.gui.SelectedObject = find(w.root, "File")
		w.gamepad.GamepadCursorEnabled = true
		local detector = find(w.root, "UIDragDetector")
		t.expect(detector.Enabled).toBe(true)
		t.expect(w.gui.SelectedObject).toBe(nil)
		detector.DragStart.fire(w.engine.types.Vector2.new(360, 200))
		detector.DragEnd.fire(w.engine.types.Vector2.new(460, 200))
		t.expect(w.width:peek()).toBe(460)
		detector.DragContinue.fire(w.engine.types.Vector2.new(500, 200))
		t.expect(w.width:peek()).toBe(460)
		w.stop()
	end)
	t.it("keeps one divider focus stop and leaves arrows for traversal", function()
		local w = world()
		local resize = find(w.root, "Resize")
		t.expect(resize.Selectable).toBe(true)
		t.expect(resize:GetAttribute("FacetFocusPart")).toBe("Grip")
		t.expect(resize:GetAttribute("axis")).toBe(nil)
		t.expect(find(resize, "Grip").Selectable).toBe(false)
		t.expect(find(resize, "Grip").Active).toBe(false)
		t.expect(find(resize, "Grip").ClassName).toBe("Frame")
		t.expect(find(resize, "UIDragDetector").CursorIcon).toBe("rbxasset://SystemCursors/SizeEW")
		w.gui.SelectedObject = resize
		local increase: any
		for _, child in w.screen:GetChildren() do
			if child:IsA("InputContext") and child.Enabled then
				increase = child:FindFirstChild("Increase") or increase
				t.expect(child:FindFirstChild("IncreaseArrow")).toBe(nil)
			end
		end
		t.expect(increase ~= nil).toBe(true)
		increase.Pressed.fire()
		increase.Released.fire()
		t.expect(w.width:peek()).toBe(376)
		w.shown:set(false)
		t.expect(resize.Visible).toBe(false)
		t.expect(find(w.root, "Sidebar").Size.X.Scale).toBe(1)
		w.stop()
	end)
end)
