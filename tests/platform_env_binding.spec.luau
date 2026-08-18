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

describe("safe-area insets are refused while the platform has not caught up (PLAT-3)", function()
	--[[ ── THE SHAPE THE ADAPTER ACTUALLY PRODUCES ──────────────────────────────

		The first version of this belt (and of this spec) tested a DERIVED INSET
		against a viewport it was not derived under — `environment.luau`'s shape,
		not the adapter's. The adapter recomputes fresh every pass, so the belt
		cancelled down to "does the area have positive extent" and refused nothing:
		48 cases over the real call shape, zero refusals, worst accepted inset
		reserving 96% of an axis.

		So these cases deliver what `roblox_env.bind` really delivers: the NEW
		`viewportRect` arrives first (the camera's `ViewportSize` moved), and the
		matching `GetInsetArea` rect arrives a pass or more LATER. Between those
		two moments the platform disagrees with itself, and the belt's whole job is
		to publish nothing until it agrees. The engine's two types (`Rect`,
		`Enum.ScreenInsets`) are unpacked in `engineServices` now, so this branch is
		reachable headlessly at all — previously no test executed it in situ. ]]
	local PORTRAIT = { w = 393, h = 852 }
	local LANDSCAPE = { w = 852, h = 393 }
	-- the shipped repro's numbers (`src/env/environment.luau:354`): a topbar-safe
	-- area of y 0..58 measured on an 852-tall portrait window
	local PORTRAIT_AREA = { minX = 0, minY = 0, maxX = 393, maxY = 794 }
	local LANDSCAPE_AREA = { minX = 0, minY = 0, maxX = 852, maxY = 335 }
	local NO_GUI_INSET = { x = 0, y = 0 }

	local function rotatingWorld()
		local core = Facet.newCore()
		local env = environment.new(core)
		local camera = newCamera(PORTRAIT.w, PORTRAIT.h)
		local services = newFakeServices(camera)
		-- the platform's CURRENT answer, which the fake lags on purpose
		local live = { core = PORTRAIT_AREA, device = PORTRAIT_AREA, topbar = PORTRAIT_AREA }
		services.insetAreas = function()
			return { core = live.core, device = live.device, topbar = live.topbar }
		end
		local unbind = roblox_env.bind(env, services)
		return {
			env = env,
			camera = camera,
			services = services,
			live = live,
			unbind = unbind,
			rotate = function(view: any)
				camera.ViewportSize = { X = view.w, Y = view.h }
				camera:GetPropertyChangedSignal("ViewportSize"):fire()
			end,
			catchUp = function(area: any)
				live.core, live.device, live.topbar = area, area, area
				-- the platform re-reports through any of its own signals; TopbarInset
				-- is the one that fires on a rotation
				services.gui.bag.signalFor("TopbarInset"):fire()
			end,
			insets = function(key: string): any
				return env:get(key):get()
			end,
		}
	end

	it("a stale area arriving AFTER the new viewportRect is refused, and the last good value stands", function()
		local w = rotatingWorld()
		-- settled portrait: the area agrees with the viewport, so it publishes
		expect(w.insets("coreSafeInsets").bottom).toBe(58)
		expect(w.env:get("viewportRect"):get().h).toBe(852)

		-- THE ROTATION. The camera moves first; `GetInsetArea` still answers the
		-- portrait rect, which on the landscape window derives right = 852 - 393 =
		-- 459 — 54% of the axis, from a rect that never described this window.
		w.rotate(LANDSCAPE)
		expect(w.env:get("viewportRect"):get().w).toBe(852)
		expect(w.insets("coreSafeInsets").right).toBe(0)
		expect(w.insets("coreSafeInsets").bottom).toBe(58)
		expect(w.insets("deviceSafeInsets").right).toBe(0)

		-- ...AND IT SETTLES. The platform catches up and the real landscape inset
		-- publishes on the next push.
		w.catchUp(LANDSCAPE_AREA)
		expect(w.insets("coreSafeInsets").bottom).toBe(58)
		expect(w.insets("coreSafeInsets").right).toBe(0)
		expect(w.env:get("viewportRect"):get().w).toBe(852)
		w.unbind()
	end)

	it("...and the same refusal holds when the stale area still FITS the new window", function()
		--[[ THE CASE THE FIT GUARD CANNOT SEE, which is what makes the cross-pass
			test load-bearing rather than decorative. A window that gets SHORTER by a
			little — a URL bar collapsing, a split-view divider moving — leaves the
			previous area comfortably inside it, so "does this area fit" answers yes
			while the area is still describing the taller window. Only "has the area
			moved with the viewport" can tell. ]]
		local w = rotatingWorld()
		expect(w.insets("coreSafeInsets").bottom).toBe(58)
		local SHORTER = { w = 393, h = 800 }
		w.rotate(SHORTER)
		expect(w.env:get("viewportRect"):get().h).toBe(800)
		-- the stale area would have derived bottom = 800 - 794 = 6, a plausible-
		-- looking number that is simply wrong; the last good 58 stands instead
		expect(w.insets("coreSafeInsets").bottom).toBe(58)

		-- ...and it settles the moment the platform reports the shorter window
		w.catchUp({ minX = 0, minY = 0, maxX = 393, maxY = 742 })
		expect(w.insets("coreSafeInsets").bottom).toBe(58)
		expect(w.insets("coreSafeInsets").top).toBe(0)
		w.unbind()
	end)

	it("the belt refuses ONLY the disagreement: an area that moves with the viewport publishes", function()
		local w = rotatingWorld()
		-- both facts move in the same pass, which is the healthy platform
		w.live.core, w.live.device, w.live.topbar = LANDSCAPE_AREA, LANDSCAPE_AREA, LANDSCAPE_AREA
		w.rotate(LANDSCAPE)
		expect(w.env:get("viewportRect"):get().w).toBe(852)
		expect(w.insets("coreSafeInsets").bottom).toBe(58)
		expect(w.insets("coreSafeInsets").right).toBe(0)
		w.unbind()
	end)

	it("the belt is a REFUSAL, not a rewrite: a held pass changes no other fact", function()
		local w = rotatingWorld()
		local topbarBefore = w.insets("topbarSafeInsets")
		w.rotate(LANDSCAPE)
		-- the viewport is the fact that DID move, and it moves regardless
		expect(w.env:get("viewportRect"):get().h).toBe(393)
		-- ...while every inset key keeps the value it had
		expect(w.insets("topbarSafeInsets").bottom).toBe(topbarBefore.bottom)
		expect(w.insets("topbarSafeInsets").right).toBe(topbarBefore.right)
		w.unbind()
	end)

	--[[ THE PURE HALF, at the numbers the shipped repro recorded. These are the
		cases the OLD belt claimed and could not deliver — each one is now a real
		refusal rather than a `describesViewport` that cancels to true. ]]
	it("an area that cannot FIT the viewport it is published beside is refused on the FIRST pass", function()
		-- the cross-pass test has nothing to compare on a first push, so the fit
		-- guard is what stands there
		expect(safe_insets.areaFitsViewport(PORTRAIT_AREA, NO_GUI_INSET, PORTRAIT)).toBe(true)
		-- 852 tall does not fit a 393-tall window
		expect(safe_insets.areaFitsViewport(PORTRAIT_AREA, NO_GUI_INSET, LANDSCAPE)).toBe(false)
		-- degenerate and negative areas are not areas
		expect(safe_insets.areaFitsViewport({ minX = 0, minY = 0, maxX = 0, maxY = 100 }, NO_GUI_INSET, PORTRAIT)).toBe(
			false
		)
		expect(safe_insets.areaFitsViewport({ minX = -4, minY = 0, maxX = 393, maxY = 100 }, NO_GUI_INSET, PORTRAIT)).toBe(
			false
		)
	end)

	it("the belt holds an unmoved area beside a moved viewport, and releases when it moves", function()
		local belt = safe_insets.newBelt()
		expect(belt:judge("core", PORTRAIT_AREA, NO_GUI_INSET, PORTRAIT)).toBe(true)
		-- same area, same viewport: an ordinary re-push, nothing is being hidden
		expect(belt:judge("core", PORTRAIT_AREA, NO_GUI_INSET, PORTRAIT)).toBe(true)
		-- the viewport moved and the area did not: the area still describes the
		-- window it was measured on
		local narrower = { w = 393, h = 800 }
		expect(belt:judge("core", PORTRAIT_AREA, NO_GUI_INSET, narrower)).toBe(false)
		expect(belt:held().core).toBe(1)
		-- ...and the moment it catches up, it publishes
		local caught = { minX = 0, minY = 0, maxX = 393, maxY = 742 }
		expect(belt:judge("core", caught, NO_GUI_INSET, narrower)).toBe(true)
		expect(belt:held().core).toBe(1)
	end)

	it("the three areas lag INDEPENDENTLY, so one holding never gags the others", function()
		local belt = safe_insets.newBelt()
		belt:judge("core", PORTRAIT_AREA, NO_GUI_INSET, PORTRAIT)
		belt:judge("device", PORTRAIT_AREA, NO_GUI_INSET, PORTRAIT)
		local narrower = { w = 393, h = 800 }
		local caught = { minX = 0, minY = 0, maxX = 393, maxY = 742 }
		expect(belt:judge("core", PORTRAIT_AREA, NO_GUI_INSET, narrower)).toBe(false)
		expect(belt:judge("device", caught, NO_GUI_INSET, narrower)).toBe(true)
		expect(belt:held().core).toBe(1)
		expect(belt:held().device).toBe(nil)
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
