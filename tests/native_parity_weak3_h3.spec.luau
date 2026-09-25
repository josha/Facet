--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose

type World = {
	engine: any,
	runtime: any,
	gui: any,
	input: any,
	screen: any,
	stop: () -> (),
}

local function world(build: (any, any) -> any, options: { [string]: any }?): World
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
	local config: { [string]: any } = {
		types = engine.types,
		guiService = gui,
		reducedMotion = true,
		services = { GuiService = gui, UserInputService = input },
	}
	for key, value in (options or {}) :: { [string]: any } do
		config[key] = value
	end
	local UI = Facet.controls(runtime, config :: any)
	local Host = runtime.constructors
	local stop, screen = runtime.mount(function()
		return Host.ScreenGui({ build(UI, Host) })
	end, engine.new("Folder"))
	return {
		engine = engine,
		runtime = runtime,
		gui = gui,
		input = input,
		screen = screen,
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

t.describe("weak3 RowActions outside tap", function()
	local function rowsWorld(role: string?, reducedMotion: boolean): (World, { [string]: any })
		local state: { [string]: any } = {
			open = { a = Compose.cell(nil), b = Compose.cell(nil) },
			coordinator = Compose.cell(nil),
			fired = {},
			content = { a = 0, b = 0 },
			hud = 0,
		}
		local w = world(function(UI, Host)
			local function row(name: string)
				return UI.RowActions({
					Name = name,
					open = state.open[name],
					coordinator = state.coordinator,
					content = function()
						return Host.TextButton "Body" {
							Text = name,
							Activated = function()
								state.content[name] += 1
							end,
						}
					end,
					trailing = {
						{
							id = "Delete",
							label = "Delete",
							role = role,
							onActivate = function()
								table.insert(state.fired, name)
							end,
						},
					},
				})
			end
			return Host.Frame "Hud" {
				row("a"),
				row("b"),
				Host.TextButton "Boost" {
					Text = "Boost",
					Activated = function()
						state.hud += 1
					end,
				},
			}
		end, { reducedMotion = reducedMotion })
		local V2 = w.engine.types.Vector2
		local a, b, boost = find(w.screen, "a"), find(w.screen, "b"), find(w.screen, "Boost")
		a.AbsolutePosition, a.AbsoluteSize = V2.new(0, 0), V2.new(300, 44)
		b.AbsolutePosition, b.AbsoluteSize = V2.new(0, 44), V2.new(300, 44)
		boost.AbsolutePosition, boost.AbsoluteSize = V2.new(600, 500), V2.new(80, 80)
		return w, state
	end
	local function tap(w: World, x: number, y: number)
		local E = w.engine.types.Enum
		w.input.InputBegan.fire({
			UserInputType = E.UserInputType.Touch,
			UserInputState = E.UserInputState.Begin,
			Position = w.engine.types.Vector3.new(x, y, 0),
		}, true)
	end
	local function sinking(w: World): { string }
		local out = {}
		for _, node in w.screen:GetDescendants() do
			if node:IsA("InputContext") and node.Enabled and node.Sink then
				table.insert(out, node.Name)
			end
		end
		return out
	end

	t.it("keeps a destructive commit running through a tap on another row and still activates that row", function()
		local w, state = rowsWorld("destructive", false)
		state.open.a:set("trailing")
		w.engine.heartbeat.fire(0.3)
		find(find(w.screen, "a"), "Delete").Activated.fire()
		t.expect(state.fired).toEqual({})
		tap(w, 100, 60)
		find(find(w.screen, "b"), "Body").Activated.fire()
		t.expect(state.content.b).toBe(1)
		t.expect(state.open.b:peek()).toBeNil()
		t.expect(state.fired).toEqual({})
		w.engine.heartbeat.fire(0.3)
		t.expect(state.fired).toEqual({ "a" })
		for _ = 1, 30 do
			w.engine.heartbeat.fire(0.1)
		end
		t.expect(state.fired).toEqual({ "a" })
		t.expect(state.open.a:peek()).toBeNil()
		w.stop()
	end)

	t.it("closes a tray over a HUD on a HUD tap, activates the HUD control and engages nothing", function()
		local w, state = rowsWorld(nil, true)
		local gameplay = 0
		w.input.InputBegan:Connect(function()
			gameplay += 1
		end)
		state.open.a:set("trailing")
		t.expect(w.gui.SelectedObject).toBeNil()
		t.expect(sinking(w)).toEqual({})
		tap(w, 640, 540)
		find(w.screen, "Boost").Activated.fire()
		t.expect(state.hud).toBe(1)
		t.expect(gameplay).toBe(1)
		t.expect(state.open.a:peek()).toBeNil()
		t.expect(#state.fired).toBe(0)
		t.expect(w.gui.SelectedObject).toBeNil()
		t.expect(sinking(w)).toEqual({})
		tap(w, 640, 540)
		find(w.screen, "Boost").Activated.fire()
		t.expect(state.hud).toBe(2)
		t.expect(gameplay).toBe(2)
		t.expect(state.open.a:peek()).toBeNil()
		w.stop()
	end)
end)
