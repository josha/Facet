--!strict
local t = require("./lib/testkit")
local FocusBeam = require("../src/ui/focus_beam")

local function r(x: number, y: number, w: number, h: number)
	return { x = x, y = y, width = w, height = h }
end

t.describe("the beam neighbour", function()
	t.it("prefers an in-beam candidate by gap, even when an out-of-beam one is nearer", function()
		local from = r(300, 600, 600, 44)
		local candidates = { r(100, 520, 44, 44), r(500, 200, 300, 44) }
		t.expect(FocusBeam.neighbor(from, candidates, "up")).toBe(2)
	end)
	t.it("ranks in-beam candidates by leading-edge gap before centre offset (M2 with control frames)", function()
		local boost = r(17, 700, 687, 44)
		local candidates = { r(71, 272, 633, 44), r(164, 402, 392, 44), r(17, 480, 44, 190) }
		t.expect(FocusBeam.neighbor(boost, candidates, "up")).toBe(3)
	end)
	t.it("falls back to the half-plane and ignores candidates behind or overlapping", function()
		local from = r(100, 100, 100, 44)
		t.expect(FocusBeam.neighbor(from, { r(400, 400, 50, 50) }, "down")).toBe(1)
		t.expect(FocusBeam.neighbor(from, { r(100, 0, 100, 44) }, "down")).toBe(nil)
		t.expect(FocusBeam.neighbor(from, { r(120, 110, 20, 20) }, "down")).toBe(nil)
	end)
	t.it("works on every axis", function()
		local from = r(100, 100, 100, 100)
		local candidates = { r(300, 120, 50, 50), r(-100, 120, 50, 50), r(120, 300, 50, 50), r(120, -100, 50, 50) }
		t.expect(FocusBeam.neighbor(from, candidates, "right")).toBe(1)
		t.expect(FocusBeam.neighbor(from, candidates, "left")).toBe(2)
		t.expect(FocusBeam.neighbor(from, candidates, "down")).toBe(3)
		t.expect(FocusBeam.neighbor(from, candidates, "up")).toBe(4)
	end)
end)

local Facet = require("../src") :: any
local engineLib = require("./lib/native_engine")

local function world(build: (any, any) -> any): any
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	input.IsKeyDown = function()
		return false
	end
	local parent = engine.new("Folder")
	local UI = Facet.controls(
		runtime,
		{
			types = engine.types,
			guiService = gui,
			inputParent = parent,
			services = { GuiService = gui, UserInputService = input },
		} :: any
	)
	local stop, screen = runtime.mount(function()
		return runtime.constructors.ScreenGui({ build(UI, runtime.constructors, engine.types.Enum) })
	end, parent)
	local w = { engine = engine, gui = gui, UI = UI, screen = screen, parent = parent }
	function w.place(name: string, x: number, y: number, width: number, height: number)
		local node = assert(screen:FindFirstChild(name, true))
		node.AbsolutePosition = engine.types.Vector2.new(x, y)
		node.AbsoluteSize = engine.types.Vector2.new(width, height)
		return node
	end
	function w.stop()
		stop()
		runtime:dispose()
	end
	return w
end

t.describe("UI.focusQuery", function()
	t.it("reports the beam for free moves, capture on an adjusted axis, and a set link", function()
		local w = world(function(UI, Host)
			return Host.Frame({
				UI.Button("Top")({ label = "Top" }),
				UI.Stepper("Mid")({ value = Facet.Compose.cell(3), max = 9 }),
				UI.Button("Bottom")({ label = "Bottom" }),
				UI.Button("Side")({ label = "Side" }),
			})
		end)
		local top = w.place("Top", 100, 100, 200, 44)
		local mid = w.place("Mid", 100, 200, 200, 44)
		local bottom = w.place("Bottom", 100, 300, 200, 44)
		local side = w.place("Side", 400, 300, 200, 44)
		w.gui.SelectedObject = mid
		local moves = w.UI.focusQuery()
		t.expect(moves.Up.target).toBe(top)
		t.expect(moves.Up.rule).toBe("beam")
		t.expect(moves.Down.target).toBe(bottom)
		t.expect(moves.Left.rule).toBe("capture")
		t.expect(moves.Left.target).toBe(mid)
		bottom.NextSelectionRight = top
		t.expect(w.UI.focusQuery(bottom).Right.rule).toBe("link")
		t.expect(w.UI.focusQuery(bottom).Up.target).toBe(mid)
		t.expect(w.UI.focusQuery(side).Left.target).toBe(bottom)
		w.stop()
	end)

	t.it("searches an enclosing SelectionGroup first and honours Stop", function()
		local w = world(function(UI, Host)
			return Host.Frame({
				UI.Button("Outside")({ label = "Outside" }),
				Host.Frame({
					Name = "Group",
					SelectionGroup = true,
					UI.Button("A")({ label = "A" }),
					UI.Button("B")({ label = "B" }),
				}),
			})
		end)
		w.place("Outside", 100, 100, 100, 44)
		local a = w.place("A", 100, 300, 100, 44)
		local b = w.place("B", 400, 300, 100, 44)
		t.expect(w.UI.focusQuery(b).Left.target).toBe(a)
		t.expect(w.UI.focusQuery(a).Up.target.Name).toBe("Outside")
		w.screen:FindFirstChild("Group", true).SelectionBehaviorUp = w.engine.types.Enum.SelectionBehavior.Stop
		local up = w.UI.focusQuery(a).Up
		t.expect(up.target).toBe(nil)
		t.expect(up.rule).toBe("stop")
		w.stop()
	end)

	t.it("adds no per-frame work", function()
		local w = world(function(UI, Host)
			return Host.Frame({ UI.Button("A")({ label = "A" }), UI.Button("B")({ label = "B" }) })
		end)
		local before = w.engine.heartbeat.count()
		w.gui.SelectedObject = w.place("A", 0, 0, 100, 44)
		w.UI.focusQuery()
		t.expect(w.engine.heartbeat.count()).toBe(before)
		w.stop()
	end)
end)

return nil
