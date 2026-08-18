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

--[[ ONE CLOCK, ONE DRIVER (R5 review §3b-3). Two frame sources on one presenter
	advance its motion clock twice per frame, so every duration on it elapses at
	double speed — measured by the review over the real host: 30 hook fires and a
	1 s timer reading 0.5000 with the host alone, 60 fires and 0.0000 with the
	host plus `motion_driver.bind`, and no error raised either way.

	`motion_driver` has asserted this since it shipped, but against a table
	private to itself, so it could only ever see its own binds. The claim now
	lives on the PRESENTER — the one object both drivers hold — which is also the
	first time the rule has been testable without an engine.

	THERE IS ONLY ONE ORDER TO TEST, and that is worth writing down rather than
	writing a second case that proves nothing: `host.new` BUILDS its presenter,
	so no driver can have claimed it first. The reachable collision is always
	host-then-driver, which is the case below. ]]
describe("REUSE-115 / §3b-3: a presenter takes exactly one frame driver", function()
	it("the host claims it, and a second driver is refused by name", function()
		local h = newHost()
		expect(h.presenter.frameDriver()).toBe("client.host")
		local ok, err = pcall(function()
			h.presenter.claimFrameDriver("motion_driver.bind")
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "already driven by 'client.host'", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "ONE CLOCK, ONE DRIVER", 1, true) ~= nil).toBe(true)
		h.dispose()
	end)

	it("disposing the host releases the claim, so the surface can be stood back up", function()
		local h = newHost()
		expect(h.presenter.frameDriver()).toBe("client.host")
		h.dispose()
		expect(h.presenter.frameDriver()).toBeNil()
		-- ...and the presenter now accepts a driver again
		local release = h.presenter.claimFrameDriver("motion_driver.bind")
		expect(h.presenter.frameDriver()).toBe("motion_driver.bind")
		release()
		expect(h.presenter.frameDriver()).toBeNil()
	end)

	--[[ THE ENGINE HALF, pinned as source because `motion_driver` reaches
		`game:GetService` at module scope and cannot be required headlessly. What
		matters is that it takes the claim at all — the behaviour of the claim
		itself is proved above, engine-free. ]]
	it("motion_driver.bind takes the same claim", function()
		local fs = require("@lune/fs")
		local driver = fs.readFile("src/client/motion_driver.luau")
		expect(string.find(driver, 'presenter.claimFrameDriver("motion_driver.bind")', 1, true) ~= nil).toBe(true)
		-- ...and gives it back on unbind, or a re-bind after teardown is refused
		expect(string.find(driver, "releaseClaim()", 1, true) ~= nil).toBe(true)
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

	--[[ WHAT THE HOST BUILT, COUNTED — ON BOTH PATHS (R5 review §3b-2).

		The first version of this spec only ever failed at `newAdapter`, which is
		the ONE position where the undo stack is provably complete: nothing had
		been built yet but the env binding. The review found what that hid — the
		adapter, the input system and the presenter were never pushed onto `undo`
		at all, so a throw from `newInputSystem` (reachable: `roblox_input` asserts
		after a 5 s PlayerScripts wait) abandoned a fully constructed render target
		whose pointer seam had already opened an adapter-wide connection, and a
		SUCCESSFUL `dispose()` leaked the same two objects.

		So both paths are counted here, and the failure is injected LATE — after
		the adapter and the input system exist — which is the position that could
		not previously fail. ]]
	local function countingHost(extra: any?)
		local counts = { adapter = 0, input = 0, unbind = 0, disconnect = 0 }
		local o: any = {
			newAdapter = function()
				local a = fake_target.new()
				a.dispose = function()
					counts.adapter += 1
				end
				return a
			end,
			newInputSystem = function(core: any)
				local sys = actionsLib.newSystem(core)
				local inner = sys.dispose
				sys.dispose = function()
					counts.input += 1
					inner()
				end
				return sys
			end,
			bindEnv = function(env: any)
				env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
				return function()
					counts.unbind += 1
				end
			end,
			connectFrame = function()
				return function()
					counts.disconnect += 1
				end
			end,
		}
		for k, v in (extra or {}) :: any do
			o[k] = v
		end
		return o, counts
	end

	it("dispose releases the adapter and the input system, not only the frame and the binding", function()
		local o, counts = countingHost()
		local h = host.new(o)
		h.dispose()
		expect(`adapter {counts.adapter} input {counts.input} unbind {counts.unbind} frame {counts.disconnect}`).toBe(
			"adapter 1 input 1 unbind 1 frame 1"
		)
		h.dispose() -- ...and still exactly once
		expect(`adapter {counts.adapter} input {counts.input}`).toBe("adapter 1 input 1")
	end)

	it("a throw AFTER the adapter and input system exist unwinds both of them", function()
		local o, counts = countingHost({
			connectFrame = function()
				error("the frame source could not be connected", 0)
			end,
		})
		local ok = pcall(function()
			host.new(o)
		end)
		expect(ok).toBe(false)
		--[[ THE POSITION THAT COULD NOT FAIL BEFORE. Everything constructed before
			the throw is released, in reverse order, and nothing that was never
			constructed is touched. ]]
		expect(`adapter {counts.adapter} input {counts.input} unbind {counts.unbind}`).toBe(
			"adapter 1 input 1 unbind 1"
		)
	end)

	it("a caller-supplied piece with no dispose is left alone rather than errored on", function()
		--[[ The seams take ANY object shaped like an adapter or a system; a
			consumer handing in one it owns (a billboard target, a long-lived input
			system shared across surfaces) must not have the host call a method it
			does not have, and must not have its object disposed underneath it. ]]
		local h = host.new({
			newAdapter = function()
				return fake_target.new() -- no `dispose`
			end,
			newInputSystem = function(core: any)
				return { deviceKey = function() end, createContext = function() end } -- no `dispose`
			end,
			bindEnv = function()
				return function() end
			end,
			connectFrame = function()
				return function() end
			end,
		})
		h.dispose()
		h.dispose()
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
