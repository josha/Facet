--!strict
--[[
	FOCUSING A MONITOR IS NOT A ONE-SHOT.

	A live report: in Spatial mode, focusing a monitor and then pressing
	"All monitors" to return to the overview left every LATER focus attempt
	dead — another monitor, or the same one, would not come forward. The first
	focus after launch worked; nothing after the first return did.

	This file pins the whole cycle against the showcase's real screens, driven
	through the real Activate dispatch: focus A -> overview -> focus B ->
	overview -> focus A. Three monitors, three applications, ONE shared `focused`
	cell — the showcase's own shape (`examples/virtual_monitors/main.client.luau`)
	— because a single-surface case cannot see a monitor that refuses to wake
	while a different one is the one that was last awake.

	WHAT IT PROVES, AND WHAT IT DOES NOT. `UI.activationGate` re-reads its
	`closed` binding on every press (`presenter.readGateClosed` peeks rather than
	subscribes), so a gate that has opened once closes again the moment the cell
	says so. That is the half a regression here would break, and it is what these
	cases hold. They do NOT claim anything about the engine-side half of the live
	report — the camera rig and SurfaceGui hit routing have no headless stand-in.
]]

local t = require("./lib/testkit")
local Facet = require("../src") :: any
local Compose = Facet.Compose

local nativeWorld = require("./lib/native_world")
local screens = require("../examples/virtual_monitors/screens")
local catalogModule = require("../examples/virtual_monitors/catalog")

local NAMES = { "Discover", "Chat", "Avatar" }

-- the showcase's own focus model, lifted out of main.client.luau
local function newRoom()
	local focused = Compose.cell("Overview")
	local gateOpens = 0
	local function actions()
		return {
			catalog = catalogModule.new(Compose),
			needsFocus = function(name: string)
				return function(use: any)
					return use(focused) ~= name
				end
			end,
			focusLabel = function(name: string)
				return function(use: any)
					return if use(focused) == name then "All monitors" else "Focus"
				end
			end,
			focus = function(name: string)
				gateOpens += 1
				focused:set(if focused:peek() == name then "Overview" else name)
			end,
		}
	end
	local monitors: { [string]: any } = {}
	for _, name in NAMES do
		local app, adapter, settle = nativeWorld({ x = 0, y = 0, w = 1920, h = 1080 })
		local apps = screens.create(Facet, app, actions())
		app.mount(function()
			return app.controls.Screen(name .. "Monitor")({ apps[name]() })
		end)
		settle(3)
		monitors[name] = {
			app = app,
			adapter = adapter,
			settle = settle,
			suffixed = function(suffix: string): string?
				for _, path in adapter.paths() do
					if path:sub(-#suffix) == suffix then
						return path
					end
				end
				return nil
			end,
		}
	end
	local function tick()
		for _, monitor in monitors do
			monitor.settle(2)
		end
	end
	local function press(name: string, suffix: string)
		local monitor = monitors[name]
		monitor.adapter.driveActivate(assert(monitor.suffixed(suffix), `{name}{suffix}`))
		tick()
	end
	return {
		focused = focused,
		monitors = monitors,
		press = press,
		tick = tick,
		opens = function(): number
			return gateOpens
		end,
		label = function(name: string): any
			local monitor = monitors[name]
			return monitor.adapter.node(assert(monitor.suffixed("/Focus"))).props.label
		end,
		dispose = function()
			for _, monitor in monitors do
				monitor.app.dispose()
			end
		end,
	}
end

t.describe("a monitor can be focused again after returning to the overview", function()
	t.it("cycles A -> overview -> B -> overview -> A through real activation", function()
		local room = newRoom()
		t.expect(room.focused:peek()).toBe("Overview")

		room.press("Discover", "/Focus")
		t.expect(room.focused:peek()).toBe("Discover")
		room.press("Discover", "/Focus")
		t.expect(room.focused:peek()).toBe("Overview")

		-- THE REPORTED FAILURE: the SECOND monitor never came forward
		room.press("Chat", "/Focus")
		t.expect(room.focused:peek()).toBe("Chat")
		room.press("Chat", "/Focus")
		t.expect(room.focused:peek()).toBe("Overview")

		-- ...and so did the FIRST one, asked a second time
		room.press("Discover", "/Focus")
		t.expect(room.focused:peek()).toBe("Discover")
		room.dispose()
	end)

	t.it("the gate closes again behind a monitor that has already woken once", function()
		--[[ `UI.activationGate` re-reads `closed` per press rather than latching,
			which is the whole reason the cycle above can repeat. A gate that
			remembered having opened would pass the first half of this case and fail
			the second. ]]
		local room = newRoom()
		room.press("Avatar", "/Focus")
		t.expect(room.opens()).toBe(1)
		room.press("Avatar", "/Focus")
		t.expect(room.opens()).toBe(2)
		room.press("Avatar", "/Focus")
		t.expect(room.opens()).toBe(3)
		t.expect(room.focused:peek()).toBe("Avatar")
		room.dispose()
	end)

	t.it("a press on a SLEEPING monitor is spent waking it, and reaches nothing under it", function()
		local room = newRoom()
		local before =
			room.monitors.Discover.adapter.node(assert(room.monitors.Discover.suffixed("/Genre-Racing"))).props.selected
		room.press("Discover", "/Genre-Racing")
		t.expect(room.focused:peek()).toBe("Discover")
		local after =
			room.monitors.Discover.adapter.node(assert(room.monitors.Discover.suffixed("/Genre-Racing"))).props.selected
		t.expect(after).toBe(before)
		-- awake, the same press now reaches the chip
		room.press("Discover", "/Genre-Racing")
		t.expect(
			room.monitors.Discover.adapter.node(assert(room.monitors.Discover.suffixed("/Genre-Racing"))).props.selected
				~= before
		).toBe(true)
		room.dispose()
	end)

	t.it("every monitor's Focus button says which way it will go, at every step", function()
		local room = newRoom()
		for _, name in NAMES do
			t.expect(room.label(name)).toBe("Focus")
		end
		room.press("Chat", "/Focus")
		t.expect(room.label("Chat")).toBe("All monitors")
		t.expect(room.label("Discover")).toBe("Focus")
		room.press("Chat", "/Focus")
		for _, name in NAMES do
			t.expect(room.label(name)).toBe("Focus")
		end
		room.dispose()
	end)
end)
