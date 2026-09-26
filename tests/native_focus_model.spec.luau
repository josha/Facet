--!strict
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose

local function setup(build: (any, any) -> any, options: { [string]: any }?): any
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
	input.KeyboardEnabled = true
	local parent = engine.new("Folder")
	local config: { [string]: any } = {
		types = engine.types,
		guiService = gui,
		inputParent = parent,
		services = { GuiService = gui, UserInputService = input },
	}
	for key, value in options or {} do
		config[key] = value
	end
	local UI = Facet.controls(runtime, config)
	local Host = runtime.constructors
	local stop, screen = runtime.mount(function()
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
	function world.stop()
		stop()
		runtime:dispose()
	end
	return world
end

t.describe("Tab traversal priority and the keyboard opt-in", function()
	t.it("walks Tab by SelectionOrder tier, then document order within a tier", function()
		local w = setup(function(UI)
			return UI.Screen "Page" {
				UI.Button "A" { label = "A" },
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
		local w = setup(function(UI)
			return UI.Button "A" { label = "A" }
		end)
		local context = w.find("FacetTraversal", w.parent)
		t.expect(context.Enabled).toBe(true)
		w.input.KeyboardEnabled = false
		t.expect(context.Enabled).toBe(false)
		w.input.KeyboardEnabled = true
		t.expect(context.Enabled).toBe(true)
		w.stop()
		local off = setup(function(UI)
			return UI.Button "A" { label = "A" }
		end, { keyboardNavigation = false })
		t.expect(off.find("FacetTraversal", off.parent).Enabled).toBe(false)
		off.stop()
	end)
end)

t.describe("stick entry", function()
	t.it("a left-stick push enters the selection like a D-pad press; a drift does not", function()
		local w = setup(function(UI)
			return UI.Screen "Page" { UI.Button "A" { label = "A" }, UI.Button "B" { label = "B" } }
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

t.describe("focusSection entry rules", function()
	local function sections(options: { [string]: any }?)
		local shelf: any
		local w = setup(function(UI, Host)
			shelf = UI.HStack "Shelf" {
				UI.Button "One" { label = "One" },
				UI.Button "Two" { label = "Two" },
				UI.Button "Three" { label = "Three" },
			}
			UI.focusSection(shelf, options)
			return Host.Frame "Page" {
				UI.Button "Outside" { label = "Outside" },
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
		local w = setup(function(UI, Host)
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
		local w = setup(function(UI, Host)
			return Host.Frame "Page" {
				UI.Button "Row" { label = "Row" },
				Compose.show(open, function()
					local detail = UI.VStack "Detail" {
						UI.Button "Title" { label = "Title" },
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
		local w = setup(function(UI, Host)
			return Host.Frame "Page" {
				UI.Button "Row" { label = "Row" },
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
		local w = setup(function(UI, Host)
			return Host.Frame "Page" {
				UI.Button "Row" { label = "Row" },
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
