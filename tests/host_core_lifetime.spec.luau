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

local _ = harness
