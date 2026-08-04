--!strict
-- Step 8.5 large-text-accessibility: the PreferredTextSize offset seam
-- (src/client/preferred_text) — measured-fallback-first, confirm-once,
-- stale-safe, failure-safe, never-loop (LT-1/LT-3/LT-4) — plus the live-change
-- reflow contract at the renderer (LT-2): an offset change re-solves the
-- mounted tree without remounting it.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local preferred_text = require("../src/client/preferred_text")
local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local fake_target = require("../tests/lib/fake_target")

-- inline scheduler + a controllable async lookup MODELLED ON THE LIVE SHAPE
-- (platform review F4): the engine API has no preference parameter, so the
-- harness answers for whatever preference is LIVE when the test releases the
-- lookup — exactly what GetTextSizeOffsetAsync does. `answers` maps preference
-- name -> that preference's true engine offset; the controller's requested
-- name is recorded but never consulted for the value.
local function harness(answers: { [string]: number? })
	local applied: { number } = {}
	local pending: { { requested: string, release: () -> () } } = {}
	local lookups = 0
	local livePreference: string? = nil
	local controller = preferred_text.new({
		getOffset = function(_requested: string): number?
			lookups += 1
			local co = coroutine.running()
			table.insert(pending, {
				requested = _requested,
				release = function()
					coroutine.resume(co)
				end,
			})
			coroutine.yield()
			-- the LIVE preference decides the answer, never the requested name
			local answer = answers[livePreference :: string]
			if answer == nil then
				error("no answer for live preference " .. tostring(livePreference))
			end
			return answer
		end,
		apply = function(offset: number)
			table.insert(applied, offset)
		end,
		spawn = function(f)
			-- run on a coroutine the test can hold open at the yield
			local co = coroutine.create(f)
			coroutine.resume(co)
		end,
	})
	local function setPreference(name: string)
		livePreference = name
		controller:setPreference(name)
	end
	local function release(requested: string)
		for i, entry in pending do
			if entry.requested == requested then
				table.remove(pending, i)
				entry.release()
				return
			end
		end
	end
	return controller, applied, release, function()
		return lookups
	end, setPreference
end

describe("preferred_text offset seam (LT-1/LT-3/LT-4)", function()
	it("applies the measured fallback synchronously — first mount never waits", function()
		local controller, applied, _, _, setPreference = harness({ Largest = 14 })
		setPreference("Largest")
		expect(#applied).toBe(1)
		expect(applied[1]).toBe(14)
		local now = controller:current()
		expect(now.offset).toBe(14)
		expect(now.source).toBe("fallback")
	end)

	it("a confirmed answer equal to the fallback applies nothing more (no second reflow)", function()
		local controller, applied, release, _, setPreference = harness({ Large = 4 })
		setPreference("Large")
		expect(#applied).toBe(1)
		expect(applied[1]).toBe(4)
		release("Large")
		expect(#applied).toBe(1) -- 4 == 4: no correction write
		expect(controller:current().source).toBe("measured")
	end)

	it("a confirmed answer that differs applies exactly one atomic correction", function()
		local controller, applied, release, _, setPreference = harness({ Large = 6 })
		setPreference("Large")
		expect(applied[1]).toBe(4) -- measured fallback
		release("Large")
		expect(#applied).toBe(2)
		expect(applied[2]).toBe(6) -- the engine's (hypothetically changed) truth wins
	end)

	it(
		"an answer that raced a preference step is DISCARDED — the A->B->A double-step cannot poison the cache",
		function()
			-- THE PLATFORM REVIEW F1 REPRO. The live lookup answers for the CURRENT
			-- preference: an answer resolving after another step may describe either
			-- value, so caching it under the requested name would poison that name
			-- for the session (Largest permanently under-reserved by Medium's 0).
			local controller, applied, release, lookups, setPreference = harness({ Largest = 14, Medium = 0 })
			setPreference("Largest") -- lookup A spawned (fallback 14 applied)
			setPreference("Medium") -- lookup B spawned; A is now STALE
			release("Largest") -- A resolves — with MEDIUM's engine answer (0)
			expect(controller:current().offset).toBe(0) -- Medium's own fallback stands
			local lookupsBefore = lookups()
			setPreference("Largest")
			-- the stale answer was NOT cached: Largest asks the engine AGAIN...
			expect(lookups()).toBe(lookupsBefore + 1)
			-- ...and the immediate application is the measured fallback, not 0
			expect(controller:current().offset).toBe(14)
			release("Largest") -- resolves with Largest live -> true 14
			expect(controller:current().offset).toBe(14)
			expect(controller:current().source).toBe("measured")
		end
	)

	it("an answer resolved with NO step in flight is cached: the revisit asks nothing", function()
		local controller, applied, release, lookups, setPreference = harness({ Large = 6, Medium = 0 })
		setPreference("Large")
		release("Large") -- stable across the yield -> cached 6, applied 6
		expect(applied[#applied]).toBe(6)
		setPreference("Medium")
		release("Medium")
		local lookupsBefore = lookups()
		setPreference("Large")
		expect(lookups()).toBe(lookupsBefore) -- cache hit, no re-ask
		expect(applied[#applied]).toBe(6)
		expect(controller:current().source).toBe("measured")
	end)

	it("a FAILED lookup keeps the fallback and does not retry in a loop", function()
		local applied: { number } = {}
		local calls = 0
		local controller = preferred_text.new({
			getOffset = function(): number?
				calls += 1
				error("engine unavailable")
			end,
			apply = function(offset)
				table.insert(applied, offset)
			end,
			spawn = function(f)
				coroutine.resume(coroutine.create(f))
			end,
		})
		controller:setPreference("Larger")
		expect(#applied).toBe(1)
		expect(applied[1]).toBe(10) -- measured fallback stands
		expect(calls).toBe(1) -- one attempt, no loop
		-- the retry budget is per-VISIT, not a timer:
		controller:setPreference("Larger")
		expect(calls).toBe(2)
		expect(#applied).toBe(2) -- re-applied the same fallback (idempotent value)
	end)

	it("garbage answers are refused: NaN and negative offsets keep the fallback", function()
		for _, garbage in { 0 / 0, -3 } do
			local controller, applied, release, _, setPreference = harness({ Largest = garbage :: any })
			setPreference("Largest")
			release("Largest")
			expect(#applied).toBe(1)
			expect(applied[1]).toBe(14)
		end
	end)

	it("an answer past the ceiling is CLAMPED and applied, never traded for a smaller fallback", function()
		-- platform review F2: if the platform raises its constants past the
		-- sanity ceiling, discarding the truthful bigger answer would
		-- under-reserve — the bounded clamp is the safe direction
		local controller, applied, release, _, setPreference = harness({ Largest = 1e9 :: any })
		setPreference("Largest")
		release("Largest")
		expect(#applied).toBe(2)
		expect(applied[2]).toBe(32) -- MAX_OFFSET, not the 14 fallback
		expect(controller:current().source).toBe("measured")
	end)

	it("an unknown future enum value starts from the LARGEST known fallback (over-reserve, never clip)", function()
		local controller, applied, release, _, setPreference = harness({ Colossal = 20 })
		setPreference("Colossal")
		expect(applied[1]).toBe(14)
		expect(controller:current().source).toBe("fallback-unknown")
		release("Colossal")
		expect(applied[2]).toBe(20) -- corrected to the engine's answer
	end)

	it("dispose drops late answers on the floor", function()
		local controller, applied, release, _, setPreference = harness({ Large = 6 })
		setPreference("Large")
		controller:dispose()
		release("Large")
		expect(#applied).toBe(1)
	end)
end)

describe("live preference change reflows without remount (LT-2)", function()
	local function makeSlice()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
		local bp = UI.Screen({
			id = "LargeText",
			children = {
				UI.Text({ id = "Body", text = "The quick brown fox jumps over the lazy dog", textSize = 16 }),
				UI.Button({ id = "Go", label = "Go" }),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, {})
		controller.initialRender()
		adapter.takeOps()
		return core, env, root, adapter, controller
	end

	it("raising the offset re-solves in place: same node, taller text box, no creates/removes", function()
		local _core, env, _root, adapter, controller = makeSlice()
		local heightBefore = adapter.node("/LargeText/Body").rect.h
		local liveBefore = adapter.liveCount()
		env:set("preferredTextOffset", 14)
		local ops = adapter.takeOps()
		expect(#ops > 0).toBe(true)
		for _, op in ops do
			local kind = string.sub(op, 1, 4)
			-- a preference change is GEOMETRY: rects and derived hit rects only —
			-- creates or removes here would mean the tree remounted
			if kind ~= "rect" and kind ~= "hitr" then
				error(`unexpected op on a preference reflow: {op}`)
			end
		end
		expect(adapter.node("/LargeText/Body").rect.h > heightBefore).toBe(true)
		expect(adapter.liveCount()).toBe(liveBefore)
		controller.dispose()
	end)

	it("lowering it back restores the original geometry exactly (no residue)", function()
		local _core, env, _root, adapter, controller = makeSlice()
		local h0 = adapter.node("/LargeText/Body").rect.h
		env:set("preferredTextOffset", 14)
		env:set("preferredTextOffset", 0)
		expect(adapter.node("/LargeText/Body").rect.h).toBe(h0)
		controller.dispose()
	end)
end)
