--!strict
local harness = require("./lib/harness")
--[[
	DISPOSING A SURFACE DISPOSES THE CORE IT STOOD UP.

	`src/client/host.luau`'s teardown comment used to state, as a contract, that
	it released "the frame connection, the input system, the render target and
	the environment binding" and NOT the core. An audit priced what that costs:
	after `app.dispose()` the root Compose owner was still live, so

	  · `core.owner.watch` still fired on the next write;
	  · a `core.owner.createChild()` cleanup never ran;
	  · settle callbacks registered on the pass still swept;

	and everything the presenter hangs off that owner — the focus observers,
	`with_animation`, the drag registry, the responder effects — outlived the
	surface. A disposed application that still reacts is not a leak you can see
	in a dump; it is a leak shaped exactly like a live surface.

	THE RULE IS OWNERSHIP, NOT REACH. The host disposes the core when the host
	BUILT it. A caller that supplied one through the `newCore` seam keeps it —
	that core may carry several surfaces, and ending it is the caller's call.
	Both halves are asserted here, because a fix that disposed unconditionally
	would break the second and nothing else was watching it.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local Compose = require("../src/vendor/compose/core")
local hostLib = require("../src/client/host")
local services = require("../src/core/services")
local fake_target = require("./lib/fake_target")

local VIEWPORT = { x = 0, y = 0, w = 800, h = 600 }

-- The native world's seams (tests/lib/native_world.luau), opened one level down
-- so the spec holds the Host — and therefore the core — that `app.dispose()`
-- tears down through `surface.dispose()`.
local function newSurface(over: { [string]: any }?)
	local opts: any = {
		newAdapter = function()
			return fake_target.new()
		end,
		newInputSystem = function(core: any)
			return Facet.newActionSystem(core)
		end,
		bindEnv = function(env: any)
			env:set("viewportRect", VIEWPORT)
			return function() end
		end,
		connectFrame = function()
			return function() end
		end,
	}
	for key, value in over or {} do
		opts[key] = value
	end
	return hostLib.new(opts)
end

-- Three probes, one per thing the audit found still alive.
local function probes(core: any)
	local source = Compose.cell(0)
	local watched, cleaned, swept = 0, 0, 0
	core.owner.watch(function(use)
		use(source)
		watched += 1
	end)
	local child = core.owner.createChild()
	child.own(function()
		cleaned += 1
	end)
	core.settlePass.register(function()
		swept += 1
	end, "lifetime-probe")
	return {
		poke = function()
			source:set(source:peek() + 1)
			pcall(function()
				core.reactor:settle()
			end)
		end,
		watched = function(): number
			return watched
		end,
		cleaned = function(): number
			return cleaned
		end,
		swept = function(): number
			return swept
		end,
	}
end

describe("a host disposes the core it built", function()
	it("stops the root owner's watches", function()
		local surface = newSurface()
		local probe = probes(surface.core)
		probe.poke()
		local before = probe.watched()
		expect(before > 0).toBe(true)
		surface.dispose()
		probe.poke()
		expect(probe.watched()).toBe(before)
	end)

	it("runs a `createChild()` cleanup hung off the root owner", function()
		local surface = newSurface()
		local probe = probes(surface.core)
		expect(probe.cleaned()).toBe(0)
		surface.dispose()
		expect(probe.cleaned()).toBe(1)
	end)

	it("stops registered settle work", function()
		local surface = newSurface()
		local probe = probes(surface.core)
		probe.poke()
		local before = probe.swept()
		expect(before > 0).toBe(true)
		surface.dispose()
		probe.poke()
		expect(probe.swept()).toBe(before)
	end)

	it("is safe to dispose twice", function()
		local surface = newSurface()
		local probe = probes(surface.core)
		surface.dispose()
		surface.dispose()
		expect(probe.cleaned()).toBe(1)
		probe.poke()
		expect(probe.swept()).toBe(0)
	end)

	it("a settle callback registered AFTER dispose never runs", function()
		local surface = newSurface()
		local core = surface.core
		surface.dispose()
		local ran = 0
		core.settlePass.register(function()
			ran += 1
		end, "after-dispose")
		pcall(function()
			core.reactor:settle()
		end)
		core.settlePass.run()
		expect(ran).toBe(0)
	end)
end)

describe("a host never disposes a core it was handed", function()
	it("leaves a `newCore` core's owner, and its settle pass, running", function()
		local supplied = services.new({
			warn = function() end,
		})
		local surface = newSurface({
			newCore = function()
				return supplied
			end,
		})
		expect(surface.core).toBe(supplied)
		local probe = probes(supplied)
		probe.poke()
		local watched, swept = probe.watched(), probe.swept()
		surface.dispose()
		expect(probe.cleaned()).toBe(0)
		probe.poke()
		expect(probe.watched() > watched).toBe(true)
		expect(probe.swept() > swept).toBe(true)
		supplied.owner.dispose()
	end)
end)

describe("the application's dispose reaches the same teardown", function()
	it("a disposed Facet.new application leaves nothing on its root owner", function()
		local captured: any = nil
		local app = Facet.new({
			newAdapter = function()
				return fake_target.new()
			end,
			newInputSystem = function(core: any)
				captured = core
				return Facet.newActionSystem(core)
			end,
			bindEnv = function(env: any)
				env:set("viewportRect", VIEWPORT)
				return function() end
			end,
			connectFrame = function()
				return function() end
			end,
		})
		--[[ `newInputSystem` is handed the core the host BUILT (it is a seam for
			the input system, not for the core), so this is the host's own core and
			the ownership rule above applies to it. ]]
		expect(captured ~= nil).toBe(true)
		local probe = probes(captured)
		probe.poke()
		local watched = probe.watched()
		expect(watched > 0).toBe(true)
		app.dispose()
		probe.poke()
		expect(probe.watched()).toBe(watched)
		expect(probe.cleaned()).toBe(1)
	end)
end)

--[[ A THROWING CLEANUP MUST NOT STRAND THE HOST. A component's `Compose.cleanup`
	is application code. `app.dispose()` marks the application disposed FIRST, so
	a throw that stopped the teardown left the frame callback and the environment
	binding connected with no second call able to finish the job. ]]
describe("app.dispose releases the host even when a component cleanup throws", function()
	it("disconnects the frame callback and the environment binding, then raises", function()
		local fake = require("./lib/fake_target")
		local frameOff, envOff = 0, 0
		local app = Facet.new({
			newAdapter = function()
				return fake.new()
			end,
			newInputSystem = function(core: any)
				return Facet.newActionSystem(core)
			end,
			bindEnv = function(env: any)
				env:set("viewportRect", { x = 0, y = 0, w = 640, h = 480 })
				return function()
					envOff += 1
				end
			end,
			connectFrame = function()
				return function()
					frameOff += 1
				end
			end,
		})
		local UI = app.controls
		app.mount(function()
			Facet.Compose.cleanup(function()
				error("boom from a component cleanup", 0)
			end)
			return UI.Screen("S")({ UI.Text("T")({ text = "hi" }) })
		end)
		local ok, err = pcall(app.dispose)
		-- the failure is still reported to the caller...
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "boom from a component cleanup", 1, true) ~= nil).toBe(true)
		-- ...and the host is released exactly once
		expect(frameOff).toBe(1)
		expect(envOff).toBe(1)
		-- a second dispose is a no-op, not a second release
		app.dispose()
		expect(frameOff).toBe(1)
	end)

	it("closes every other surface and runs every other cleanup around the one that throws", function()
		local fake = require("./lib/fake_target")
		local adapter = fake.new()
		local frameOff, cleaned = 0, {}
		local app = Facet.new({
			newAdapter = function()
				return adapter
			end,
			newInputSystem = function(core: any)
				return Facet.newActionSystem(core)
			end,
			bindEnv = function(env: any)
				env:set("viewportRect", { x = 0, y = 0, w = 640, h = 480 })
				return function() end
			end,
			connectFrame = function()
				return function()
					frameOff += 1
				end
			end,
		})
		local UI = app.controls
		local function surface(name: string, throws: boolean)
			return function()
				Facet.Compose.cleanup(function()
					cleaned[name] = true
					if throws then
						error(`boom from {name}`, 0)
					end
				end)
				return UI.Screen(name)({ UI.Text("T")({ text = name }) })
			end
		end
		app.mount(surface("First", false))
		app.mount(surface("Broken", true))
		app.presentModal(surface("Sheet", false))
		expect(adapter.liveCount() > 0).toBe(true)
		local ok, err = pcall(app.dispose)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "boom from Broken", 1, true) ~= nil).toBe(true)
		-- every surface was torn down, in spite of the one in the middle
		expect(cleaned.First).toBe(true)
		expect(cleaned.Broken).toBe(true)
		expect(cleaned.Sheet).toBe(true)
		expect(adapter.liveCount()).toBe(0)
		expect(frameOff).toBe(1)
	end)
end)

local _ = harness

describe("application shutdown finishes animated and auxiliary surfaces", function()
	for _, reduced in { false, true } do
		it("releases pending exits and toast rows immediately with reduced motion " .. tostring(reduced), function()
			local w = require("./lib/world").new({ reducedMotion = reduced })
			local UI = w.UI
			local cleaned, frames = {}, 0
			w.app.onFrame(function()
				frames += 1
			end)
			local function panel(name)
				return function()
					Compose.cleanup(function()
						cleaned[name] = (cleaned[name] or 0) + 1
					end)
					local text = Compose.formula(function()
						return name
					end)
					return UI.ZStack(name)({ canvasGroup = true, UI.Text({ text = text }) })
				end
			end
			w.present(panel("Base"))
			local close = w.app.presentModal(panel("Leaving"), { transition = { enter = "fade", exit = "fade" } })
			w.settle(12)
			close()
			w.app.presentModal(panel("StillOpen"), { transition = { enter = "fade", exit = "fade" } })
			for i = 1, 5 do
				w.app.presentToast(panel("Toast" .. i), { duration = 10 })
			end
			expect(w.adapter.liveCount() > 0).toBe(true)
			expect(w.pres.toastCounts().queued > 0).toBe(true)
			w.app.dispose()
			expect(w.adapter.liveCount()).toBe(0)
			expect(w.pres.toastCounts().visible).toBe(0)
			expect(w.pres.toastCounts().queued).toBe(0)
			for _, name in { "Base", "Leaving", "StillOpen", "Toast1", "Toast2", "Toast3" } do
				expect(cleaned[name]).toBe(1)
			end
			-- Queued components were never mounted.
			expect(cleaned.Toast4).toBeNil()
			expect(cleaned.Toast5).toBeNil()
			local before = frames
			w.app.dispose()
			w.pres.tick(1)
			expect(frames).toBe(before)
			Facet.themes.declareApp("shutdown_probe", { tileMin = 96 })
			Facet.themes.declareApp("shutdown_probe", nil)
			expect(w.core.lastError()).toBeNil()
		end)
	end
	it("clears waiting callouts and chrome without mounting the next queued component", function()
		local w = require("./lib/world").new()
		local UI, shown = w.UI, Compose.cell(false)
		local mounted, cleaned = 0, 0
		w.present(function()
			local tips = {}
			for i = 1, 3 do
				table.insert(
					tips,
					UI.Callout("Tip" .. i)({
						anchor = UI.Button("Anchor" .. i)({ label = "Add", onActivate = function() end }),
						isPresented = shown,
						onRetire = function() end,
						content = function()
							mounted += 1
							Compose.cleanup(function()
								cleaned += 1
							end)
							return UI.Text({ text = "Add an item" })
						end,
					})
				)
			end
			return UI.Screen("S")(tips)
		end)
		shown:set(true)
		w.settle(12)
		w.app.presentAnchored(function()
			return UI.Text({ text = "Help" })
		end, { id = "Chrome", chrome = true, anchor = { source = { rect = { x = 20, y = 20, w = 44, h = 44 } } } })
		expect(mounted).toBe(1)
		expect(w.pres.callouts().queued).toBe(2)
		w.app.dispose()
		expect(mounted).toBe(1)
		expect(cleaned).toBe(1)
		expect(w.adapter.liveCount()).toBe(0)
		expect(w.pres.callouts().queued).toBe(0)
	end)
	it("releases a provider even if its transport's unbind fails", function()
		local w = require("./lib/world").new()
		local provider = w.app.newResourceProvider({
			bind = function()
				return function()
					error("unbind failed", 0)
				end
			end,
		})
		local ok, err = pcall(w.app.dispose)
		expect(ok).toBe(false)
		expect(tostring(err)).toBe("unbind failed")
		local owner = Compose.createOwner()
		local handle = provider.acquire(owner, "after-dispose")
		expect(handle.state:peek()).toBe("failed")
		expect(handle.error:peek()).toBe("resource provider disposed")
		owner.dispose()
	end)
end)
