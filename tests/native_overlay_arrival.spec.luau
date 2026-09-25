--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose

local function signal()
	local handlers = {}
	return {
		Connect = function(_, fn)
			table.insert(handlers, fn)
			return {
				Disconnect = function()
					local index = table.find(handlers, fn)
					if index then
						table.remove(handlers, index)
					end
				end,
			}
		end,
		fire = function()
			for _, fn in table.clone(handlers) do
				fn()
			end
		end,
		count = function()
			return #handlers
		end,
	}
end

local function world(build: (any) -> any)
	local engine = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local frames = { Heartbeat = signal() }
	local UI = Facet.controls(
		runtime,
		{
			types = engine.types,
			guiService = gui,
			reducedMotion = true,
			services = { GuiService = gui, RunService = frames },
		} :: any
	)
	local stop, screen = runtime.mount(function()
		return runtime.constructors.ScreenGui({ build(UI) })
	end, engine.new("Folder"))
	return screen, frames, function()
		stop()
		runtime:dispose()
	end
end

local function hidden(screen: any, name: string): boolean?
	local node = screen:FindFirstChild(name, true)
	if node == nil then
		return nil
	end
	local at = node
	while at and at ~= screen do
		if at:IsA("GuiObject") and not at.Visible then
			return true
		end
		at = at.Parent
	end
	return false
end

t.describe("presented surfaces arrive styled", function()
	t.it("holds a newly presented surface hidden until the next frame, when the theme styles apply", function()
		for _, kind in { "Sheet", "Alert" } do
			local open = Compose.cell(false)
			local screen, frames, stop = world(function(UI)
				if kind == "Sheet" then
					return UI.Sheet "Market" {
						title = "Seeds",
						isPresented = open,
						detent = Compose.cell("medium"),
						content = function()
							return UI.Text { text = "Wheat" }
						end,
					}
				end
				return UI.Alert "Confirm" {
					title = "Sell the crop?",
					isPresented = open,
					actions = { { id = "ok", label = "Sell" } },
				}
			end)
			local inner = if kind == "Sheet" then "SheetPanel" else "ok"
			open:set(true)
			t.expect(`{kind} hidden {hidden(screen, inner)}`).toBe(`{kind} hidden true`)
			frames.Heartbeat.fire()
			t.expect(`{kind} hidden {hidden(screen, inner)}`).toBe(`{kind} hidden false`)
			t.expect(frames.Heartbeat.count()).toBe(0)
			stop()
		end
	end)

	t.it("releases its frame hook when the surface closes before the first frame", function()
		local open = Compose.cell(false)
		local _, frames, stop = world(function(UI)
			return UI.Alert "Confirm" {
				title = "Sell the crop?",
				isPresented = open,
				actions = { { id = "ok", label = "Sell" } },
			}
		end)
		open:set(true)
		t.expect(frames.Heartbeat.count()).toBe(1)
		open:set(false)
		t.expect(frames.Heartbeat.count()).toBe(0)
		stop()
	end)
end)

return nil
