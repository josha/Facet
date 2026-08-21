--!strict
--[[
	ONE VIEWPORT CHANGE IS ONE SOLVE (docs/plans/parity-round3.md, item E
	-- the measurement story).

	L-27 recorded "one viewport change costs 5 solves and 2 structural syncs,
	reproducibly" and left the conclusion "the lever for a resize is the solve
	COUNT, not the solve". The 2026-08-13 device capture (rr.html) put a number
	on it: arrange 8.270 ms/occurrence, measure 3.057 ms/occurrence, 9.67
	arranges per step, arrange+measure = 58.5% of wall. Five solves where one
	would do is ~45 ms of a ~200 ms frame.

	The cause is two multipliers that compound, and BOTH have to go:

	  1. `src/client/roblox_env.luau` `pushViewport()` writes SIX facts on one
	     real resize (viewportRect, coreSafeInsets, deviceSafeInsets,
	     topbarSafeInsets, topbarInset, displaySize). Unbatched, each write is
	     its own flush.
	  2. `src/render/renderer.luau` observed EIGHT geometry keys INDEPENDENTLY,
	     each callback running a full `solveAndApply()`.

	Measured on 2026-08-13 with tools/lune/_probe_solves against a 40-row tree:
	six unbatched writes + eight observers = 5 solves (L-27's number exactly).
	Batching alone = 5. One coalescing memo alone = 4. Both = 1.

	WHAT EACH BLOCK WOULD CATCH:

	  · "a batched geometry change is ONE solve" -> the regression this whole
	    entry exists to prevent: someone re-splitting the coalescing memo back
	    into per-key observers, or dropping the adapter's batch. This is the
	    only check here that fails on today's shipped code.
	  · "every geometry key still re-solves" -> the way a coalescing memo goes
	    wrong is by reading FEWER keys than it replaced, which is silent: the
	    surface simply stops responding to (say) preferredTextOffset. Each key
	    is driven individually and must still cost exactly one solve, so a
	    dropped dependency reddens as 0.
	  · "an edgeToEdge surface does not re-solve for a safe-area inset" -> the
	    ONE narrowing of that rule (L-31), and the differential that keeps it
	    honest: an edgeToEdge surface is defined not to consume a safe-area
	    inset, so watching one is pure waste — but a narrowing is exactly how a
	    memo goes silently deaf, so the identical-rects proof is the licence.
	  · "a non-geometry write does not solve" -> the opposite failure: a memo
	    that returns a fresh identity on every flush would re-solve the whole
	    surface on any unrelated environment write.
	  · "env:batch is the general mechanism" -> that the adapter's batching is
	    the core's existing transaction, not a second bespoke one.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src")
local fake_target = require("./lib/fake_target")

-- the eight facts the renderer re-solves for, and a distinct value for each
local GEOMETRY: { { key: string, a: any, b: any } } = {
	{ key = "viewportRect", a = { x = 0, y = 0, w = 900, h = 700 }, b = { x = 0, y = 0, w = 600, h = 700 } },
	{
		key = "coreSafeInsets",
		a = { top = 0, bottom = 0, left = 0, right = 0 },
		b = { top = 36, bottom = 0, left = 0, right = 0 },
	},
	{
		key = "deviceSafeInsets",
		a = { top = 0, bottom = 0, left = 0, right = 0 },
		b = { top = 44, bottom = 34, left = 0, right = 0 },
	},
	{
		key = "overscanInsets",
		a = { top = 0, bottom = 0, left = 0, right = 0 },
		b = { top = 8, bottom = 8, left = 8, right = 8 },
	},
	-- Small|Medium|Large; `Large` is the TV class, so drive Medium->Small to
	-- exercise the key without flipping the surface into a ten-foot layout
	{ key = "displaySize", a = "Medium", b = "Small" },
	{ key = "preferredTextOffset", a = 0, b = 10 },
	{ key = "themeMetrics", a = nil, b = { density = 2 } },
}

local function harness(rowCount: number?)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 900, h = 700 })
	local system = Facet.newActionSystem(core)
	local pres = Facet.newPresenter(core, env, fake_target.new(), system)

	local rows = {}
	for i = 1, rowCount or 40 do
		table.insert(
			rows,
			Facet.UI.HStack({
				id = "R" .. i,
				width = { type = "fill", weight = 1 },
				children = {
					Facet.UI.Text({ id = "A", text = "Row " .. i }),
					Facet.UI.Spacer({ id = "S" }),
					Facet.UI.Text({ id = "B", text = "value " .. i }),
				},
			})
		)
	end
	local handle =
		pres.present(Facet.UI.Screen({ id = "S", children = { Facet.UI.VStack({ id = "List", children = rows }) } }))
	pres.refresh()

	local function solves(): number
		return ((handle.controller.stats() :: any).solves :: number) or 0
	end

	return core, env, pres, solves
end

describe("one geometry change is one solve", function()
	it("a batched geometry change is ONE solve", function()
		local _core, env, pres, solves = harness()

		-- exactly the shape of roblox_env.pushViewport(): several facts, one
		-- real resize. Unbatched + per-key observers, this measured 5.
		local before = solves()
		env:batch(function()
			env:set("viewportRect", { x = 0, y = 0, w = 360, h = 691 })
			env:set("coreSafeInsets", { top = 36, bottom = 0, left = 0, right = 0 })
			env:set("deviceSafeInsets", { top = 44, bottom = 34, left = 0, right = 0 })
			env:set("topbarSafeInsets", { top = 36, bottom = 0, left = 0, right = 0 })
			env:set("topbarInset", { x = 0, y = 0, w = 360, h = 36 })
			-- displaySize is Small|Medium|Large, NOT the size class, and `Large`
			-- alone means TELEVISION (typographyScale 1.5, ten-foot, overscan).
			-- The adapter publishes it on every pushViewport; a rotation does not
			-- change it. Held constant so this measures batching, not a TV swap.
			env:set("displaySize", "Medium")
		end)
		pres.refresh()

		expect(solves() - before).toBe(1)
	end)

	it("every geometry key still re-solves", function()
		for _, fact in GEOMETRY do
			local _core, env, pres, solves = harness(8)
			env:set(fact.key, fact.a)
			pres.refresh()

			local before = solves()
			env:set(fact.key, fact.b)
			pres.refresh()

			-- exactly one: 0 means the coalescing memo stopped reading this key
			-- and the surface is now deaf to it; >1 means it is still fanned out.
			expect(solves() - before).toBe(1)
		end
	end)

	it("typographyScale is covered — the DERIVED key nothing could drive directly", function()
		--[[ ARCHITECTURE GATE F4, 2026-08-14. The renderer's memo reads EIGHT keys
			and the `GEOMETRY` table above drives SEVEN. `typographyScale` is absent
			and correctly so — it is derived and cannot be `env:set` — but that left
			it genuinely uncovered: delete `"typographyScale"` from GEOMETRY_KEYS and
			no case reddened, while every surface went deaf to the player's text-size
			preference. The neighbouring `preferredTextSize` case asserts a CLAMPED
			no-op costs zero solves, so it cannot cover this either.

			Drive it through its real dependency, at values that actually move the
			derived scale. ]]
		local _core, env, pres, solves = harness(8)
		env:set("preferredTextSize", 1)
		pres.refresh()

		local before = solves()
		env:set("preferredTextSize", 2)
		pres.refresh()
		expect(solves() - before).toBe(1)
	end)

	it("a nested geometry fact is REFUSED, not half-compared", function()
		--[[ ARCHITECTURE GATE F3, 2026-08-14. The value comparison walks one level.
			A nested fact whose OUTER table is rebuilt while an inner table is reused
			by reference would compare equal and report "unchanged" — a MISSED
			re-solve, the surface going silently deaf. Any table-valued field now
			returns false instead. `themeMetrics` is the one key that takes an
			arbitrary table, so it is the one that can carry the shape. ]]
		local _core, env, pres, solves = harness(8)
		local shared = { a = 1 }
		env:set("themeMetrics", { nested = shared, density = 1 })
		pres.refresh()

		local before = solves()
		-- outer rebuilt, inner REUSED by reference: identity comparison would call
		-- this unchanged and never re-solve
		env:set("themeMetrics", { nested = shared, density = 1 })
		pres.refresh()
		expect(solves() - before).toBe(1)
	end)

	it("an edgeToEdge surface does not re-solve for a safe-area inset — proved by a differential", function()
		--[[ L-31, 2026-08-14. `solveAndApply` opens with

		      if rootPolicy == "edgeToEdge" then insets = { 0, 0, 0, 0 }

		    — it READS `coreSafeInsets` and throws the value away, and never reads
		    `deviceSafeInsets` at all. Both were nonetheless in the coalescing
		    memo, so every scrim, backdrop and dock re-solved for an inset it is
		    defined to ignore. The shipped case that hurts: a dock which PUBLISHES
		    its measured height into `coreSafeInsets` re-solved for its own
		    publication, every time.

		    "IT DOES NOT MATTER" IS A CLAIM, SO IT IS MEASURED. The case above
		    ("every geometry key still re-solves") exists because a memo that reads
		    fewer keys than it replaced goes SILENTLY deaf, and this is exactly that
		    shape — so asserting 0 solves alone would be asserting the hazard. The
		    differential is the proof: two identical surfaces in two cores, one laid
		    out under a fat inset and one under none, must produce IDENTICAL rects.
		    If they ever differ, the narrowing is wrong and this reddens rather than
		    the surface going quietly wrong on a device with a notch.

		    MUTATION NOTE, because it cost a round to find: `edgeToEdge` has TWO
		    independent authorities — the renderer zeroes `insets` before the solve
		    (renderer.luau, `if rootPolicy == "edgeToEdge"`) AND the solver takes the
		    whole viewport as the content rect (solver.luau, `if policy ==
		    "edgeToEdge"`). Breaking either one alone leaves this case GREEN, because
		    the other still holds. Both have to go to see the differential redden.

		    (Rascal Rally's role-pick modal is `rootPolicy = "edgeToEdge"`, so its
		    consumer rider — games/RascalRally/code/tests/facet_resize_solve_contract
		    — carries the same pair of assertions against the shipped surface.) ]]
		local PATHS = { "/S", "/S/List", "/S/List/R1", "/S/List/R1/A", "/S/List/R4/B", "/S/List/R8" }
		local function edgeToEdgeRects(inset: number): { [string]: string }
			local core = Facet.newCore()
			local env = Facet.newEnvironment(core)
			env:set("viewportRect", { x = 0, y = 0, w = 900, h = 700 })
			env:set("coreSafeInsets", { top = inset, bottom = inset, left = inset, right = inset })
			env:set("deviceSafeInsets", { top = inset, bottom = inset, left = inset, right = inset })
			local pres = Facet.newPresenter(core, env, fake_target.new(), Facet.newActionSystem(core))
			local rows = {}
			for i = 1, 8 do
				table.insert(
					rows,
					Facet.UI.HStack({
						id = "R" .. i,
						width = { type = "fill", weight = 1 },
						children = {
							Facet.UI.Text({ id = "A", text = "Row " .. i }),
							Facet.UI.Spacer({ id = "S" }),
							Facet.UI.Text({ id = "B", text = "value " .. i }),
						},
					})
				)
			end
			local handle = pres.present(
				Facet.UI.Screen({ id = "S", children = { Facet.UI.VStack({ id = "List", children = rows }) } }),
				{ rootPolicy = "edgeToEdge" }
			)
			pres.refresh()
			local out: { [string]: string } = {}
			for _, path in PATHS do
				local r = handle.controller.rectOf(path) :: any
				out[path] = if r == nil then "nil" else `{r.x},{r.y},{r.w},{r.h}`
			end
			return out
		end

		local none, fat = edgeToEdgeRects(0), edgeToEdgeRects(60)
		for _, path in PATHS do
			-- "nil" everywhere would make this vacuous
			expect(none[path]).never().toBe("nil")
			expect(fat[path]).toBe(none[path])
		end

		-- ...and therefore the re-solve is waste, and is gone
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 900, h = 700 })
		local pres = Facet.newPresenter(core, env, fake_target.new(), Facet.newActionSystem(core))
		local handle = pres.present(
			Facet.UI.Screen({ id = "S", children = { Facet.UI.Text({ id = "T", text = "edge" }) } }),
			{ rootPolicy = "edgeToEdge" }
		)
		pres.refresh()
		local function solves(): number
			return ((handle.controller.stats() :: any).solves :: number) or 0
		end
		local before = solves()
		env:set("coreSafeInsets", { top = 36, bottom = 0, left = 0, right = 0 })
		env:set("deviceSafeInsets", { top = 44, bottom = 34, left = 0, right = 0 })
		pres.refresh()
		expect(solves() - before).toBe(0)
		-- the surface is NOT deaf in general: a fact it does consume still solves
		env:set("viewportRect", { x = 0, y = 0, w = 600, h = 700 })
		pres.refresh()
		expect(solves() - before).toBe(1)
	end)

	it("a non-geometry write does not solve", function()
		local _core, env, pres, solves = harness(8)
		local before = solves()
		env:set("reducedMotion", true)
		env:set("preferredTransparency", 0.5)
		pres.refresh()
		expect(solves() - before).toBe(0)
	end)

	it("a set-and-revert inside one batch costs NOTHING", function()
		--[[ RED-TEAM 2026-08-13. The first cut of the coalescing memo returned a
			fresh `{}` per recompute, so identity-inequality meant "recomputed",
			not "changed". That discarded both guarantees `src/core/custom.luau`
			states in its own header — "set-and-revert transactions and unchanged
			recomputes [are] fire-free" — and it discarded them in the exact
			dimension this whole entry exists to reduce. Measured then: 1 solve
			where there had been 0. ]]
		local _core, env, pres, solves = harness(8)
		local before = solves()
		env:batch(function()
			env:set("viewportRect", { x = 0, y = 0, w = 500, h = 700 })
			env:set("viewportRect", { x = 0, y = 0, w = 900, h = 700 }) -- back where it started
		end)
		pres.refresh()
		expect(solves() - before).toBe(0)
	end)

	it("a write that moves NO geometry value costs nothing", function()
		-- `typographyScale` is a memo over displaySize + preferredTextOffset and
		-- clamps: two different preferredTextSize values can produce the SAME
		-- scale. Recomputed-but-unchanged must not re-solve the surface.
		local _core, env, pres, solves = harness(8)
		env:set("preferredTextSize", 4)
		pres.refresh()
		local before = solves()
		env:set("preferredTextSize", 9)
		pres.refresh()
		expect(solves() - before).toBe(0)
	end)

	it("re-publishing the SAME numbers in a fresh table costs nothing", function()
		--[[ THE REAL-WORLD CASE, and the reason the memo compares by content.
			`roblox_env.pushViewport()` builds a BRAND NEW rect and inset tables
			every time it runs, and it runs on `TopbarInset` changes as well as on
			resizes. Under table-identity comparison, a topbar change alone
			re-solved the whole surface for a viewport that had not moved. ]]
		local _core, env, pres, solves = harness(8)
		local before = solves()
		for _ = 1, 3 do
			env:batch(function()
				env:set("viewportRect", { x = 0, y = 0, w = 900, h = 700 }) -- identical numbers
				env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
				env:set("deviceSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
			end)
			pres.refresh()
		end
		expect(solves() - before).toBe(0)
	end)

	it("consumers on SEPARATE memos are notified in creation order", function()
		--[[ RED-TEAM 2026-08-13. Coalescing moved each surface's solve observer off
			the shared env signal onto its OWN memo. `notify` sorts observers by seq
			WITHIN one node, which gave a total order only while every consumer
			observed the same signal; `flushBody` builds its queue by iterating
			tables keyed by node REFERENCES, and hash order is not an order. Measured
			solve order across six surfaces varying run to run within one process.

			A FIRST CUT OF THIS CASE PROVED NOTHING. It presented six surfaces and
			compared their `onGeometry` order across three runs — and passed with the
			sort REMOVED, because six small surfaces happened to hash stably. Twelve
			memos do not: without the sort this reads `4,10,6,9,8,12,11,7,3,2,5,1`,
			then `1,11,7,2,6,3,5,9,12,10,4,8`, then `4,11,1,9,7,3,2,12,6,8,5,10`.
			That is the shape a determinism check has to have — seen to fail. ]]
		local core = Facet.newCore()
		local sig = core:signal(0)
		local order: { number } = {}
		for i = 1, 12 do
			local m = core:memo(function(use)
				return use(sig) + i
			end)
			core:observe(m, function()
				table.insert(order, i)
			end)
		end
		sig:set(1)

		local expected = {}
		for i = 1, 12 do
			table.insert(expected, tostring(i))
		end
		expect(table.concat(order, ",")).toBe(table.concat(expected, ","))
	end)

	it("env:batch is the general mechanism", function()
		local _core, env, pres, solves = harness(8)

		-- nested batches collapse to the outermost, and the batch is the core's
		-- own transaction: a write inside is not visible to an observer until
		-- the outer one closes, so the whole group costs one solve.
		local before = solves()
		env:batch(function()
			env:set("viewportRect", { x = 0, y = 0, w = 500, h = 700 })
			env:batch(function()
				env:set("displaySize", "Small")
			end)
			env:set("preferredTextOffset", 4)
		end)
		pres.refresh()
		expect(solves() - before).toBe(1)
	end)
end)

--[[ ── O-20 / L-29 RESIDUAL 2: A GEOMETRY CHANGE THAT ALSO MOVES A BOUND
	LAYOUT PROP IS STILL ONE SOLVE ─────────────────────────────────────────────

	MEASURED, not theorised (2026-08-15, tools/lune/_probe_modal_solves and the
	game-side probe recorded in artifacts/swiftui-parity-round3/o20-modal-solve
	-residual.md). The optimization log booked this as "a second solve site on
	the MODAL PRESENTATION PATH". It is not: `presenter.present` of the same
	blueprint costs exactly what `presenter.presentModal` costs, and a bare modal
	over a plain tree costs 1. What costs 3 is a surface that has a LAYOUT prop
	bound to a memo over the viewport — Rascal Rally's role-pick modal binds
	`width` on its two CTA sub-labels to `{ type = "fixed", px = … }`.

	THE SHAPE, exactly as it ships. The memo returns a FRESH TABLE that is equal
	BY VALUE to the last one (`px` did not move), and the core's default equality
	is identity, so the bound-prop observer fires and pushes `measure` dirt in the
	same flush as the six geometry facts. That much is the consumer's business —
	it costs one prop write. What the framework then charged for it was TWO extra
	FULL solves:

	  1. the settle pass opened with a stale solve-feedback drain. `feedbackArmed`
	     is set whenever a settle-phase solve finishes with a flush still open —
	     including when the listeners published NOTHING — and if the core does not
	     restart the pass, that arm survives into the NEXT flush and fires there
	     against a mark from the previous one. A drain and a geometry solve in the
	     same pass are two full solves of the same tree.
	  2. `controller.refresh()` then solved a THIRD time for `measure` dirt the
	     settle solve had already consumed: the dirt was pushed BEFORE that solve
	     ran, the solve was full, and nothing dirtied the tree afterwards — but
	     `refresh` reads the class off the queue and never asks whether a solve
	     has happened since.

	WHAT EACH CASE WOULD CATCH:

	  · "…is ONE solve, and stays one" -> both amplifiers, and it drives TWO
	    rotations because amplifier 1 only appears on the SECOND (the first
	    geometry change is the one that arms it). A regression to 2 or 3 reddens.
	  · "…and the prop is still LIVE" -> the dangerous direction. Both fixes are
	    "skip a solve"; a skip that goes too far leaves the surface painting the
	    old box. The px is MOVED and the painted rect must move with it. TWO
	    drivers, and the second is the one that bites: moving the px THROUGH THE
	    VIEWPORT is answered by the settle-phase solve whichever way `refresh`
	    decides, so it cannot see an over-eager stale-dirt test at all (measured:
	    that mutation reddens 108 cases across the suite and NOT this one). Moving
	    it through a plain signal leaves `refresh` as the only thing that can solve.
	  · "a solve that a listener really did feed back from still re-solves" ->
	    the drain this narrowing must not break: with no geometry change pending,
	    a consumer publishing from `onSolved` still earns its re-solve.
]]
describe("a geometry change that also moves a bound layout prop", function()
	-- the shipped shape: a layout prop bound to a memo over the viewport that
	-- returns a fresh table of the SAME numbers
	local function boundWidthHarness(pxFor: (number) -> number)
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1920, h = 1080 })
		-- the second driver: a plain signal, so the px can move with NO geometry
		-- change and `refresh` is the only thing that can solve for it
		local nudge = core:signal(0)
		local width = core:memo(function(use)
			local vp = use(env:get("viewportRect")) :: any
			return { type = "fixed", px = pxFor(vp.w) + (use(nudge) :: number) }
		end)
		local system = Facet.newActionSystem(core)
		local pres = Facet.newPresenter(core, env, fake_target.new(), system)
		local handle = pres.present(Facet.UI.Screen({
			id = "S",
			children = {
				Facet.UI.VStack({
					id = "Card",
					children = {
						Facet.UI.Text({ id = "Sub", text = "cause chaos", width = width }),
					},
				}),
			},
		}))
		pres.refresh()
		return env,
			pres,
			handle,
			function(): number
				return ((handle.controller.stats() :: any).solves :: number) or 0
			end,
			nudge
	end

	-- exactly roblox_env.pushViewport()'s fact group, batched
	local function rotate(env: any, w: number, h: number)
		local compact = w < 600
		env:batch(function()
			env:set("viewportRect", { x = 0, y = 0, w = w, h = h })
			env:set("coreSafeInsets", { top = if compact then 36 else 0, bottom = 0, left = 0, right = 0 })
			env:set("deviceSafeInsets", {
				top = if compact then 44 else 0,
				bottom = if compact then 34 else 0,
				left = 0,
				right = 0,
			})
			env:set("topbarSafeInsets", { top = if compact then 36 else 0, bottom = 0, left = 0, right = 0 })
			env:set("topbarInset", { x = 0, y = 0, w = w, h = if compact then 36 else 0 })
			env:set("displaySize", "Medium")
		end)
	end

	it("is ONE solve, and stays one over repeated changes", function()
		-- value-STABLE on purpose: the memo re-evaluates because the viewport
		-- moved, and hands back the same 120 in a new table
		local env, pres, _handle, solves = boundWidthHarness(function()
			return 120
		end)

		-- A/A control: the same refresh with nothing changed, before any delta
		local control = solves()
		pres.refresh()
		expect(solves() - control).toBe(0)

		-- FIRST change. This one measured 2 before the fix.
		local before = solves()
		rotate(env, 1900, 1000)
		pres.refresh()
		expect(solves() - before).toBe(1)

		--[[ SECOND change, and this is the case the Rascal Rally rider could never
			see: it only ever measured the first rotation of a fresh surface, so the
			solve the first one ARMS was charged to a rotation nobody looked at.
			This measured 3. ]]
		before = solves()
		rotate(env, 1901, 1001)
		pres.refresh()
		expect(solves() - before).toBe(1)

		-- ...and a third, so "one" is the steady state rather than a phase
		before = solves()
		rotate(env, 1902, 1002)
		pres.refresh()
		expect(solves() - before).toBe(1)
	end)

	it("...and the prop is still LIVE: a px that really moves moves the rect", function()
		-- the negative control for both skips. Neither fix may make the surface
		-- paint a box the solver has not re-derived.
		local env, pres, handle, _solves, nudge = boundWidthHarness(function(w: number)
			return if w > 600 then 120 else 44
		end)
		local function subWidth(): number
			return ((handle.controller.rectOf("/S/Card/Sub") :: any) or { w = -1 }).w
		end
		expect(subWidth()).toBe(120)

		rotate(env, 500, 900)
		pres.refresh()
		expect(subWidth()).toBe(44)

		rotate(env, 1900, 1000)
		pres.refresh()
		expect(subWidth()).toBe(120)

		--[[ …and the driver a geometry change cannot rescue. A rotation is answered
			by the settle-phase solve however `refresh` decides, so everything above
			this line survives a stale-dirt test that skips EVERYTHING; a px moved
			through a plain signal, after a full solve has run, leaves `refresh` as
			the only thing that can put it on screen. ]]
		nudge:set(30)
		pres.refresh()
		expect(subWidth()).toBe(150)

		-- and back, so the case pins a live binding rather than a one-way latch
		nudge:set(0)
		pres.refresh()
		expect(subWidth()).toBe(120)
	end)

	it("a solve a listener really did feed back from still re-solves", function()
		-- the drain the narrowing must not break: no geometry change is pending,
		-- so the arm is the only thing that can earn this solve
		local env, pres, handle, solves = boundWidthHarness(function()
			return 120
		end)
		local fed = 0
		local unhook = (handle.controller :: any).onSolved(function()
			-- publish once, from the solve, exactly as a dock reserving space does
			if fed == 0 then
				fed += 1
				env:set("overscanInsets", { top = 7, bottom = 0, left = 0, right = 0 })
			end
		end)
		local before = solves()
		env:set("preferredTextOffset", 4)
		pres.refresh()
		expect(fed).toBe(1)
		-- one for the write, one for what the listener published: the drain is
		-- still there. A 1 here would mean the feedback cycle stopped closing.
		expect(solves() - before >= 2).toBe(true)
		unhook()
	end)
end)
