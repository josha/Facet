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
		-- rode its parent. The adapter and the renderer both accumulate ancestor
		-- offsets, so a record on the Line would double its travel — and THAT, not
		-- the total, is what this case is about. It is asserted per path, because a
		-- count is satisfied by the wrong two records as easily as the right two.
		expect(w.adapter.node("/S/Body/Line").props.transform).toBe(nil)
		-- The total is 2, and both are named: the Body's POSITION (it was pushed
		-- down) and the Header's SIZE (its height is what changed). Before size was
		-- animated this read 1 — the Header's growth was a silent snap.
		expect(w.adapter.node("/S/Body").props.transform.y).toBe(-100)
		expect(w.adapter.node("/S/Header").props.transform.h).toBe(-100)
		expect(w.pres.animationRecordCount()).toBe(2)
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
		-- 2 = the Body's position record + the Header's size record (it read 1
		-- before size was animated); the point of the line is "non-zero, and the
		-- outer call's own record is one of them", so the Body's is named too
		expect(node.props.transform.y).toBe(-100)
		expect(w.pres.animationRecordCount()).toBe(2)
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
		-- the Body's position + the Header's size; 0 is what a latched refusal gives
		expect(w.pres.animationRecordCount()).toBe(2)
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

--[[ SIZE — the round-2 deferral, closed (docs/plans/with-animation-size.md).
	Round 2 shipped position only and recorded five mechanisms as the reason.
	Four of them describe what animating a size MEANS (content relayouts inside
	a box that is changing size — which is what SwiftUI does too); the fifth,
	"an interpolated size re-fits icon art and re-scales Path2D points every
	frame of the flight", was already false when it was written: the shipped
	POSITION animation calls `applyRect` on every handle in the animated subtree
	every frame (src/client/screen_target.luau's `transform` branch), and
	`applyRect` already runs `refitIconArt` and `applyPathPoints`. Size adds no
	call; it changes two numbers inside calls that were already happening.

	THE ONE STRUCTURAL DIFFERENCE FROM POSITION, and most of these cases are
	about it: a position delta ACCUMULATES down the subtree (the instance tree is
	flat, so a container's move does not carry the nodes inside it — every
	descendant must add its ancestors' offsets), and a size delta does NOT. A
	child's rect is absolute; growing its parent's painted box moves nothing.
	So the size half of a record is the node's OWN absolute delta, with no `inh`
	and no compensating record, and a child of a resizing node stays exactly its
	own size. ]]
local function sizeWorld(opts: any?)
	local options = opts or {}
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	if options.reducedMotion then
		env:set("reducedMotion", true)
	end
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)

	local tall = core:signal(false)
	local panelHeight = core:memo(function(use: any)
		return { type = "fixed", px = if use(tall) then 200 else 100 }
	end)
	local UI = LuauUI.UI
	-- Panel is FIRST, so its own position never changes: the only thing that can
	-- animate about it is its SIZE. Tail sits under it and moves by exactly the
	-- same 100 px the Panel grew, which is what makes the "one spring" assertion
	-- below an exact equality rather than a correlation.
	pres.present(UI.Screen({
		id = "S",
		padding = 0,
		gap = 0,
		children = {
			UI.VStack({
				id = "Panel",
				padding = 0,
				gap = 0,
				height = panelHeight,
				children = { UI.Text({ id = "Label", text = "row" }) },
			}),
			UI.Box({ id = "Tail", height = { type = "fixed", px = 40 } }),
		},
	}))
	pres.refresh()
	return { core = core, env = env, adapter = adapter, pres = pres, tall = tall }
end

describe("withAnimation: the painted SIZE travels, and the solved size is still exact", function()
	it("the solved size is the NEW one on the frame the call returns", function()
		local w = sizeWorld()
		expect(w.adapter.node("/S/Panel").rect.h).toBe(100)
		w.pres.withAnimation("container", function()
			w.tall:set(true)
		end)
		-- the same invariant every position case defends: geometry is at its
		-- destination, exactly, on the frame the call returns
		expect(w.adapter.node("/S/Panel").rect.h).toBe(200)
	end)

	it("the PAINTED size starts at the old one and travels to the new one", function()
		local w = sizeWorld()
		w.pres.withAnimation("container", function()
			w.tall:set(true)
		end)
		-- seeded synchronously inside the commit, exactly as the offset is: a size
		-- record written a frame late paints one frame at the destination and jumps
		expect(w.adapter.node("/S/Panel").presentedSize.h).toBe(100)
		w.pres.tick(FRAME)
		local mid = w.adapter.node("/S/Panel").presentedSize.h
		expect(mid > 100).toBe(true)
		expect(mid < 200).toBe(true)
		settle(w.pres)
		local node = w.adapter.node("/S/Panel")
		expect(node.presentedSize.h).toBe(node.rect.h)
	end)

	it("a SIZE-ONLY change is claimed — the node never moved, and it still animates", function()
		local w = sizeWorld()
		w.pres.withAnimation("container", function()
			w.tall:set(true)
		end)
		local panel = w.adapter.node("/S/Panel")
		-- it did not move, and the old `claimed` predicate (relX ~= 0 or relY ~= 0)
		-- is exactly what made this case a silent snap
		expect(panel.presentedPosition.y).toBe(panel.rect.y)
		expect(panel.presentedSize.h).toBe(100)
	end)

	it("ONE spring drives both halves: the growth and the displacement are the same number", function()
		local w = sizeWorld()
		w.pres.withAnimation("container", function()
			w.tall:set(true)
		end)
		-- Panel painted height = 200 - 100p; Tail painted y = 200 - 100p. Same p,
		-- so they are equal on EVERY frame — a subtree that tears reddens here
		-- rather than in a screenshot nobody takes.
		for _ = 1, 8 do
			local panel = w.adapter.node("/S/Panel")
			local tail = w.adapter.node("/S/Tail")
			expect(panel.presentedSize.h).toBe(tail.presentedPosition.y)
			w.pres.tick(FRAME)
		end
	end)

	it("SIZE DOES NOT ACCUMULATE: the child of a growing node keeps its own size", function()
		local w = sizeWorld()
		local label = w.adapter.node("/S/Panel/Label")
		local before = label.rect.h
		w.pres.withAnimation("container", function()
			w.tall:set(true)
		end)
		local live = w.adapter.node("/S/Panel/Label")
		-- the position half of a record accumulates down the subtree; the size half
		-- must not, or every descendant of a growing panel would inflate with it
		expect(live.presentedSize.h).toBe(live.rect.h)
		expect(live.rect.h).toBe(before)
		-- ...and the child carries no record of its own to do it with
		expect(live.props.transform).toBe(nil)
	end)

	it("the record CLEARS at settle — the transform goes back to nil, not to a zero residue", function()
		local w = sizeWorld()
		w.pres.withAnimation("container", function()
			w.tall:set(true)
		end)
		settle(w.pres)
		-- RascalRally's luauui_sponsor_entry.spec asserts `props.transform == nil`
		-- at rest in six places; a size animation that left `{w=0,h=0}` behind would
		-- break the game's own invariant while every count here still read zero
		expect(w.adapter.node("/S/Panel").props.transform).toBe(nil)
		expect(w.pres.animationRecordCount()).toBe(0)
		local panel = w.adapter.node("/S/Panel")
		expect(panel.presentedSize.h).toBe(panel.rect.h)
	end)

	--[[ REDUCED MOTION, AND THE ASSERTION THAT ACTUALLY BITES.

		The policy is inherited, not re-decided: `withAnimation` is DECORATIVE
		motion (the exact layout already carries every fact and the travel was
		pure continuity), so under reduced motion it installs NO records —
		src/present/presenter.luau's explicit `motionClock:isReduced()` branch.
		Size changes nothing about that; a size that snaps loses no information
		for the same reason a position that snaps loses none.

		A RECORD-COUNT ASSERTION CANNOT SEE THAT BRANCH, and this was measured
		(mutation M5, 2026-08-14): deleting the branch outright reddened NOTHING,
		here or in the pre-existing reduced-motion case. Under reduced motion the
		spring settles synchronously inside `setTarget`, and `claim` registers
		`onSettle` BEFORE aiming, so records install and clear inside the same
		call — the count is 0 either way and the paint is exact either way.

		So the check is on what the branch actually buys, which is what the design
		said all along: no writes. "Install and immediately clear" is two rounds of
		amplified subtree writes per root for a visual no-op. Counting the adapter
		ops is the only instrument that can tell the two implementations apart. ]]
	it("reduced motion installs no size record — and spends no adapter write to do it", function()
		local w = sizeWorld({ reducedMotion = true })
		w.adapter.takeOps()
		w.pres.withAnimation("container", function()
			w.tall:set(true)
		end)
		local transformWrites = 0
		for _, op in w.adapter.takeOps() do
			if string.find(op, ".transform=", 1, true) ~= nil then
				transformWrites += 1
			end
		end
		expect(transformWrites).toBe(0)
		local panel = w.adapter.node("/S/Panel")
		expect(panel.rect.h).toBe(200)
		expect(panel.presentedSize.h).toBe(200)
		expect(w.pres.animationRecordCount()).toBe(0)
	end)

	it("a second call mid-flight RE-BASES the size instead of snapping it", function()
		local w = sizeWorld()
		w.pres.withAnimation("container", function()
			w.tall:set(true)
		end)
		for _ = 1, 6 do
			w.pres.tick(FRAME)
		end
		local midFlight = w.adapter.node("/S/Panel").presentedSize.h
		w.pres.withAnimation("container", function()
			w.tall:set(false)
		end)
		local afterClaim = w.adapter.node("/S/Panel").presentedSize.h
		-- a restart would snap the painted height to 200 (the new "old place");
		-- a re-base continues from the pixel height that is actually on screen
		expect(math.abs(afterClaim - midFlight) < 1).toBe(true)
		settle(w.pres)
		local panel = w.adapter.node("/S/Panel")
		expect(panel.presentedSize.h).toBe(panel.rect.h)
		expect(w.pres.animationRecordCount()).toBe(0)
	end)

	it("an ordinary refresh outside a call paints the size instantly, as it always did", function()
		local w = sizeWorld()
		w.tall:set(true)
		w.pres.refresh()
		local panel = w.adapter.node("/S/Panel")
		expect(panel.presentedSize.h).toBe(panel.rect.h)
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
