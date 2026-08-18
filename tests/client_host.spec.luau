--!strict
--[[ THE CLIENT HOST'S FRAME CONTRACT (reuse audit REUSE-109/115; `src/client/host.luau`).

	The defect this module exists to end is not visible in a dump: three of the
	four shipped bootstraps drove `presenter.refresh()` alone and never
	`presenter.tick(dt)`, so the motion clock never advanced — and a frozen clock
	and a settled one look identical in every static instrument. What tells them
	apart is TIME PASSING: schedule something with a dwell, run frames, and see
	whether it ever expires.

	So this file drives the host with a hand-cranked frame source and asserts the
	four things a hand-rolled bootstrap got wrong: that a frame ticks AND
	refreshes, in that order; that `presenter.onTick` is the sanctioned place for
	a consumer's per-frame work rather than a second connection; that exactly one
	frame source exists; and that `dispose` stops it and unbinds, idempotently and
	in the order that cannot fault mid-frame.

	HEADLESS BY CONSTRUCTION. `host.luau` requires nothing engine-only at module
	scope and resolves `screen_target` / `roblox_input` / `roblox_env` inside
	`new`, each behind its own seam — which is the only reason this contract can
	be tested at all.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local host = require("../src/client/host")
local actionsLib = require("../src/input/actions")
local fake_target = require("../tests/lib/fake_target")
local UI = require("../src/blueprint")

--[[ A hand-cranked frame source. `frames.step(dt)` is one PreRender edge; the
	counter is how the spec proves there is exactly ONE connection rather than
	the two or three the audit found across three different RunService signals. ]]
local function newFrames()
	local fns: { (dt: number) -> () } = {}
	local connects = 0
	local disconnects = 0
	return {
		connect = function(fn: (dt: number) -> ()): () -> ()
			connects += 1
			table.insert(fns, fn)
			return function()
				disconnects += 1
				local i = table.find(fns, fn)
				if i ~= nil then
					table.remove(fns, i)
				end
			end
		end,
		step = function(dt: number)
			for _, fn in table.clone(fns) do
				fn(dt)
			end
		end,
		connects = function()
			return connects
		end,
		disconnects = function()
			return disconnects
		end,
		live = function()
			return #fns
		end,
	}
end

local function newHost(extra: any?)
	local frames = newFrames()
	local adapter = fake_target.new()
	local unbinds = 0
	local o: any = {
		newAdapter = function()
			return adapter
		end,
		newInputSystem = function(core: any)
			return actionsLib.newSystem(core)
		end,
		bindEnv = function(env: any)
			env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
			return function()
				unbinds += 1
			end
		end,
		connectFrame = frames.connect,
	}
	for k, v in (extra or {}) :: any do
		o[k] = v
	end
	local h = host.new(o)
	return h, frames, adapter, function()
		return unbinds
	end
end

describe("client host: the six steps, in order, once", function()
	it("hands back a bound, presentable surface", function()
		local h = newHost()
		expect(h.core ~= nil).toBe(true)
		expect(h.env ~= nil).toBe(true)
		expect(h.adapter ~= nil).toBe(true)
		expect(h.inputSystem ~= nil).toBe(true)
		expect(h.presenter ~= nil).toBe(true)
		-- the environment was BOUND before the presenter was built: a viewport
		-- that arrives after the first solve is the 1x1-first-frame defect class
		expect(h.env:get("viewportRect"):get().w).toBe(390)
		h.dispose()
	end)

	it("connects exactly one frame source, and disposing takes it back", function()
		local h, frames = newHost()
		expect(frames.connects()).toBe(1)
		expect(frames.live()).toBe(1)
		h.dispose()
		expect(frames.disconnects()).toBe(1)
		expect(frames.live()).toBe(0)
	end)

	it("refuses an unknown opt by name, the way every other Facet boundary does", function()
		local ok, err = pcall(function()
			host.new({ displayOrdr = 5 } :: any)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "client.host.new") ~= nil).toBe(true)
		expect(string.find(tostring(err), "Did you mean 'displayOrder'%?") ~= nil).toBe(true)
	end)
end)

--[[ THE HALF THREE OF FOUR BOOTSTRAPS DROPPED. A `refresh`-only drive leaves the
	motion clock frozen, so nothing scheduled on it ever comes due. The instrument
	is the presenter's own tick hook, which fires from INSIDE `tick` and therefore
	cannot be reached by a refresh at all. ]]
describe("REUSE-109: the frame drives the clock, not just the solve", function()
	it("a frame advances the motion clock with the frame's own dt", function()
		local h, frames = newHost()
		local seen: { number } = {}
		h.presenter.onTick(function(dt: number)
			table.insert(seen, dt)
		end)
		frames.step(1 / 60)
		frames.step(1 / 30)
		expect(#seen).toBe(2)
		expect(seen[1]).toBe(1 / 60)
		expect(seen[2]).toBe(1 / 30) -- the FRAME's dt, not a wall-clock guess
		h.dispose()
	end)

	--[[ ORDER, AND WHY IT IS NOT A DETAIL. A tick hook is where a consumer's
		per-frame work goes (`presenter.onTick` calls itself "the one sanctioned
		frame source outside the motion clock"), and whatever it writes has to be
		SOLVED in the same frame it was written. Refreshing before ticking costs
		every hook exactly one frame of latency — the same defect as driving
		`refresh` alone, one frame smaller, and just as invisible in a dump. ]]
	it("ticks BEFORE it refreshes, so this frame's hook work is solved this frame", function()
		local h, frames, adapter = newHost()
		local rows = h.core:signal("first")
		h.presenter.present(UI.Screen({
			id = "S",
			children = { UI.Text({ id = "L", text = rows }) },
		}))
		h.presenter.refresh()
		adapter.takeOps()

		-- a hook that writes: the write must be visible in the SAME frame's solve
		local wrote = false
		h.presenter.onTick(function()
			if not wrote then
				wrote = true
				rows:set("second")
			end
		end)
		frames.step(1 / 60)
		expect(adapter.node("/S/L").props.text).toBe("second")
		h.dispose()
	end)

	it("a disposed host runs no further frames, even if the source fires again", function()
		local h, frames = newHost()
		local ticks = 0
		h.presenter.onTick(function()
			ticks += 1
		end)
		frames.step(1 / 60)
		expect(ticks).toBe(1)
		h.dispose()
		frames.step(1 / 60) -- a source that has not honoured the disconnect
		expect(ticks).toBe(1)
	end)
end)

describe("client host: teardown", function()
	it("dispose unbinds the environment and is idempotent", function()
		local h, frames, _adapter, unbinds = newHost()
		expect(unbinds()).toBe(0)
		h.dispose()
		expect(unbinds()).toBe(1)
		expect(frames.disconnects()).toBe(1)
		h.dispose()
		h.dispose()
		expect(unbinds()).toBe(1) -- ...and does not unbind twice
		expect(frames.disconnects()).toBe(1)
	end)

	--[[ CONSTRUCTION IS ALL-OR-NOTHING. A bootstrap that throws after binding the
		environment leaves a live binding nobody holds a handle to — the state whose
		teardown nobody writes, because there is nothing to write it on. ]]
	it("a construction that fails halfway leaves nothing bound", function()
		local unbound = 0
		local ok = pcall(function()
			host.new({
				bindEnv = function()
					return function()
						unbound += 1
					end
				end,
				newAdapter = function()
					error("the render target could not be built", 0)
				end,
			} :: any)
		end)
		expect(ok).toBe(false)
		expect(unbound).toBe(1)
	end)
end)
