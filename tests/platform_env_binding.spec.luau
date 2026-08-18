--!strict
--[[
	THE PLATFORM ADAPTER, DRIVEN BY A FAKE ENGINE — release-candidate platform
	review PLAT-1/RR-6, PLAT-2 and PLAT-3.

	`src/client/roblox_env.luau` decides what the whole framework believes about
	the device: the viewport, the safe areas, the input class, the on-screen
	keyboard. It had no test of any kind, because its three services were
	module-scope `game:GetService` locals and the module could not even be
	REQUIRED off a client. Three defects lived there because of that:

	  · PLAT-1/RR-6 — the keyboard-occlusion connection was gated on
	    `UserInputService.OnScreenKeyboardVisible`, i.e. on whether the keyboard
	    was up AT BIND TIME, which it never is. The `and`/`or` short-circuited to
	    `nil`, `table.insert(t, nil)` appended nothing, and
	    `keyboardOcclusionRect` stayed nil for the session.
	  · PLAT-2 — `workspace.CurrentCamera` was captured once, so a replaced
	    camera orphaned the ViewportSize connection and `viewportRect` stopped
	    updating for the session.
	  · PLAT-3 — an inset measured against the previous orientation could be
	    published beside the new viewport (the pure half is proved directly in
	    the safe-area block below; the engine `Rect`/`Enum` path it rides has no
	    headless twin, which is exactly why the arithmetic moved out of the
	    adapter).

	The fakes below are deliberately thin: they answer the members the adapter
	actually reads and count connections, because "was the connection made" is
	the entire question for two of the three findings.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local environment = require("../src/env/environment")
local safe_insets = require("../src/env/safe_insets")
local roblox_env = require("../src/client/roblox_env")

-- ---------------------------------------------------------------------------
-- a change signal with a live-connection count, which is the instrument

local function newSignal(): any
	local records: { any } = {}
	local signal = {}
	function signal.Connect(_self, fn: (...any) -> ()): any
		local record = { fn = fn, connected = true }
		table.insert(records, record)
		return {
			Disconnect = function()
				record.connected = false
			end,
		}
	end
	function signal.fire(_self, ...)
		for _, record in records do
			if record.connected then
				record.fn(...)
			end
		end
	end
	function signal.liveCount(_self): number
		local n = 0
		for _, record in records do
			if record.connected then
				n += 1
			end
		end
		return n
	end
	return signal
end

local function newPropertyBag(): any
	local signals: { [string]: any } = {}
	return {
		signals = signals,
		signalFor = function(name: string): any
			if signals[name] == nil then
				signals[name] = newSignal()
			end
			return signals[name]
		end,
	}
end

local function newCamera(w: number, h: number): any
	local bag = newPropertyBag()
	local camera: any = {
		ViewportSize = { X = w, Y = h },
		GetPropertyChangedSignal = function(_self, name: string)
			return bag.signalFor(name)
		end,
		bag = bag,
	}
	return camera
end

local function newFakeServices(camera: any): any
	local guiBag = newPropertyBag()
	local inputBag = newPropertyBag()
	local worldBag = newPropertyBag()
	local gui: any = {
		ReducedMotionEnabled = false,
		PreferredTransparency = 1,
		TopbarInset = { Min = { X = 0, Y = 0 }, Width = 0, Height = 0 },
		GetGuiInset = function(_self)
			return { X = 0, Y = 0 }, { X = 0, Y = 0 }
		end,
		GetPropertyChangedSignal = function(_self, name: string)
			return guiBag.signalFor(name)
		end,
		bag = guiBag,
	}
	local input: any = {
		PreferredInput = { Name = "KeyboardAndMouse" },
		KeyboardEnabled = true,
		MouseEnabled = true,
		TouchEnabled = false,
		GamepadEnabled = false,
		OnScreenKeyboardVisible = false,
		OnScreenKeyboardPosition = { X = 0, Y = 700 },
		OnScreenKeyboardSize = { X = 400, Y = 300 },
		GamepadConnected = newSignal(),
		GamepadDisconnected = newSignal(),
		LastInputTypeChanged = newSignal(),
		GetPropertyChangedSignal = function(_self, name: string)
			return inputBag.signalFor(name)
		end,
		bag = inputBag,
	}
	local world: any = {
		CurrentCamera = camera,
		GetPropertyChangedSignal = function(_self, name: string)
			return worldBag.signalFor(name)
		end,
		bag = worldBag,
	}
	return {
		userInput = input,
		gui = gui,
		text = { GetTextSizeOffsetAsync = function() end },
		world = world,
	}
end

describe("the platform adapter binds the connections it claims to (PLAT-1/PLAT-2)", function()
	it("the on-screen-keyboard connection is made even though the keyboard is down at bind", function()
		local core = Facet.newCore()
		local env = environment.new(core)
		local camera = newCamera(390, 844)
		local services = newFakeServices(camera)
		local unbind = roblox_env.bind(env, services)

		local keyboardSignal = services.userInput.bag.signalFor("OnScreenKeyboardPosition")
		expect(keyboardSignal:liveCount()).toBe(1)

		-- ...and the rect actually arrives when the keyboard comes up
		expect(env:get("keyboardOcclusionRect"):get()).toBe(nil)
		services.userInput.OnScreenKeyboardVisible = true
		keyboardSignal:fire()
		local rect = env:get("keyboardOcclusionRect"):get()
		expect(rect).toBeTruthy()
		expect(rect.y).toBe(700)
		expect(rect.h).toBe(300)

		services.userInput.OnScreenKeyboardVisible = false
		keyboardSignal:fire()
		expect(env:get("keyboardOcclusionRect"):get()).toBe(nil)
		unbind()
	end)

	it("an engine without the member is cleanly skipped, with no nil hole", function()
		local core = Facet.newCore()
		local env = environment.new(core)
		local camera = newCamera(1280, 720)
		local services = newFakeServices(camera)
		services.userInput.OnScreenKeyboardVisible = nil
		local ok, unbind = pcall(roblox_env.bind, env, services)
		expect(ok).toBe(true)
		expect(services.userInput.bag.signalFor("OnScreenKeyboardPosition"):liveCount()).toBe(0)
		-- the unbind walk must not trip over a hole in `connections`
		expect(pcall(unbind :: any)).toBe(true)
	end)

	it("a replaced CurrentCamera re-binds ViewportSize and drops the old connection (PLAT-2)", function()
		local core = Facet.newCore()
		local env = environment.new(core)
		local first = newCamera(390, 844)
		local services = newFakeServices(first)
		local unbind = roblox_env.bind(env, services)
		expect(env:get("viewportRect"):get().w).toBe(390)

		local firstViewportSignal = first:GetPropertyChangedSignal("ViewportSize")
		expect(firstViewportSignal:liveCount()).toBe(1)

		-- the game swaps in a cutscene camera
		local second = newCamera(1280, 720)
		services.world.CurrentCamera = second
		services.world.bag.signalFor("CurrentCamera"):fire()

		-- the facts followed it...
		expect(env:get("viewportRect"):get().w).toBe(1280)
		-- ...the old connection is gone...
		expect(firstViewportSignal:liveCount()).toBe(0)
		-- ...and the NEW camera's resizes reach env
		second.ViewportSize = { X = 1600, Y = 900 }
		second:GetPropertyChangedSignal("ViewportSize"):fire()
		expect(env:get("viewportRect"):get().w).toBe(1600)

		unbind()
		expect(second:GetPropertyChangedSignal("ViewportSize"):liveCount()).toBe(0)
	end)
end)

describe("safe-area insets are refused when they cannot describe the viewport (PLAT-3)", function()
	--[[ The numbers are the shipped repro recorded at `src/env/environment.luau:354`:
		a topbar-safe area of y 0..58 measured on an 852-tall portrait window, read
		back after a rotation to a 393-tall landscape one. ]]
	local PORTRAIT = { w = 393, h = 852 }
	local LANDSCAPE = { w = 852, h = 393 }
	local AREA = { minX = 0, minY = 0, maxX = 393, maxY = 58 }
	local NO_GUI_INSET = { x = 0, y = 0 }

	it("the conversion is unchanged for an inset measured on the viewport it is published with", function()
		local insets = safe_insets.fromArea(AREA, NO_GUI_INSET, PORTRAIT)
		expect(insets.top).toBe(0)
		expect(insets.left).toBe(0)
		expect(insets.right).toBe(0)
		expect(insets.bottom).toBe(794)
		expect(safe_insets.describesViewport(insets, PORTRAIT)).toBe(true)
	end)

	it("the same inset read against the rotated viewport is refused", function()
		local stale = safe_insets.fromArea(AREA, NO_GUI_INSET, PORTRAIT)
		-- top 0 + bottom 794 is twice the 393-tall landscape window: this inset
		-- cannot have come from it
		expect(safe_insets.describesViewport(stale, LANDSCAPE)).toBe(false)
	end)

	it("a horizontal notch inset that eats the whole width is refused too", function()
		local wide = { top = 0, bottom = 0, left = 500, right = 500 }
		expect(safe_insets.describesViewport(wide, LANDSCAPE)).toBe(false)
		expect(safe_insets.describesViewport({ top = 0, bottom = 0, left = 44, right = 44 }, LANDSCAPE)).toBe(true)
	end)

	it("the legacy gui inset is added back before edges are derived", function()
		-- desktop: the CoreUI area reads (0,0)->(w, h-58) while the window is h tall
		local desktop = { w = 1280, h = 720 }
		local area = { minX = 0, minY = 0, maxX = 1280, maxY = 662 }
		local insets = safe_insets.fromArea(area, { x = 0, y = 58 }, desktop)
		expect(insets.top).toBe(58)
		expect(insets.bottom).toBe(0)
	end)
end)
