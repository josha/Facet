--!strict

type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type ScreenGuiConstructor = typeof(require("@repo/tools/typecheck/aliases").ScreenGuiConstructor)
type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")

local function r(x: number, y: number, w: number, h: number)
	return { x = x, y = y, width = w, height = h }
end

t.describe("the beam neighbour", function()
	t.it("prefers an in-beam candidate by gap, even when an out-of-beam one is nearer", function()
		local from = r(300, 600, 600, 44)
		local candidates = { r(100, 520, 44, 44), r(500, 200, 300, 44) }
		t.expect(Compose.focusNeighbor(from, candidates, "up")).toBe(2)
	end)
	t.it("ranks in-beam candidates by leading-edge gap before centre offset (M2 with control frames)", function()
		local boost = r(17, 700, 687, 44)
		local candidates = { r(71, 272, 633, 44), r(164, 402, 392, 44), r(17, 480, 44, 190) }
		t.expect(Compose.focusNeighbor(boost, candidates, "up")).toBe(3)
	end)
	t.it("falls back to the half-plane and ignores candidates behind or overlapping", function()
		local from = r(100, 100, 100, 44)
		t.expect(Compose.focusNeighbor(from, { r(400, 400, 50, 50) }, "down")).toBe(1)
		t.expect(Compose.focusNeighbor(from, { r(100, 0, 100, 44) }, "down")).toBe(nil)
		t.expect(Compose.focusNeighbor(from, { r(120, 110, 20, 20) }, "down")).toBe(nil)
	end)
	t.it("breaks a gap tie by centre offset", function()
		local from = r(100, 100, 100, 44)
		t.expect(Compose.focusNeighbor(from, { r(180, 200, 100, 44), r(110, 200, 100, 44) }, "down")).toBe(2)
	end)
	t.it("a candidate is ahead when it starts past the control's centre and ends past its edge", function()
		local tab = r(850.5, 59, 68.5, 44)
		t.expect(Compose.focusNeighbor(tab, { r(886.5, 108, 71, 44) }, "right")).toBe(1)
		t.expect(Compose.focusNeighbor(tab, { r(883, 108, 71, 44) }, "right")).toBe(nil)
		local header = r(16, 809, 741, 44)
		t.expect(Compose.focusNeighbor(header, { r(511.67, 605, 242.33, 44) }, "right")).toBe(nil)
		t.expect(Compose.focusNeighbor(header, { r(511.67, 605, 250, 44) }, "right")).toBe(1)
	end)
	t.it(
		"out of the beam, a candidate within 45 degrees ranks by cross offset, even when much farther (F12)",
		function()
			local from = r(100, 500, 100, 44)
			t.expect(Compose.focusNeighbor(from, { r(430, 250, 40, 44), r(1030, 200, 40, 44) }, "right")).toBe(2)
			local source = r(100, 400, 100, 44)
			t.expect(Compose.focusNeighbor(source, { r(520, 100, 40, 40), r(1030, 85, 40, 40) }, "right")).toBe(1)
			t.expect(Compose.focusNeighbor(source, { r(460, 100, 40, 40), r(1030, 85, 40, 40) }, "right")).toBe(2)
		end
	)
	t.it("out of the beam, the nearer of two equally offset candidates wins", function()
		local toolbar = r(161.5, 8, 101.5, 44)
		t.expect(Compose.focusNeighbor(toolbar, { r(623, 56, 296, 50), r(629, 59, 68, 44) }, "right")).toBe(2)
	end)
	t.it("works on every axis", function()
		local from = r(100, 100, 100, 100)
		local candidates = { r(300, 120, 50, 50), r(-100, 120, 50, 50), r(120, 300, 50, 50), r(120, -100, 50, 50) }
		t.expect(Compose.focusNeighbor(from, candidates, "right")).toBe(1)
		t.expect(Compose.focusNeighbor(from, candidates, "left")).toBe(2)
		t.expect(Compose.focusNeighbor(from, candidates, "down")).toBe(3)
		t.expect(Compose.focusNeighbor(from, candidates, "up")).toBe(4)
	end)
end)

local Facet = require("../src") :: any
local engineLib = require("./lib/native_engine")

local function world(build: (any, any) -> any): any
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
	local stop, screen: any = runtime.mount(function()
		return ((runtime.constructors.ScreenGui :: unknown) :: ScreenGuiConstructor)({
			(build :: (any, any, any) -> any)(UI, runtime.constructors, engine.types.Enum),
		})
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
		local w = world(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame({
				UI.Button("Top")({ label = "Top" }) :: unknown,
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
		local w = world(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame({
				UI.Button("Outside")({ label = "Outside" }) :: unknown,
				Host.Frame({
					Name = "Group",
					SelectionGroup = true,
					UI.Button("A")({ label = "A" }) :: unknown,
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

	t.it("reports capture on an adjustable's own axis before it is selected", function()
		local w = world(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame({
				UI.Button("L")({ label = "L" }) :: unknown,
				UI.Stepper("Volume")({ value = Facet.Compose.cell(3), max = 9 }),
				UI.Slider("Rear")({ value = Facet.Compose.cell(3), min = 0, max = 9, axis = "y" :: "y" }),
				UI.Button("Below")({ label = "Below" }),
			})
		end)
		w.place("L", 0, 100, 80, 44)
		local volume = w.place("Volume", 100, 100, 200, 44)
		local rear = w.place("Rear", 400, 50, 44, 200)
		w.place("Below", 100, 300, 200, 44)
		local moves = w.UI.focusQuery(volume)
		t.expect(`{moves.Left.rule} {moves.Left.target and moves.Left.target.Name}`).toBe("capture Volume")
		t.expect(moves.Right.rule).toBe("capture")
		t.expect(moves.Down.target.Name).toBe("Below")
		local vertical = w.UI.focusQuery(rear)
		t.expect(vertical.Up.rule).toBe("capture")
		t.expect(vertical.Left.rule).toBe("beam")
		w.stop()
	end)

	t.it("does not report capture for a disabled value control", function()
		local w = world(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame({
				UI.Button("L")({ label = "L" }) :: unknown,
				UI.Stepper("Volume")({ value = Facet.Compose.cell(3), max = 9, enabled = false }),
			})
		end)
		w.place("L", 0, 100, 80, 44)
		local volume = w.place("Volume", 100, 100, 200, 44)
		t.expect(w.UI.focusQuery(volume).Left.rule).toBe("beam")
		w.stop()
	end)

	t.it("searches nested SelectionGroups inside out and honours an outer Stop", function()
		local w = world(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame({
				UI.Button("Out")({ label = "Out" }) :: unknown,
				Host.Frame({
					Name = "Outer",
					SelectionGroup = true,
					UI.Button("Sibling")({ label = "Sibling" }) :: unknown,
					Host.Frame({ Name = "Inner", SelectionGroup = true, UI.Button("A")({ label = "A" }) }),
				}),
			})
		end)
		w.place("Out", 100, 0, 100, 44)
		w.place("Sibling", 100, 100, 100, 44)
		local a = w.place("A", 100, 300, 100, 44)
		t.expect(w.UI.focusQuery(a).Up.target.Name).toBe("Sibling")
		w.place("Sibling", 400, 400, 100, 44)
		t.expect(w.UI.focusQuery(a).Up.target.Name).toBe("Out")
		w.screen:FindFirstChild("Outer", true).SelectionBehaviorUp = w.engine.types.Enum.SelectionBehavior.Stop
		local up = w.UI.focusQuery(a).Up
		t.expect(`{up.rule} {up.target}`).toBe("stop nil")
		w.stop()
	end)

	t.it("ignores a link to a hidden or unselectable target, zero-size and off-screen candidates", function()
		local w = world(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame({
				UI.Button("From")({ label = "From" }) :: unknown,
				UI.Button("Hidden")({ label = "Hidden" }),
				UI.Button("Flat")({ label = "Flat" }),
				UI.Button("Away")({ label = "Away" }),
				UI.Button("Near")({ label = "Near" }),
			})
		end)
		w.screen.AbsoluteSize = w.engine.types.Vector2.new(1000, 800)
		local from = w.place("From", 100, 100, 100, 44)
		local hidden = w.place("Hidden", 400, 100, 100, 44)
		w.place("Flat", 100, 200, 100, 0)
		w.place("Away", 100, 900, 100, 44)
		w.place("Near", 100, 400, 100, 44)
		hidden.Visible = false
		from.NextSelectionRight = hidden
		t.expect(w.UI.focusQuery(from).Right.rule).toBe("none")
		t.expect(w.UI.focusQuery(from).Down.target.Name).toBe("Near")
		w.place("Near", 100, 950, 100, 44)
		t.expect(w.UI.focusQuery(from).Down.rule).toBe("none")
		w.stop()
	end)

	t.it("a scroll child is a candidate off its window only from inside the same scroll container", function()
		local w = world(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame({
				UI.Button("Above")({ label = "Above" }) :: unknown,
				Host.ScrollingFrame("Scroller")({
					Selectable = false,
					UI.Button("Row1")({ label = "Row1" }) :: unknown,
					UI.Button("Row2")({ label = "Row2" }),
				}),
				UI.Button("Far")({ label = "Far" }),
			})
		end)
		w.screen.AbsoluteSize = w.engine.types.Vector2.new(1000, 800)
		local above = w.place("Above", 100, 20, 300, 44)
		w.place("Scroller", 100, 100, 320, 200)
		local row1 = w.place("Row1", 100, -150, 300, 44)
		local row2 = w.place("Row2", 100, 350, 300, 44)
		w.place("Far", 100, 700, 300, 44)
		t.expect(w.UI.focusQuery(above).Down.target.Name).toBe("Far")
		t.expect(w.UI.focusQuery(row2).Up.target).toBe(row1)
		w.place("Row2", 100, 280, 300, 44)
		t.expect(w.UI.focusQuery(above).Down.target).toBe(row2)
		w.stop()
	end)

	t.it("a multi-line text field below the screen is reached through its viewport (F6c)", function()
		local w = world(function(UI: FacetControls, Host: RobloxHost)
			return Host.ScrollingFrame("Page")({
				Selectable = false,
				UI.Button("Above")({ label = "Above" }) :: unknown,
				UI.TextInput("Notes")({ value = Facet.Compose.cell(""), multiline = true, visibleLines = 3 }),
			})
		end)
		w.screen.AbsoluteSize = w.engine.types.Vector2.new(1000, 1000)
		w.place("Page", 0, 0, 1000, 1000)
		local above = w.place("Above", 20, 950, 300, 44)
		local viewport = w.place("Viewport", 20, 1100, 900, 70)
		local field = assert(viewport:FindFirstChildWhichIsA("TextBox", true))
		w.place(field.Name, 20, 1100, 900, 28)
		field.AbsolutePosition = w.engine.types.Vector2.new(20, 1100)
		field.AbsoluteSize = w.engine.types.Vector2.new(900, 28)
		t.expect(w.UI.focusQuery(above).Down.target).toBe(field)
		w.stop()
	end)

	t.it("a selectable scroll container ranks by its own rectangle, like a control (F16)", function()
		local w = world(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame({
				UI.Button("Above")({ label = "Above" }) :: unknown,
				UI.Button("Right")({ label = "Right" }),
				Host.ScrollingFrame("Scroller")({
					Selectable = true,
					UI.Button("Clipped")({ label = "Clipped" }),
				}),
			})
		end)
		w.screen.AbsoluteSize = w.engine.types.Vector2.new(1000, 800)
		local above = w.place("Above", 100, 20, 300, 44)
		w.place("Right", 600, 120, 100, 44)
		w.place("Scroller", 100, 100, 320, 200)
		local clipped = w.place("Clipped", 100, 350, 300, 44)
		local down = w.UI.focusQuery(above).Down
		t.expect(down.target).toBe(clipped)
		t.expect(down.rule).toBe("beam")
		w.stop()
	end)

	t.it("a SelectionGroup counts through a Folder between it and the control", function()
		local w = world(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame({
				UI.Button("Near")({ label = "Near" }) :: unknown,
				Host.Frame({
					Name = "Group",
					SelectionGroup = true,
					Host.Folder({
						UI.Button("Top")({ label = "Top" }) :: unknown,
						UI.Button("Low")({ label = "Low" }),
					}),
				}),
			})
		end)
		local top = w.place("Top", 100, 100, 687, 44)
		local low = w.place("Low", 100, 300, 44, 100)
		w.place("Near", 400, 160, 200, 44)
		t.expect(w.UI.focusQuery(top).Down.target).toBe(low)
		w.stop()
	end)

	t.it("at a limit a value control's axis reports the control beyond it", function()
		local value = Facet.Compose.cell(0)
		local w = world(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame({
				UI.Button("L")({ label = "L" }) :: unknown,
				UI.Stepper("Volume")({ value = value, max = 9 }),
				UI.Button("R")({ label = "R" }),
			})
		end)
		local l = w.place("L", 0, 100, 100, 44)
		local volume = w.place("Volume", 120, 100, 200, 44)
		w.place("R", 340, 100, 100, 44)
		t.expect(w.UI.focusQuery(volume).Left.target).toBe(l)
		t.expect(w.UI.focusQuery(volume).Right.rule).toBe("capture")
		w.stop()
	end)

	t.it("adds no per-frame work", function()
		local w = world(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame({ UI.Button("A")({ label = "A" }) :: unknown, UI.Button("B")({ label = "B" }) })
		end)
		local before = w.engine.heartbeat.count()
		w.gui.SelectedObject = w.place("A", 0, 0, 100, 44)
		w.UI.focusQuery()
		t.expect(w.engine.heartbeat.count()).toBe(before)
		w.stop()
	end)
end)

return nil
