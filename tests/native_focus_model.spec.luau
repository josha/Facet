--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local engineLib = require("./lib/native_engine")
local Compose: ComposeModule = Facet.Compose

local function setup(build: (any, any) -> any, options: { [string]: any }?): any
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
	input.KeyboardEnabled = true
	local parent = engine.new("Folder")
	local config: { [string]: any } = {
		types = engine.types,
		guiService = gui,
		inputParent = parent,
		services = { GuiService = gui, UserInputService = input },
	}
	for key, value in (options or {} :: { [string]: any }) do
		config[key] = value
	end
	local UI = Facet.controls(runtime, config)
	local Host = (runtime.constructors :: unknown) :: RobloxHost
	local stop, screen: any = runtime.mount(function()
		return Host.ScreenGui({ build(UI, Host) })
	end, parent)
	local world = { engine = engine, runtime = runtime, gui = gui, input = input, screen = screen, parent = parent }
	function world.find(name: string, root: any?): any
		local at = root or screen
		if at.Name == name then
			return at
		end
		for _, child in at:GetChildren() do
			local found = world.find(name, child)
			if found then
				return found
			end
		end
		return nil
	end
	function world.tab()
		world.find("Traverse", parent).Pressed.fire()
	end
	function world.selected(): string
		return if gui.SelectedObject then gui.SelectedObject.Name else "nil"
	end
	function world.activateKeys(): { string }
		local keys = {}
		local context = world.find("FacetActivate", parent)
		if context and context.Enabled then
			for _, binding in context:FindFirstChild("Activate"):GetChildren() do
				table.insert(keys, binding.KeyCode.Name)
			end
		end
		table.sort(keys)
		return keys
	end
	function world.stop()
		stop()
		runtime:dispose()
	end
	return world
end

t.describe("Tab traversal priority and the keyboard opt-in", function()
	t.it("walks Tab by SelectionOrder tier, then document order within a tier", function()
		local w = setup(function(UI: FacetControls)
			return UI.Screen "Page" {
				UI.Button "A" { label = "A" } :: unknown,
				UI.Button "Late" { label = "Late", SelectionOrder = 5 },
				UI.Button "B" { label = "B" },
				UI.Button "First" { label = "First", SelectionOrder = -1 },
			}
		end)
		local names = {}
		for _ = 1, 4 do
			w.tab()
			table.insert(names, w.selected())
		end
		t.expect(names).toEqual({ "First", "A", "B", "Late" })
		w.tab()
		t.expect(w.selected()).toBe("First")
		w.stop()
	end)
	t.it("binds Tab only while a keyboard is live and keyboardNavigation is not false", function()
		local w = setup(function(UI: FacetControls)
			return UI.Button "A" { label = "A" }
		end)
		local context = w.find("FacetTraversal", w.parent)
		t.expect(context.Enabled).toBe(true)
		w.input.KeyboardEnabled = false
		t.expect(context.Enabled).toBe(false)
		w.input.KeyboardEnabled = true
		t.expect(context.Enabled).toBe(true)
		w.stop()
		local off = setup(function(UI: FacetControls)
			return UI.Button "A" { label = "A" }
		end, { keyboardNavigation = false })
		t.expect(off.find("FacetTraversal", off.parent).Enabled).toBe(false)
		off.stop()
	end)
end)

t.describe("stick entry", function()
	t.it("a left-stick push enters the selection like a D-pad press; a drift does not", function()
		local w = setup(function(UI: FacetControls)
			return UI.Screen "Page" { UI.Button "A" { label = "A" } :: unknown, UI.Button "B" { label = "B" } }
		end)
		local V2 = w.engine.types.Vector2
		local context = w.find("FacetEntry", w.parent)
		t.expect(context.Sink).toBe(false)
		local enter = context:FindFirstChild("Enter")
		enter.StateChanged.fire(V2.new(0.2, -0.1))
		t.expect(w.selected()).toBe("nil")
		enter.StateChanged.fire(V2.new(0, -1))
		t.expect(w.selected()).toBe("A")
		w.stop()
	end)
end)

t.describe("leaving the gamepad", function()
	t.it(
		"drops a pad selection when the preferred input leaves the gamepad, so the engine cannot eat typed WASD",
		function()
			local w = setup(function(UI: FacetControls)
				return UI.Screen "Page" { UI.Button "Q" { label = "Q" } :: unknown, UI.Button "W" { label = "W" } }
			end)
			local E = w.engine.types.Enum
			local last = E.UserInputType.Gamepad1
			w.input.GetLastInputType = function()
				return last
			end
			w.input.PreferredInput = E.PreferredInput.Gamepad
			w.find("FacetEntry", w.parent):FindFirstChild("Enter").StateChanged.fire(w.engine.types.Vector2.new(0, -1))
			t.expect(w.selected()).toBe("Q")
			w.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
			t.expect(w.selected()).toBe("nil")
			last = E.UserInputType.Keyboard
			w.tab()
			t.expect(w.selected()).toBe("Q")
			w.input.PreferredInput = E.PreferredInput.Gamepad
			w.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
			t.expect(w.selected()).toBe("Q")
			w.stop()
		end
	)

	t.it("keeps a first Tab that lands before the preferred input leaves the gamepad", function()
		local w = setup(function(UI: FacetControls)
			return UI.Screen "Page" { UI.Button "Q" { label = "Q" } :: unknown, UI.Button "W" { label = "W" } }
		end)
		local E = w.engine.types.Enum
		w.input.GetLastInputType = function()
			return E.UserInputType.Keyboard
		end
		w.input.PreferredInput = E.PreferredInput.Gamepad
		w.tab()
		t.expect(w.selected()).toBe("Q")
		w.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
		t.expect(w.selected()).toBe("Q")
		w.stop()
	end)

	t.it("leaves a game's own pad selection outside Facet alone", function()
		local own: any
		local w = setup(function(UI: FacetControls, Host: RobloxHost)
			own = Host.TextButton { Name = "GameMenu", Selectable = true }
			return Host.Frame { Name = "Legacy", own :: unknown, UI.Screen "Page" { UI.Button "Q" { label = "Q" } } }
		end)
		local E = w.engine.types.Enum
		w.input.GetLastInputType = function()
			return E.UserInputType.Gamepad1
		end
		w.input.PreferredInput = E.PreferredInput.Gamepad
		w.gui.SelectedObject = own
		w.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
		t.expect(w.selected()).toBe("GameMenu")
		w.stop()
	end)
end)

t.describe("focusSection entry rules", function()
	local function sections(options: { [string]: any }?)
		local shelf: any
		local w = setup(function(UI: FacetControls, Host: RobloxHost)
			shelf = UI.HStack "Shelf" {
				UI.Button "One" { label = "One" } :: unknown,
				UI.Button "Two" { label = "Two" },
				UI.Button "Three" { label = "Three" },
			}
			UI.focusSection(shelf, options)
			return Host.Frame "Page" {
				UI.Button "Outside" { label = "Outside" } :: unknown,
				shelf,
			}
		end)
		return w
	end
	t.it("restores the remembered item, and a preferred item wins the first entry", function()
		local w = sections({ preferred = "Two" })
		w.gui.SelectedObject = w.find("Outside")
		w.gui.SelectedObject = w.find("Three")
		t.expect(w.selected()).toBe("Two")
		w.gui.SelectedObject = w.find("One")
		w.gui.SelectedObject = w.find("Outside")
		w.gui.SelectedObject = w.find("Three")
		t.expect(w.selected()).toBe("One")
		w.stop()
	end)
	t.it("entry first lands on the first item every time; nearest leaves the engine's choice", function()
		local first = sections({ entry = "first" })
		first.gui.SelectedObject = first.find("Outside")
		first.gui.SelectedObject = first.find("Three")
		t.expect(first.selected()).toBe("One")
		first.gui.SelectedObject = first.find("Two")
		first.gui.SelectedObject = first.find("Outside")
		first.gui.SelectedObject = first.find("Three")
		t.expect(first.selected()).toBe("One")
		first.stop()
		local nearest = sections({ entry = "nearest", preferred = "Two" })
		nearest.gui.SelectedObject = nearest.find("One")
		nearest.gui.SelectedObject = nearest.find("Outside")
		nearest.gui.SelectedObject = nearest.find("Three")
		t.expect(nearest.selected()).toBe("Three")
		nearest.stop()
	end)
	t.it("refuses an unknown option, entry or a missing group", function()
		local w = setup(function(UI, Host: RobloxHost)
			local group = Host.Frame {}
			t.expect(pcall(UI.focusSection, group, { entry = "random" })).toBe(false)
			t.expect(pcall(UI.focusSection, group, { enter = "first" })).toBe(false)
			t.expect(pcall(UI.focusSection, nil)).toBe(false)
			return group
		end)
		w.stop()
	end)
end)

t.describe("focusSection focusOnAppear and returnFocus", function()
	t.it("lands on the appearing branch and returns to the row that opened it", function()
		local open = Compose.cell(false)
		local w = setup(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame "Page" {
				UI.Button "Row" { label = "Row" } :: unknown,
				Compose.show(open, function()
					local detail = UI.VStack "Detail" {
						UI.Button "Title" { label = "Title" } :: unknown,
						UI.Button "Back" { label = "Back" },
					}
					UI.focusSection(detail, { focusOnAppear = "Back", returnFocus = true })
					return detail
				end),
			}
		end)
		w.gui.SelectedObject = w.find("Row")
		open:set(true)
		t.expect(w.selected()).toBe("Back")
		open:set(false)
		t.expect(w.selected()).toBe("Row")
		w.stop()
	end)
	t.it("does not take the selection when nothing is selected (a touch or mouse player)", function()
		local open = Compose.cell(false)
		local w = setup(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame "Page" {
				UI.Button "Row" { label = "Row" } :: unknown,
				Compose.show(open, function()
					local detail = UI.VStack "Detail" { UI.Button "Back" { label = "Back" } }
					UI.focusSection(detail, { focusOnAppear = true, returnFocus = true })
					return detail
				end),
			}
		end)
		open:set(true)
		t.expect(w.selected()).toBe("nil")
		open:set(false)
		t.expect(w.selected()).toBe("nil")
		w.stop()
	end)
	t.it("without the keys the selection stays where the engine left it", function()
		local open = Compose.cell(false)
		local w = setup(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame "Page" {
				UI.Button "Row" { label = "Row" } :: unknown,
				Compose.show(open, function()
					local detail = UI.VStack "Detail" { UI.Button "Back" { label = "Back" } }
					UI.focusSection(detail)
					return detail
				end),
			}
		end)
		w.gui.SelectedObject = w.find("Row")
		open:set(true)
		t.expect(w.selected()).toBe("Row")
		w.stop()
	end)
end)

t.describe("responder: engage, resign and the gameplay guard (DK-13/DK-15)", function()
	local function form(options: { [string]: any }?)
		local responder: any
		local presses: { [string]: number } = {}
		local w = setup(function(UI: FacetControls)
			local hud = UI.Screen "Hud" {
				UI.Button "One" {
					label = "One",
					onActivate = function()
						presses.one = (presses.one or 0) + 1
					end,
				} :: unknown,
				UI.Button "Two" {
					label = "Two",
					onActivate = function()
						presses.two = (presses.two or 0) + 1
					end,
				},
				UI.Button "Three" { label = "Three" },
			}
			responder = UI.responder(hud, options)
			return hud
		end)
		w.responder, w.presses = responder, presses
		function w.traversal(): boolean
			return w.find("FacetTraversal", w.parent).Enabled
		end
		function w.guard(): boolean
			local guard = w.find("FacetGameplayGuard", w.parent)
			return guard ~= nil and guard.Enabled
		end
		function w.tap(hits: { any }, kind: string?)
			w.parent.GetGuiObjectsAtPosition = function()
				return hits
			end
			local E = w.engine.types.Enum
			w.input.InputBegan.fire({
				UserInputType = if kind == "touch" then E.UserInputType.Touch else E.UserInputType.MouseButton1,
				KeyCode = E.KeyCode:FromValue(0),
				Position = w.engine.types.Vector3.new(10, 10, 0),
			}, true)
		end
		return w
	end
	t.it("a passive surface at rest binds no Tab and no guard: the game keeps the keys", function()
		local w = form()
		t.expect(w.responder.state:peek()).toBe("passive")
		t.expect(w.traversal()).toBe(false)
		t.expect(w.guard()).toBe(false)
		local E = w.engine.types.Enum
		w.input.InputBegan.fire({ UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.DPadDown }, false)
		t.expect(w.selected()).toBe("nil")
		w.stop()
	end)
	t.it("engage() binds Tab and the guard; the first Tab enters, resign() gives the keys back", function()
		local w = form()
		w.responder.engage()
		t.expect(w.responder.state:peek()).toBe("engaged")
		t.expect(w.traversal()).toBe(true)
		t.expect(w.guard()).toBe(true)
		w.tab()
		t.expect(w.selected()).toBe("One")
		w.tab()
		t.expect(w.selected()).toBe("Two")
		w.responder.resign()
		t.expect(w.responder.state:peek()).toBe("passive")
		t.expect(w.selected()).toBe("nil")
		t.expect(w.traversal()).toBe(false)
		t.expect(w.guard()).toBe(false)
		w.stop()
	end)
	t.it("a tap on the surface engages on the tapped control; a tap outside resigns", function()
		local w = form()
		w.tap({ w.find("One") })
		t.expect(w.responder.state:peek()).toBe("engaged")
		t.expect(w.selected()).toBe("One")
		w.tab()
		t.expect(w.selected()).toBe("Two")
		w.tap({}, "touch")
		t.expect(w.responder.state:peek()).toBe("passive")
		t.expect(w.selected()).toBe("nil")
		t.expect(w.traversal()).toBe(false)
		w.stop()
	end)
	t.it("the selection entering the surface engages it; Cancel resigns it", function()
		local w = form()
		w.gui.SelectedObject = w.find("Two")
		t.expect(w.responder.state:peek()).toBe("engaged")
		local cancel = w.find("FacetResponderCancel", w.parent)
		t.expect(cancel.Sink).toBe(false)
		cancel:FindFirstChild("Cancel").Pressed.fire()
		t.expect(w.responder.state:peek()).toBe("passive")
		t.expect(w.selected()).toBe("nil")
		w.stop()
	end)
	t.it("passive = false is engaged-open: always engaged, resign() changes nothing", function()
		local w = form({ passive = false })
		t.expect(w.responder.state:peek()).toBe("engaged")
		t.expect(w.traversal()).toBe(true)
		w.responder.resign()
		t.expect(w.responder.state:peek()).toBe("engaged")
		w.stop()
	end)
	t.it("gameplayGuard = false binds neither the guard nor Space on its buttons", function()
		local w = form({ gameplayGuard = false })
		w.responder.engage()
		t.expect(w.guard()).toBe(false)
		w.gui.SelectedObject = w.find("One")
		t.expect(w.activateKeys()).toEqual({ "Return" })
		w.stop()
	end)
	t.it("refuses an unknown option and a missing root", function()
		local w = setup(function(UI, Host: RobloxHost)
			local root = Host.Frame {}
			t.expect(pcall(UI.responder, root, { pasive = true })).toBe(false)
			t.expect(pcall(UI.responder, nil)).toBe(false)
			return root
		end)
		w.stop()
	end)
end)

t.describe("traversalWrap (DK-3)", function()
	t.it("traversalWrap = false stops Tab at the last control and Shift+Tab at the first", function()
		local w = setup(function(UI: FacetControls)
			local page = UI.Screen "Page" {
				UI.Button "A" { label = "A" } :: unknown,
				UI.Button "B" { label = "B" },
			}
			UI.responder(page, { passive = false, traversalWrap = false })
			return page
		end)
		w.tab()
		w.tab()
		t.expect(w.selected()).toBe("B")
		w.tab()
		t.expect(w.selected()).toBe("B")
		w.input.IsKeyDown = function()
			return true
		end
		w.tab()
		t.expect(w.selected()).toBe("A")
		w.tab()
		t.expect(w.selected()).toBe("A")
		w.stop()
	end)
end)

t.describe("keyboardNavigation = false", function()
	t.it("binds no Tab and no Space; Return still activates", function()
		local w = setup(function(UI: FacetControls)
			return UI.Screen "Page" { UI.Button "A" { label = "A" } }
		end, { keyboardNavigation = false })
		w.gui.SelectedObject = w.find("A")
		t.expect(w.find("FacetTraversal", w.parent).Enabled).toBe(false)
		t.expect(w.activateKeys()).toEqual({ "Return" })
		w.stop()
	end)
	t.it("true (and the default) binds Tab, and Space next to Return on a selected Button", function()
		for _, options in { {}, { keyboardNavigation = true } } do
			local w = setup(function(UI: FacetControls)
				return UI.Screen "Page" { UI.Button "A" { label = "A" } }
			end, options)
			t.expect(w.find("FacetTraversal", w.parent).Enabled).toBe(true)
			w.gui.SelectedObject = w.find("A")
			t.expect(w.activateKeys()).toEqual({ "Return", "Space" })
			w.stop()
		end
	end)
end)

t.describe("Grid: a ragged last line has an answer (native NextSelection)", function()
	local function grid(count: number, flow: ("row" | "column")?)
		local cells = Compose.cell(count)
		local w = setup(function(UI: FacetControls)
			return UI.Grid "Cells" {
				columns = 4,
				flow = flow,
				Compose.keyed({
					from = function(use: Use): { number }
						local list: { number } = {}
						for index = 1, use(cells) do
							table.insert(list, index)
						end
						return list
					end,
					key = function(value: number)
						return value
					end,
					render = function(_, position, key: number): GuiObject
						return UI.Button("c" .. key)({ label = tostring(key), LayoutOrder = position })
					end,
				}),
			}
		end)
		w.cells = cells
		function w.down(name: string): string
			local target = w.find(name).NextSelectionDown
			return if target then target.Name else "nil"
		end
		return w
	end
	t.it("Down from a lane the last line does not reach clamps to the last cell", function()
		local w = grid(10)
		t.expect(w.down("c7")).toBe("c10")
		t.expect(w.down("c8")).toBe("c10")
		t.expect(w.down("c5")).toBe("nil")
		t.expect(w.down("c6")).toBe("nil")
		t.expect(w.down("c9")).toBe("nil")
		t.expect(w.down("c10")).toBe("nil")
		w.cells:set(12)
		t.expect(w.down("c7")).toBe("nil")
		t.expect(w.down("c8")).toBe("nil")
		w.cells:set(13)
		t.expect(w.down("c10")).toBe("c13")
		t.expect(w.down("c12")).toBe("c13")
		t.expect(w.down("c9")).toBe("nil")
		w.stop()
	end)
	t.it("a single short line needs no clamp", function()
		local w = grid(3)
		t.expect(w.down("c1")).toBe("nil")
		w.stop()
	end)
	t.it("flow = column clamps Right into a short last column", function()
		local w = grid(10, "column")
		local function right(name: string): string
			local target = w.find(name).NextSelectionRight
			return if target then target.Name else "nil"
		end

		t.expect(right("c8")).toBe("c10")
		t.expect(right("c9")).toBe("c10")
		t.expect(right("c7")).toBe("nil")
		w.stop()
	end)
end)
