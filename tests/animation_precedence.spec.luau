--!strict
-- `withAnimation` PRECEDENCE vs the keep-visible offset — RED-TEAM Milestone 1,
-- BLOCKER 1.
--
-- THE DEFECT. `presenter.present` wires every contribution that declares a
-- `keepVisibleOffset` (every `UI.TextInput` does) to
-- `controller.setPresentationOffset`, and calls it ONCE eagerly at present time
-- with the current max — which is `0`. `setPresentationOffset` starts from
-- `lastOffsetY = nil`, so `0 ~= nil` and it writes the ZERO transform
-- `{x = 0, y = -0}` onto the ROOT path. `lastTransform[root]` is now non-nil
-- forever.
--
-- `installAnimationRecords`' walk then hit a precedence rule that read
-- "another writer owns this path, so take its WHOLE SUBTREE out of this diff" —
-- and the root's subtree is the ENTIRE surface. Every subsequent
-- `withAnimation` on that surface installed ZERO records, snapped, and said
-- nothing: no error, no diagnostic. The suite was green only because no shipped
-- surface combined a text field with `withAnimation`.
--
-- THE FIX (renderer.luau, `installAnimationRecords`): the precedence rule
-- exists so two writers cannot contend for ONE `lastTransform` slot. That is a
-- statement about the NODE, not its descendants — so the owned node is skipped
-- and the walk CONTINUES into its children with `inh` unchanged. `inh` is the
-- composed delta from records installed IN THIS DIFF; a foreign writer's shift
-- (keep-visible, a structural transition) is not part of that composition and
-- is added on top by both accumulating halves of the presentation channel, so
-- passing `inh` through unchanged is exactly right.
--
-- Every case here mounts a `UI.TextInput` beside the animated node. Its absence
-- is why the defect survived a green suite.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local fake_target = require("./lib/fake_target")

local FRAME = 1 / 60

local function settle(pres: any)
	for _ = 1, 120 do
		pres.tick(FRAME)
	end
end

-- The same world `with_animation.spec` uses — a header whose height is bound to
-- a signal, and a body below it that moves when the signal flips — plus the one
-- ingredient that broke it: a `UI.TextInput`, mounted BESIDE the animated node.
local function world(opts: any?)
	local options = opts or {}
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)

	local tall = core:signal(false)
	local headerHeight = core:memo(function(use: any)
		return { type = "fixed", px = if use(tall) then 200 else 100 }
	end)
	local UI = Facet.UI

	local children: { any } = {
		UI.Box({ id = "Header", height = headerHeight }),
	}
	local field: any = nil
	if options.textInput ~= false then
		field = Facet.newTextInput(Facet, core, {
			id = "Field",
			value = core:signal("hi"),
			env = env,
			actionSystem = system,
		})
		table.insert(children, field.blueprint)
	end
	table.insert(
		children,
		UI.VStack({
			id = "Body",
			padding = 0,
			gap = 0,
			height = { type = "fixed", px = 100 },
			children = { UI.Text({ id = "Line", text = "row" }) },
		})
	)

	local handle = pres.present(UI.Screen({ id = "S", padding = 0, gap = 0, children = children }), options.presentOpts)
	pres.refresh()
	return { core = core, env = env, adapter = adapter, pres = pres, tall = tall, handle = handle, field = field }
end

describe("withAnimation survives a keep-visible writer on the root (BLOCKER 1)", function()
	it("a surface holding a UI.TextInput still installs records and flies", function()
		local w = world()
		-- the precondition that made this defect real: the root ALREADY carries a
		-- transform at boot, written by the eager keep-visible wiring. If this
		-- ever stops being true the case below stops proving anything, so it is
		-- asserted rather than assumed.
		expect(w.adapter.node("/S").props.transform ~= nil).toBe(true)

		local before = w.adapter.node("/S/Body").rect.y
		w.pres.withAnimation("container", function()
			w.tall:set(true)
		end)
		-- the solve is exact and instant, as always
		expect(w.adapter.node("/S/Body").rect.y).toBe(before + 100)
		-- ...and the PAINT starts where it was. Pre-fix: `animationRecordCount()`
		-- was 0, `/S/Body` carried no transform, and the painted position equalled
		-- the new rect — a silent snap.
		--
		-- The count is asserted as "some", not as an exact number, on purpose: a
		-- `UI.TextInput` carries a `UI.When` whose false branch is a handle with no
		-- solved rect, and such a node takes a COMPENSATING record (R2 #8) so it is
		-- held still while its parent flies. That is pre-existing behaviour, reached
		-- identically by a bare `UI.When` under no owned ancestor at all, and it is
		-- not what this case is about. The STRUCTURAL pin below is the exact one.
		expect(w.pres.animationRecordCount() > 0).toBe(true)
		expect(w.adapter.node("/S/Body").props.transform.y).toBe(-100)
		expect(w.adapter.node("/S/Body").presentedPosition.y).toBe(before)
		w.pres.tick(FRAME)
		local mid = w.adapter.node("/S/Body").presentedPosition.y
		expect(mid > before).toBe(true)
		expect(mid < before + 100).toBe(true)
		settle(w.pres)
		local node = w.adapter.node("/S/Body")
		expect(node.presentedPosition.y).toBe(node.rect.y)
		expect(w.pres.animationRecordCount()).toBe(0)
	end)

	it("`present(bp, { keepVisibleOffset = signal })` reproduces it without any control", function()
		-- the same root ownership, reached through the PUBLIC present option
		-- rather than a control's bundle — proof the defect was the precedence
		-- rule and not anything text-field-specific.
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local tall = core:signal(false)
		local headerHeight = core:memo(function(use: any)
			return { type = "fixed", px = if use(tall) then 200 else 100 }
		end)
		local UI = Facet.UI
		pres.present(
			UI.Screen({
				id = "S",
				padding = 0,
				gap = 0,
				children = {
					UI.Box({ id = "Header", height = headerHeight }),
					UI.VStack({
						id = "Body",
						padding = 0,
						gap = 0,
						height = { type = "fixed", px = 100 },
						children = { UI.Text({ id = "Line", text = "row" }) },
					}),
				},
			}),
			{ keepVisibleOffset = core:signal(0) }
		)
		pres.refresh()
		expect(adapter.node("/S").props.transform ~= nil).toBe(true)

		local before = adapter.node("/S/Body").rect.y
		pres.withAnimation("container", function()
			tall:set(true)
		end)
		-- 2 = the Body's POSITION record + the Header's SIZE record. It read 1 until
		-- `withAnimation` learned to animate size (2026-08-14); what this case is
		-- about is that the count is not ZERO, which is what the whole-subtree
		-- exclusion produced on any surface holding a keep-visible writer.
		expect(pres.animationRecordCount()).toBe(2)
		expect(adapter.node("/S/Body").presentedPosition.y).toBe(before)
	end)

	it("the owned node itself is still NOT claimed — one writer per slot", function()
		-- THE PRECEDENCE RULE'S ACTUAL JOB, which the fix must not undo.
		--
		-- THE OWNED NODE HAS TO MOVE, or this case proves nothing. A first draft
		-- flipped the header and asserted the root's transform was untouched — but
		-- the root's rect does not move when a header grows, so its own delta is
		-- zero and NO implementation would claim it. Deleting the precedence check
		-- outright (`local owned = false`) left that draft, and the entire suite,
		-- green. What moves the root is the SAFE AREA, so that is what this changes
		-- inside the animated call.
		local w = world()
		local rootT = w.adapter.node("/S").props.transform
		expect(rootT ~= nil).toBe(true)
		local bodyBefore = w.adapter.node("/S/Body").rect.y
		w.pres.withAnimation("container", function()
			-- a 30px top inset arrives (a rotation, a notch, the Roblox topbar):
			-- the root's own rect moves 0 -> 30 and every child rides it down
			w.env:set("coreSafeInsets", { top = 30, bottom = 0, left = 0, right = 0 })
		end)
		-- the root's slot is byte-for-byte what keep-visible left there. Without the
		-- rule the animation claims it and writes {0,-30} over the keep-visible
		-- value, and the two writers then alternate on one slot for the rest of the
		-- surface's life — the exact contention the rule exists to prevent.
		local after = w.adapter.node("/S").props.transform
		expect(w.adapter.node("/S").rect.y).toBe(30)
		expect(after.x).toBe(rootT.x)
		expect(after.y).toBe(rootT.y)
		-- ...and because the root did NOT absorb the move, each child carries its
		-- own full delta instead, so the flight still happens
		expect(w.adapter.node("/S/Body").rect.y).toBe(bodyBefore + 30)
		expect(w.adapter.node("/S/Body").props.transform.y).toBe(-30)
		expect(w.adapter.node("/S/Body").presentedPosition.y).toBe(bodyBefore)
		settle(w.pres)
		expect(w.adapter.node("/S/Body").presentedPosition.y).toBe(w.adapter.node("/S/Body").rect.y)
	end)

	it("a live keep-visible shift COMPOSES with a record beneath it rather than being absorbed", function()
		-- the harder half: the root is not merely owned, it is owned at a
		-- NON-ZERO offset. The animation record under it is relative to the
		-- solved rect; the keep-visible shift is added on top by the
		-- accumulating channel. Passing `inh` through unchanged is what makes
		-- that sum come out right.
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local tall = core:signal(false)
		local lift = core:signal(0)
		local headerHeight = core:memo(function(use: any)
			return { type = "fixed", px = if use(tall) then 200 else 100 }
		end)
		local UI = Facet.UI
		pres.present(
			UI.Screen({
				id = "S",
				padding = 0,
				gap = 0,
				children = {
					UI.Box({ id = "Header", height = headerHeight }),
					UI.VStack({
						id = "Body",
						padding = 0,
						gap = 0,
						height = { type = "fixed", px = 100 },
						children = { UI.Text({ id = "Line", text = "row" }) },
					}),
				},
			}),
			{ keepVisibleOffset = lift }
		)
		pres.refresh()
		lift:set(40) -- the keyboard is up: the whole surface rides 40px up
		pres.refresh()
		local before = adapter.node("/S/Body").rect.y
		pres.withAnimation("container", function()
			tall:set(true)
		end)
		-- the Body's position + the Header's size (1 before size was animated)
		expect(pres.animationRecordCount()).toBe(2)
		-- painted = solved rect + own record (-100) + the root's -40. At the seed
		-- the body must appear exactly where the player last saw it: its OLD rect
		-- lifted by 40.
		expect(adapter.node("/S/Body").presentedPosition.y).toBe(before - 40)
		settle(pres)
		-- ...and it lands at the new rect, still lifted by 40 — the keep-visible
		-- shift is not consumed by the flight
		expect(adapter.node("/S/Body").presentedPosition.y).toBe(adapter.node("/S/Body").rect.y - 40)
	end)

	it("the no-TextInput surface is unchanged (the control case)", function()
		local w = world({ textInput = false })
		local before = w.adapter.node("/S/Body").rect.y
		w.pres.withAnimation("container", function()
			w.tall:set(true)
		end)
		-- the Body's position + the Header's size (1 before size was animated)
		expect(w.pres.animationRecordCount()).toBe(2)
		expect(w.adapter.node("/S/Body").presentedPosition.y).toBe(before)
	end)
end)
