--!strict
--[[ THE Z BAND IS A FUNCTION OF THE TREE, NOT OF HISTORY (NM-H4a).

	MEASURED ON THE LIVE ADAPTER, 2026-08-17, in a Studio Play session on the built
	showcase, driving the director's own sequence and comparing the whole engine
	tree against a fresh mount at the same viewport:

	    driven=86 nodes  fresh=86 nodes  DIVERGENCES=73
	    ...and every one of the 73 is `zIndex` alone. Position, size and visibility
	    are identical.

	WHY. `syncZOrder` reserves a slot below any node that carries a hit expander,
	because the adapter paints that expander at `hostZ - 1` and without the
	reservation the number belongs to whatever node was walked immediately before —
	a TIE, which the engine breaks by insertion order, i.e. by exactly the
	non-determinism the explicit walk exists to remove.

	It decided that by reading `lastHitRects`, which is the set of expanders that
	exist RIGHT NOW. On a first structural sync that set is empty — the rects have
	not been pushed yet — so nothing is reserved:

	    z=26  /HudScreen/Hud/Rounds/RoundStrip/R1      36x36 @59,62
	    z=26  FacetHitExpander                        44x44 @97,58   <- R2's
	    z=27  /HudScreen/Hud/Rounds/RoundStrip/R2      36x36 @101,62
	    z=27  FacetHitExpander                        44x44 @139,58  <- R3's

	Every expander sitting on the previous button's number, on a freshly mounted
	screen, live. A later sync — after any structural change, which a rotation
	provides — finds the rects present, reserves, and the whole band moves under
	everything. That is the 73.

	A HIT FLOOR IS A FACT ABOUT THE CLASS, not about what has been pushed, so the
	reservation now reads `effectiveHitFloor` and the band is stable from the first
	sync onward.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local fake_target = require("../tests/lib/fake_target")

local UI = Facet.UI

local function world(): any
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 734, h = 393 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	return { core = core, env = env, adapter = adapter, pres = pres, system = system }
end

--[[ THREE SUB-FLOOR CIRCLES IN A ROW: the shape the live measurement came off, and
	the one that needs a reservation each. A 36px control under a 44px floor is what
	makes the adapter ask for an expander at all. ]]
local function discs(w: any, extra: number): any
	local kids = {}
	for i = 1, 3 + extra do
		table.insert(
			kids,
			UI.Button({
				id = `R{i}`,
				label = "-",
				shape = "circle",
				padding = 0,
				-- one axis only: the solver enforces the 1:1 square for a circle
				width = { type = "fixed", px = 36 },
			})
		)
	end
	return w.pres.present(
		UI.Screen({ id = "S", children = { UI.HStack({ id = "Row", gap = 6, children = kids }) } }),
		{}
	)
end

local function zOf(w: any, path: string): number?
	local n = w.adapter.node(path)
	return if n ~= nil then n.z else nil
end

describe("NM-H4a: the hit-expander z reservation is a fact about the class", function()
	it("a FIRST sync already reserves — the expanders cannot tie with the buttons", function()
		local w = world()
		discs(w, 0)
		w.pres.refresh()
		local z1, z2, z3 = zOf(w, "/S/Row/R1"), zOf(w, "/S/Row/R2"), zOf(w, "/S/Row/R3")
		expect(z1 ~= nil).toBe(true)
		--[[ The adapter paints an expander at `hostZ - 1`, so consecutive numbers on
			three sub-floor controls means R2's expander lands on R1 — measured live as
			exactly that. A reserved slot each puts them two apart. ]]
		expect((z2 :: number) - (z1 :: number)).toBe(2)
		expect((z3 :: number) - (z2 :: number)).toBe(2)
	end)

	it("...and the band does not move when a later solve happens", function()
		--[[ The 73-node drift: the same tree, read before and after further solves.
			A band that is a function of the tree is the same band every time. ]]
		local w = world()
		discs(w, 0)
		w.pres.refresh()
		local before = { zOf(w, "/S/Row/R1"), zOf(w, "/S/Row/R2"), zOf(w, "/S/Row/R3") }
		for _ = 1, 4 do
			w.env:set("viewportRect", { x = 0, y = 0, w = 393, h = 759 })
			w.pres.refresh()
			w.env:set("viewportRect", { x = 0, y = 0, w = 734, h = 393 })
			w.pres.refresh()
		end
		local after = { zOf(w, "/S/Row/R1"), zOf(w, "/S/Row/R2"), zOf(w, "/S/Row/R3") }
		expect(`{after[1]}|{after[2]}|{after[3]}`).toBe(`{before[1]}|{before[2]}|{before[3]}`)
	end)

	it("a driven surface's band equals a FRESH one's — the live divergence, headless", function()
		local driven = world()
		discs(driven, 0)
		driven.pres.refresh()
		for _ = 1, 3 do
			driven.env:set("viewportRect", { x = 0, y = 0, w = 393, h = 759 })
			driven.pres.refresh()
			driven.env:set("viewportRect", { x = 0, y = 0, w = 734, h = 393 })
			driven.pres.refresh()
		end
		local fresh = world()
		discs(fresh, 0)
		fresh.pres.refresh()
		local diffs = {}
		for _, path in driven.adapter.paths() do
			local a, b = zOf(driven, path), zOf(fresh, path)
			if a ~= b then
				table.insert(diffs, `{path} driven={tostring(a)} fresh={tostring(b)}`)
			end
		end
		expect(table.concat(diffs, " ; ")).toBe("")
	end)

	it("a node with NO floor reserves nothing — the band is not padded", function()
		-- the negative control: a reservation for every node would be a band twice as
		-- deep and would prove nothing about expanders
		local w = world()
		w.pres.present(
			UI.Screen({
				id = "T",
				children = {
					UI.VStack({
						id = "Col",
						children = {
							UI.Text({ id = "A", text = "a" }),
							UI.Text({ id = "B", text = "b" }),
						},
					}),
				},
			}),
			{}
		)
		w.pres.refresh()
		local a, b = zOf(w, "/T/Col/A"), zOf(w, "/T/Col/B")
		expect((b :: number) - (a :: number)).toBe(1)
	end)
end)
