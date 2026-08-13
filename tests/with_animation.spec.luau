--!strict
-- `presenter.withAnimation(class, fn)` — SwiftUI-parity round 2, Phase 1
-- (docs/plans/swiftui-parity-round2.md §Phase 1). State changes applied inside
-- `fn` animate their visual consequences.
--
-- THE ONE INVARIANT EVERY CASE HERE DEFENDS: the solver stays exact and instant.
-- A node's `rect` after the call is the NEW solved rect, on the very frame the
-- call returns; only its PAINTED position travels. That is why almost every
-- assertion below reads `node.rect` and `node.presentedPosition` in the same
-- breath — a design that animated geometry would pass a naive "it moved
-- smoothly" test and fail every one of these.
--
-- The design went through two adversarial review rounds before any of this was
-- written; the cases that look oddly specific are the defects those rounds
-- found. Named at each one:
--
--   * the UNARMED PRE-DRAIN (review R2 #1) — an unrelated discrete change that
--     fired before the call must NOT animate at its full delta;
--   * LIVENESS IS NOT `lastRects ~= nil` (R2 #2) — a new row adopting a parked
--     instance carries the dead occupant's rect and would fly in from its grave;
--   * ROOTS ONLY, RELATIVE (R1 blocker 3) — both the renderer and the adapter
--     already accumulate ancestor offsets, so a per-node absolute delta paints a
--     sliding panel's children at double the distance;
--   * "CHANGED IN THIS DIFF", not "nearest recorded ancestor" (R2 #7) — a live
--     record from an earlier call must not be read as this diff's baseline;
--   * the COMPENSATING RECORD (R2 #8) — a child that did NOT move while its
--     parent did must be held still, or the accumulation drags it along;
--   * REDUCED MOTION INSTALLS NOTHING (R1 #10) — not "installs and immediately
--     clears", which paints a stale delta forever if the settle ordering slips;
--   * NESTED-TRANSACTION REFUSAL (R2 #3) — inside an outer transaction nothing
--     has flushed, so the animation would silently not happen.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local fake_target = require("./lib/fake_target")

local FRAME = 1 / 60

-- Settle a spring by stepping far past its response. `container` is 0.35 s, so
-- 120 frames is ~2 s of clock — comfortably settled, and the assertion is on the
-- terminal value, never on a frame count.
local function settle(pres: any)
	for _ = 1, 120 do
		pres.tick(FRAME)
	end
end

-- The world every case shares: a Screen holding a header whose height is bound
-- to a signal, and a body below it. Flipping the signal moves the body — one
-- clean, whole-pixel rect change with nothing else in the frame.
local function world(opts: any?)
	local options = opts or {}
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	if options.reducedMotion then
		-- `motionPolicy` is DERIVED from this fact (env/environment.luau:166-167);
		-- setting the derived key is refused, which is the right refusal
		env:set("reducedMotion", true)
	end
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)

	local tall = core:signal(false)
	local headerHeight = core:memo(function(use: any)
		return { type = "fixed", px = if use(tall) then 200 else 100 }
	end)
	local UI = LuauUI.UI
	local screen = UI.Screen({
		id = "S",
		padding = 0,
		gap = 0,
		children = {
			UI.Box({ id = "Header", height = headerHeight }),
			-- a VStack, not a Box: `UI.Box` is a leaf and refuses children
			UI.VStack({
				id = "Body",
				padding = 0,
				gap = 0,
				height = { type = "fixed", px = 100 },
				children = { UI.Text({ id = "Line", text = "row" }) },
			}),
		},
	})
	local handle = pres.present(screen)
	pres.refresh()
	return {
		core = core,
		env = env,
		adapter = adapter,
		pres = pres,
		tall = tall,
		handle = handle,
	}
end

describe("withAnimation: the solver stays exact and instant", function()
	it("the solved rect is the NEW one on the frame the call returns", function()
		local w = world()
		local before = w.adapter.node("/S/Body").rect.y
		w.pres.withAnimation("container", function()
			w.tall:set(true)
		end)
		local node = w.adapter.node("/S/Body")
		-- geometry: already at its destination, exactly, with no interpolation
		expect(node.rect.y).toBe(before + 100)
	end)

	it("the PAINTED position starts at the old place and travels to the new one", function()
		local w = world()
		local before = w.adapter.node("/S/Body").rect.y
		w.pres.withAnimation("container", function()
			w.tall:set(true)
		end)
		-- seeded synchronously inside the commit (transitions.luau:321's rule):
		-- the node must never paint one frame at its destination and jump back
		expect(w.adapter.node("/S/Body").presentedPosition.y).toBe(before)
		w.pres.tick(FRAME)
		local mid = w.adapter.node("/S/Body").presentedPosition.y
		expect(mid > before).toBe(true)
		expect(mid < before + 100).toBe(true)
		settle(w.pres)
		local node = w.adapter.node("/S/Body")
		expect(node.presentedPosition.y).toBe(node.rect.y)
	end)

	it("records are dropped at settle, so the channel is clean afterwards", function()
		local w = world()
		w.pres.withAnimation("container", function()
			w.tall:set(true)
		end)
		settle(w.pres)
		expect(w.pres.animationRecordCount()).toBe(0)
	end)
end)

describe("withAnimation: records are relative, and only at animation roots", function()
	it("a child riding its moved parent installs NO record of its own", function()
		local w = world()
		w.pres.withAnimation("container", function()
			w.tall:set(true)
		end)
		-- /S/Body moved; /S/Body/Line moved by exactly the same delta because it
		-- rode its parent. One record, not two — the adapter and the renderer
		-- both accumulate ancestor offsets, so a second record would double it.
		expect(w.pres.animationRecordCount()).toBe(1)
	end)

	it("the riding child is painted at ONE delta, never two", function()
		local w = world()
		local lineBefore = w.adapter.node("/S/Body/Line").rect.y
		w.pres.withAnimation("container", function()
			w.tall:set(true)
		end)
		-- painted where it used to be: +100 solved, -100 presentation, not -200
		expect(w.adapter.node("/S/Body/Line").presentedPosition.y).toBe(lineBefore)
	end)
end)

describe("withAnimation: what must NOT animate", function()
	it("a discrete change made BEFORE the call does not animate (the unarmed pre-drain)", function()
		local w = world()
		-- an unrelated change lands and is left undrained, exactly as a network
		-- event or a Heartbeat script's set would be. NOTE: a `set` alone commits
		-- nothing to the adapter — the rect still reads its OLD value here, which
		-- is why the assertions below read the node AFTER the call and compare it
		-- against itself. An earlier draft captured `rect.y` on this line and
		-- compared the painted position to it; that reads the pre-commit value and
		-- is unsatisfiable against any correct implementation.
		w.tall:set(true)
		-- ...and now an unrelated animated call runs. Without the pre-drain the
		-- armed commit would drain the earlier change too and animate it at its
		-- FULL delta, not a fraction of one.
		w.pres.withAnimation("container", function() end)
		local node = w.adapter.node("/S/Body")
		-- painted exactly where it was solved: it landed, it did not fly.
		-- Verified to BITE: with the pre-drain removed, this line reads the old
		-- position and the record count is 1, so both assertions go red.
		expect(node.presentedPosition.y).toBe(node.rect.y)
		expect(w.pres.animationRecordCount()).toBe(0)
	end)

	it("an ordinary refresh outside a call installs nothing", function()
		local w = world()
		w.tall:set(true)
		w.pres.refresh()
		expect(w.pres.animationRecordCount()).toBe(0)
		local node = w.adapter.node("/S/Body")
		expect(node.presentedPosition.y).toBe(node.rect.y)
	end)
end)

describe("withAnimation: reduced motion installs nothing at all", function()
	it("the layout is exact and there is no flight", function()
		local w = world({ reducedMotion = true })
		local before = w.adapter.node("/S/Body").rect.y
		w.pres.withAnimation("container", function()
			w.tall:set(true)
		end)
		local node = w.adapter.node("/S/Body")
		expect(node.rect.y).toBe(before + 100)
		-- not "installed and immediately cleared" — installed at all is the bug,
		-- because a settle-ordering slip then paints a stale delta forever
		expect(w.pres.animationRecordCount()).toBe(0)
		expect(node.presentedPosition.y).toBe(node.rect.y)
	end)
end)

describe("withAnimation: refusals", function()
	it("an unknown motion class is refused with the registered list", function()
		local w = world()
		local ok, err = pcall(function()
			w.pres.withAnimation("continer", function() end)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "container", 1, true) ~= nil).toBe(true)
	end)

	it("an inline params table is refused — motion classes are NAMES", function()
		local w = world()
		local ok = pcall(function()
			w.pres.withAnimation({ dampingRatio = 1, response = 0.3 } :: any, function() end)
		end)
		expect(ok).toBe(false)
	end)

	it("a call inside an already-open transaction is refused, not silently inert", function()
		local w = world()
		local ok, err = pcall(function()
			w.core:transaction(function()
				w.pres.withAnimation("container", function()
					w.tall:set(true)
				end)
			end)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "transaction", 1, true) ~= nil).toBe(true)
		-- ...and it names the OTHER thing that produces the same silence, plus the
		-- hazard, because the probe cannot tell the two apart (red-team R2)
		expect(string.find(tostring(err), "commit", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "do not retry", 1, true) ~= nil).toBe(true)
	end)

	it("a throwing body re-raises AND leaves nothing armed", function()
		local w = world()
		local ok = pcall(function()
			w.pres.withAnimation("container", function()
				error("boom", 0)
			end)
		end)
		expect(ok).toBe(false)
		-- the frame stack unwound: a later plain refresh must not animate
		w.tall:set(true)
		w.pres.refresh()
		expect(w.pres.animationRecordCount()).toBe(0)
	end)
end)

--[[ RED-TEAM R1 (2026-08-13) — A NESTED CALL USED TO KILL THE OUTER ANIMATION.

	The inner call armed and disarmed the same presenter-wide controllers the outer
	call had armed, and it did so BEFORE raising its own refusal — so by the time
	the outer call reached its armed `self.refresh()` there was no session left.

	MEASURED BEFORE THE FIX, on exactly the world below: the inner call raised (so
	an author watching stderr saw *something*), but the OUTER call's `/S/Body`
	landed at `rect.y = 200` painted at `presentedPosition.y = 200` — no flight at
	all, where the flight must start at 100 — and `animationRecordCount()` was 0.
	Under the `pcall` shape below, not even the inner raise was visible.

	The refusal now runs first, before anything is armed, refreshed or mutated. ]]
describe("withAnimation: nesting refuses the INNER call and leaves the outer flight intact", function()
	it("the inner call is refused by its own cause, not the transaction one", function()
		local w = world()
		local innerOk: boolean, innerErr: any = true, nil
		w.pres.withAnimation("container", function()
			w.tall:set(true)
			innerOk, innerErr = pcall(function()
				w.pres.withAnimation("object", function() end)
			end)
		end)
		expect(innerOk).toBe(false)
		-- named for what it IS: there is no outer core transaction here, and the
		-- old message sent the reader hunting for one
		expect(string.find(tostring(innerErr), "inside another withAnimation call", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(innerErr), "Nothing has been mutated by this call", 1, true) ~= nil).toBe(true)
	end)

	it("the OUTER animation still flies — the exact regression, measured", function()
		local w = world()
		local before = w.adapter.node("/S/Body").rect.y
		w.pres.withAnimation("container", function()
			w.tall:set(true)
			pcall(function()
				w.pres.withAnimation("object", function() end)
			end)
		end)
		local node = w.adapter.node("/S/Body")
		-- the layout landed exactly, as it did before the fix (this half never broke)
		expect(node.rect.y).toBe(before + 100)
		-- ...and THIS is the half the inner call used to delete: the paint starts
		-- where the body used to be, and a record is live to carry it there.
		-- Before the fix both of these read the settled value / 0.
		expect(node.presentedPosition.y).toBe(before)
		expect(w.pres.animationRecordCount()).toBe(1)
		settle(w.pres)
		expect(w.adapter.node("/S/Body").presentedPosition.y).toBe(w.adapter.node("/S/Body").rect.y)
	end)

	it("the refusal does not latch: the next call animates normally", function()
		local w = world()
		pcall(function()
			w.pres.withAnimation("container", function()
				w.pres.withAnimation("container", function() end)
			end)
		end)
		-- the outer raised too (the inner's error propagates out of `fn`), which
		-- must not leave `inWithAnimation` stuck on for the rest of the session
		local before = w.adapter.node("/S/Body").rect.y
		w.pres.withAnimation("container", function()
			w.tall:set(true)
		end)
		expect(w.adapter.node("/S/Body").rect.y).toBe(before + 100)
		expect(w.pres.animationRecordCount()).toBe(1)
	end)
end)

--[[ RED-TEAM R2 (2026-08-13) — A CALL MADE DURING A CORE COMMIT.

	`src/core/imperative.luau`'s `commit` opens `if committing then return end`, so
	a `core:transaction` opened from anything the commit itself dispatches — an
	observer, an effect, a settle chain — never flushes. The nesting probe sees the
	same silence an outer transaction produces and cannot separate them, so the
	refusal used to assert a transaction that was not open.

	It still refuses (the animation genuinely did not happen, and silence is the
	worst outcome), but the message now names BOTH causes and states the hazard the
	late raise creates: `fn` already ran inside the transaction, so its mutation has
	landed, and a caller that catches the raise must not retry it. ]]
describe("withAnimation: called during a core commit", function()
	local function raiseFromObserver(w: any): string
		local trigger = w.core:signal(0)
		local captured: string? = nil
		local unsubscribe = w.core:observe(trigger, function()
			-- the `pcall(action.onAction)` shape from src/controls/row_actions.luau:
			-- this is where the raise becomes invisible to the player
			local ok, err = pcall(function()
				w.pres.withAnimation("container", function()
					w.tall:set(true)
				end)
			end)
			if not ok then
				captured = tostring(err)
			end
		end)
		-- a plain set outside any transaction commits synchronously, and observers
		-- fire from INSIDE that commit (imperative.luau's `fireObservers`) — which
		-- is the whole point: `committing` is true while this handler runs
		trigger:set(1)
		unsubscribe()
		return captured or "<no raise>"
	end

	it("the message names the commit as well as the transaction, and warns about the retry", function()
		local w = world()
		local message = raiseFromObserver(w)
		expect(string.find(message, "core commit", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "outer core transaction", 1, true) ~= nil).toBe(true)
		-- THE DOUBLE-MUTATION HAZARD, stated: `fn` ran before the check
		expect(string.find(message, "already been applied", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "do not retry", 1, true) ~= nil).toBe(true)
	end)

	it("`fn`'s mutation HAS landed when it raises — which is why the warning is there", function()
		local w = world()
		raiseFromObserver(w)
		-- the signal `fn` set is set, and the layout settles to it on the next
		-- ordinary refresh. A caller that "retried" would toggle it back.
		expect(w.tall:get()).toBe(true)
		w.pres.refresh()
		expect(w.adapter.node("/S/Body").rect.y).toBe(200)
	end)
end)

describe("withAnimation: a path that did not exist before", function()
	-- THE RECYCLING TRAP (review R2 #2). `restoreParkedProps` writes
	-- `lastRects[path]` for a NEW path adopting a parked instance, so an
	-- implementation that reads liveness as `lastRects[path] ~= nil` sees a
	-- "previous rect" belonging to whatever node that instance used to be — and
	-- flies the new row in from a dead row's position. Liveness must come from a
	-- baseline snapshot of live paths instead. Instance recycling is on by
	-- default, so this is the shipped configuration, not a contrived one.
	local function appearWorld()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local shown = core:signal(false)
		local UI = LuauUI.UI
		pres.present(UI.Screen({
			id = "S",
			padding = 0,
			gap = 0,
			children = {
				UI.When({
					id = "Gate",
					condition = shown,
					thenView = function()
						return UI.Box({ id = "Late", height = { type = "fixed", px = 60 } })
					end,
				}),
				UI.Box({ id = "Tail", height = { type = "fixed", px = 40 } }),
			},
		}))
		pres.refresh()
		return { core = core, adapter = adapter, pres = pres, shown = shown }
	end

	it("a node that APPEARS inside the call installs no record of its own", function()
		local w = appearWorld()
		w.pres.withAnimation("container", function()
			w.shown:set(true)
		end)
		-- the appearing node is a structural change and belongs to the transition
		-- system, not to withAnimation; only the sibling it pushed down may fly
		local recs = w.pres.animationRecordCount()
		expect(recs <= 1).toBe(true)
		local late = w.adapter.node("/S/Gate/then/Late")
		expect(late ~= nil).toBe(true)
		expect(late.presentedPosition.y).toBe(late.rect.y)
	end)

	it("the sibling it displaced DOES fly, so the case is not vacuous", function()
		local w = appearWorld()
		local tailBefore = w.adapter.node("/S/Tail").rect.y
		w.pres.withAnimation("container", function()
			w.shown:set(true)
		end)
		local tail = w.adapter.node("/S/Tail")
		expect(tail.rect.y > tailBefore).toBe(true)
		expect(tail.presentedPosition.y).toBe(tailBefore)
	end)
end)

describe("withAnimation: interruption carries velocity", function()
	it("a second call mid-flight re-targets instead of restarting from rest", function()
		local w = world()
		w.pres.withAnimation("container", function()
			w.tall:set(true)
		end)
		-- part-way through the first flight, aim somewhere else
		for _ = 1, 6 do
			w.pres.tick(FRAME)
		end
		local midFlight = w.adapter.node("/S/Body").presentedPosition.y
		w.pres.withAnimation("container", function()
			w.tall:set(false)
		end)
		-- a RESTART would snap the paint back to the new old-place in one step;
		-- a re-target continues from where the pixel actually was
		local afterClaim = w.adapter.node("/S/Body").presentedPosition.y
		expect(math.abs(afterClaim - midFlight) < 1).toBe(true)
		settle(w.pres)
		local node = w.adapter.node("/S/Body")
		expect(node.presentedPosition.y).toBe(node.rect.y)
		expect(w.pres.animationRecordCount()).toBe(0)
	end)
end)

describe("withAnimation: two calls in one frame", function()
	it("two sequential calls are two COMMITS, not one", function()
		local w = world()
		local commits = w.pres.commitCount()
		w.pres.withAnimation("container", function()
			w.tall:set(true)
		end)
		w.pres.withAnimation("object", function()
			w.tall:set(false)
		end)
		-- asserted on commit count, not on animation-set count: an earlier
		-- revision of this design claimed two sets while producing one commit,
		-- and a set-count assertion would not have caught it
		expect(w.pres.commitCount() - commits >= 2).toBe(true)
	end)
end)
